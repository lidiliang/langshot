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

test('a late exit from the previous helper cannot disconnect a reopened plugin', async () => {
  const first = fakeChild({ exitOnKill: false })
  const second = fakeChild()
  const children = [first, second]
  const client = new HelperClient({ helperPath: __filename, spawnProcess: () => children.shift(), timeoutMs: 100 })
  const firstResponse = client.request('hello')
  client.stop()
  await assert.rejects(firstResponse, /stopped/)

  const secondResponse = client.request('hello')
  const request = JSON.parse(String(second.stdin.read()).trim())
  first.emit('exit', 0, null)
  assert.equal(client.process, second)
  second.stdout.write(`${JSON.stringify({ protocolVersion: 1, type: 'response', requestId: request.requestId, ok: true, payload: { reopened: true } })}\n`)
  assert.deepEqual(await secondResponse, { reopened: true })
})

function fakeChild({ exitOnKill = true } = {}) {
  const child = new EventEmitter()
  child.stdin = new PassThrough()
  child.stdout = new PassThrough()
  child.stderr = new PassThrough()
  child.kill = () => {
    if (exitOnKill) child.emit('exit', 0, null)
  }
  return child
}
