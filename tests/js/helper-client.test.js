'use strict'

const test = require('node:test')
const assert = require('node:assert/strict')
const { EventEmitter } = require('node:events')
const { PassThrough } = require('node:stream')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { HelperClient, materializeBundledHelper } = require('../../plugin/lib/helper-client')

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

test('a bundled helper is materialized to a real executable app bundle', t => {
  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'langshot-helper-test-'))
  t.after(() => fs.rmSync(fixtureRoot, { recursive: true, force: true }))
  const sourceApp = path.join(fixtureRoot, 'virtual', 'langshot-helper.app')
  const sourceBinary = path.join(sourceApp, 'Contents', 'MacOS', 'langshot-helper')
  fs.mkdirSync(path.dirname(sourceBinary), { recursive: true })
  fs.writeFileSync(path.join(sourceApp, 'Contents', 'Info.plist'), '<plist>fixture</plist>')
  fs.writeFileSync(sourceBinary, 'fixture-binary')

  const installedBinary = materializeBundledHelper(sourceApp, path.join(fixtureRoot, 'installed'))

  assert.notEqual(installedBinary, sourceBinary)
  assert.equal(fs.readFileSync(installedBinary, 'utf8'), 'fixture-binary')
  assert.equal(fs.readFileSync(path.join(installedBinary, '..', '..', 'Info.plist'), 'utf8'), '<plist>fixture</plist>')
  assert.equal(fs.statSync(installedBinary).mode & 0o111, 0o111)
})

test('a materialized helper is repaired when its executable is changed', t => {
  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'langshot-helper-test-'))
  t.after(() => fs.rmSync(fixtureRoot, { recursive: true, force: true }))
  const sourceApp = path.join(fixtureRoot, 'virtual', 'langshot-helper.app')
  const sourceBinary = path.join(sourceApp, 'Contents', 'MacOS', 'langshot-helper')
  fs.mkdirSync(path.dirname(sourceBinary), { recursive: true })
  fs.writeFileSync(path.join(sourceApp, 'Contents', 'Info.plist'), '<plist/>')
  fs.writeFileSync(sourceBinary, 'trusted-binary')
  const installRoot = path.join(fixtureRoot, 'installed')
  const installedBinary = materializeBundledHelper(sourceApp, installRoot)
  fs.writeFileSync(installedBinary, 'changed')

  assert.equal(materializeBundledHelper(sourceApp, installRoot), installedBinary)
  assert.equal(fs.readFileSync(installedBinary, 'utf8'), 'trusted-binary')
})

test('changed helper bundle metadata creates a new materialized version', t => {
  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'langshot-helper-test-'))
  t.after(() => fs.rmSync(fixtureRoot, { recursive: true, force: true }))
  const sourceApp = path.join(fixtureRoot, 'virtual', 'langshot-helper.app')
  const sourceBinary = path.join(sourceApp, 'Contents', 'MacOS', 'langshot-helper')
  const sourceInfo = path.join(sourceApp, 'Contents', 'Info.plist')
  fs.mkdirSync(path.dirname(sourceBinary), { recursive: true })
  fs.writeFileSync(sourceInfo, '<plist>1.0.0</plist>')
  fs.writeFileSync(sourceBinary, 'same-binary')
  const installRoot = path.join(fixtureRoot, 'installed')
  const firstBinary = materializeBundledHelper(sourceApp, installRoot)
  fs.writeFileSync(sourceInfo, '<plist>1.0.1</plist>')

  const nextBinary = materializeBundledHelper(sourceApp, installRoot)

  assert.notEqual(nextBinary, firstBinary)
  assert.equal(fs.readFileSync(path.join(nextBinary, '..', '..', 'Info.plist'), 'utf8'), '<plist>1.0.1</plist>')
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
