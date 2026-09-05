'use strict'

const test = require('node:test')
const assert = require('node:assert/strict')
const { PROTOCOL_VERSION, createRequest, parseMessage } = require('../../plugin/lib/protocol')

test('createRequest emits a versioned request with caller payload', () => {
  const request = createRequest('session.begin', { mode: 'manual' }, 'request-1')
  assert.deepEqual(request, {
    protocolVersion: PROTOCOL_VERSION,
    type: 'session.begin',
    requestId: 'request-1',
    payload: { mode: 'manual' }
  })
})

test('capture preparation is part of the protocol surface', () => {
  const request = createRequest('session.prepare', { mode: 'simple' }, 'prepare-1')
  assert.equal(request.type, 'session.prepare')
  assert.equal(request.payload.mode, 'simple')
})

test('createRequest rejects commands outside the protocol surface', () => {
  assert.throws(() => createRequest('shell.exec', {}), /Unsupported request type/)
})

test('parseMessage rejects malformed and incompatible helper output', () => {
  assert.throws(() => parseMessage('{'), /invalid JSON/)
  assert.throws(
    () => parseMessage(JSON.stringify({ protocolVersion: 2, type: 'hello' })),
    /Incompatible protocol version/
  )
})
