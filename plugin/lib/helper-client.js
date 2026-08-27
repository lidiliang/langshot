'use strict'

const { EventEmitter } = require('node:events')
const { spawn } = require('node:child_process')
const fs = require('node:fs')
const path = require('node:path')
const { createRequest, parseMessage } = require('./protocol')

class HelperClient extends EventEmitter {
  constructor(options = {}) {
    super()
    this.helperPath = options.helperPath || resolveHelperPath()
    this.spawnProcess = options.spawnProcess || spawn
    this.timeoutMs = options.timeoutMs || 5000
    this.process = null
    this.pending = new Map()
    this.buffer = ''
  }

  start() {
    if (this.process) return
    if (!fs.existsSync(this.helperPath)) {
      throw new Error(`langShot helper not found: ${this.helperPath}`)
    }
    const child = this.spawnProcess(this.helperPath, [], {
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env, LANGSHOT_PARENT_PID: String(process.pid) }
    })
    this.process = child
    child.stdout.setEncoding('utf8')
    child.stdout.on('data', chunk => this.#consume(chunk))
    child.stderr.setEncoding('utf8')
    child.stderr.on('data', chunk => this.emit('diagnostic', String(chunk).trim()))
    child.once('exit', (code, signal) => this.#handleExit(code, signal))
    child.once('error', error => this.#handleExit(null, null, error))
  }

  async request(type, payload = {}) {
    this.start()
    const message = createRequest(type, payload)
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(message.requestId)
        reject(new Error(`Helper request timed out: ${type}`))
      }, this.timeoutMs)
      this.pending.set(message.requestId, { resolve, reject, timer })
      this.process.stdin.write(`${JSON.stringify(message)}\n`)
    })
  }

  stop() {
    if (!this.process) return
    this.process.kill('SIGTERM')
    this.process = null
  }

  #consume(chunk) {
    this.buffer += chunk
    let newline = this.buffer.indexOf('\n')
    while (newline >= 0) {
      const line = this.buffer.slice(0, newline).trim()
      this.buffer = this.buffer.slice(newline + 1)
      if (line) this.#dispatch(line)
      newline = this.buffer.indexOf('\n')
    }
  }

  #dispatch(line) {
    let message
    try {
      message = parseMessage(line)
    } catch (error) {
      this.emit('protocolError', error)
      return
    }
    if (message.requestId && this.pending.has(message.requestId)) {
      const pending = this.pending.get(message.requestId)
      this.pending.delete(message.requestId)
      clearTimeout(pending.timer)
      if (message.ok === false) pending.reject(toHelperError(message.error))
      else pending.resolve(message.payload || {})
      return
    }
    this.emit('event', message)
    this.emit(message.type, message.payload || {})
  }

  #handleExit(code, signal, cause) {
    const error = cause || new Error(`langShot helper exited (${code ?? signal ?? 'unknown'})`)
    this.process = null
    for (const { reject, timer } of this.pending.values()) {
      clearTimeout(timer)
      reject(error)
    }
    this.pending.clear()
    this.emit('exit', error)
  }
}

function toHelperError(value) {
  const error = new Error(value?.message || 'Native helper request failed')
  error.code = value?.code || 'HELPER_ERROR'
  return error
}

function resolveHelperPath() {
  const bundled = path.join(__dirname, '..', 'native', 'langshot-helper.app', 'Contents', 'MacOS', 'langshot-helper')
  const development = path.resolve(__dirname, '..', '..', 'native', '.build', 'debug', 'langshot-helper')
  return fs.existsSync(bundled) ? bundled : development
}

module.exports = { HelperClient, resolveHelperPath }

