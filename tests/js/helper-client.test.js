'use strict'

const test = require('node:test')
const assert = require('node:assert/strict')
const { EventEmitter } = require('node:events')
const { PassThrough } = require('node:stream')
const { HelperClient } = require('../../plugin/lib/helper-client')

test('HelperClient correlates a split-line response with its request', async () => {
  const child = fakeChild()
  const client = new HelperClient({ helperPath: __filename, spawnProcess: () => child, timeoutMs: 100 })
  const response = client.request('hello')
  const request = JSON.parse(String(child.stdin.read()).trim())
  const line = JSON.stringify({ protocolVersion: 1, type: 'response', requestId: request.requestId, ok: true, payload: { name: 'langshot-helper' } })
  child.stdout.write(line.slice(0, 12))
  child.stdout.write(`${line.slice(12)}\n`)
  assert.deepEqual(await response, { name: 'langshot-helper' })
})

test('HelperClient rejects pending work when the helper exits', async () => {
  const child = fakeChild()
  const client = new HelperClient({ helperPath: __filename, spawnProcess: () => child, timeoutMs: 100 })
  const response = client.request('hello')
  child.emit('exit', 2, null)
  await assert.rejects(response, /exited/)
})

function fakeChild() {
  const child = new EventEmitter()
  child.stdin = new PassThrough()
  child.stdout = new PassThrough()
  child.stderr = new PassThrough()
  child.kill = () => child.emit('exit', 0, null)
  return child
}

