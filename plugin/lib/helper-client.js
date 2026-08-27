'use strict'

const { EventEmitter } = require('node:events')
const { spawn } = require('node:child_process')
const crypto = require('node:crypto')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { createRequest, parseMessage } = require('./protocol')

const helperBinaryRelativePath = path.join('Contents', 'MacOS', 'langshot-helper')
const helperInfoRelativePath = path.join('Contents', 'Info.plist')

class HelperClient extends EventEmitter {
  constructor(options = {}) {
    super()
    this.helperPath = options.helperPath || null
    this.helperPathResolver = options.helperPathResolver || (() => resolveHelperPath({ installRoot: options.helperInstallRoot }))
    this.spawnProcess = options.spawnProcess || spawn
    this.timeoutMs = options.timeoutMs || 5000
    this.process = null
    this.pending = new Map()
    this.buffer = ''
  }

  start() {
    if (this.process) return
    if (!this.helperPath) this.helperPath = this.helperPathResolver()
    if (!fs.existsSync(this.helperPath)) {
      throw new Error(`langShot helper not found: ${this.helperPath}`)
    }
    const child = this.spawnProcess(this.helperPath, [], {
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env, LANGSHOT_PARENT_PID: String(process.pid) }
    })
    this.process = child
    this.buffer = ''
    child.stdout.setEncoding('utf8')
    child.stdout.on('data', chunk => {
      if (this.process === child) this.#consume(chunk)
    })
    child.stderr.setEncoding('utf8')
    child.stderr.on('data', chunk => {
      if (this.process === child) this.emit('diagnostic', String(chunk).trim())
    })
    child.once('exit', (code, signal) => this.#handleExit(child, code, signal))
    child.once('error', error => this.#handleExit(child, null, null, error))
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
    const child = this.process
    this.process = null
    child.kill('SIGTERM')
    this.#rejectPending(new Error('langShot helper stopped'))
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

  #handleExit(child, code, signal, cause) {
    if (this.process !== child) return
    const error = cause || new Error(`langShot helper exited (${code ?? signal ?? 'unknown'})`)
    this.process = null
    this.#rejectPending(error)
    this.emit('exit', error)
  }

  #rejectPending(error) {
    for (const { reject, timer } of this.pending.values()) {
      clearTimeout(timer)
      reject(error)
    }
    this.pending.clear()
  }
}

function toHelperError(value) {
  const error = new Error(value?.message || 'Native helper request failed')
  error.code = value?.code || 'HELPER_ERROR'
  return error
}

function resolveHelperPath(options = {}) {
  const bundledApp = options.bundledApp || path.join(__dirname, '..', 'native', 'langshot-helper.app')
  const bundledBinary = path.join(bundledApp, helperBinaryRelativePath)
  const development = options.development || path.resolve(__dirname, '..', '..', 'native', '.build', 'debug', 'langshot-helper')
  if (!fs.existsSync(bundledBinary)) return development
  return materializeBundledHelper(bundledApp, options.installRoot || resolveHelperInstallRoot())
}

function resolveHelperInstallRoot() {
  const appData = globalThis.utools && typeof globalThis.utools.getPath === 'function'
    ? globalThis.utools.getPath('appData')
    : path.join(os.homedir(), 'Library', 'Application Support')
  return path.join(appData, 'langShot', 'helper')
}

function materializeBundledHelper(sourceApp, installRoot) {
  const sourceBinary = path.join(sourceApp, helperBinaryRelativePath)
  const sourceInfo = path.join(sourceApp, helperInfoRelativePath)
  if (!fs.existsSync(sourceBinary) || !fs.existsSync(sourceInfo)) {
    throw new Error(`langShot helper bundle is incomplete: ${sourceApp}`)
  }

  const binary = fs.readFileSync(sourceBinary)
  const info = fs.readFileSync(sourceInfo)
  const digest = helperBundleDigest(binary, info)
  const versionRoot = path.join(installRoot, digest)
  const targetApp = path.join(versionRoot, 'langshot-helper.app')
  const targetBinary = path.join(targetApp, helperBinaryRelativePath)
  const targetInfo = path.join(targetApp, helperInfoRelativePath)

  if (hasExpectedHelper(targetBinary, targetInfo, digest)) {
    fs.chmodSync(targetBinary, 0o755)
    return targetBinary
  }

  fs.mkdirSync(installRoot, { recursive: true, mode: 0o700 })
  const stagingRoot = `${versionRoot}.staging-${process.pid}-${Date.now()}`
  const stagingApp = path.join(stagingRoot, 'langshot-helper.app')
  const stagingBinary = path.join(stagingApp, helperBinaryRelativePath)
  const stagingInfo = path.join(stagingApp, helperInfoRelativePath)

  try {
    fs.mkdirSync(path.dirname(stagingBinary), { recursive: true })
    fs.writeFileSync(stagingInfo, info)
    fs.writeFileSync(stagingBinary, binary, { mode: 0o755 })
    fs.chmodSync(stagingBinary, 0o755)
    fs.rmSync(versionRoot, { recursive: true, force: true })
    fs.renameSync(stagingRoot, versionRoot)
  } finally {
    fs.rmSync(stagingRoot, { recursive: true, force: true })
  }

  if (!hasExpectedHelper(targetBinary, targetInfo, digest)) {
    throw new Error(`langShot helper could not be installed: ${targetBinary}`)
  }
  return targetBinary
}

function hasExpectedHelper(binaryPath, infoPath, expectedDigest) {
  if (!fs.existsSync(binaryPath) || !fs.existsSync(infoPath)) return false
  try {
    return helperBundleDigest(fs.readFileSync(binaryPath), fs.readFileSync(infoPath)) === expectedDigest
  } catch {
    return false
  }
}

function helperBundleDigest(binary, info) {
  return crypto.createHash('sha256')
    .update(binary)
    .update(Buffer.from([0]))
    .update(info)
    .digest('hex')
}

module.exports = { HelperClient, materializeBundledHelper, resolveHelperPath }
