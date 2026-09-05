'use strict'

const PROTOCOL_VERSION = 1

const REQUEST_TYPES = new Set([
  'hello',
  'permissions.get',
  'permissions.request',
  'permissions.openSettings',
  'session.prepare',
  'session.begin',
  'selection.confirm',
  'selection.reset',
  'scroll.anchor',
  'scroll.setSpeed',
  'session.pause',
  'session.resume',
  'session.finish',
  'session.discard',
  'session.recover',
  'editor.export'
])

function createRequest(type, payload = {}, requestId = crypto.randomUUID()) {
  if (!REQUEST_TYPES.has(type)) throw new TypeError(`Unsupported request type: ${type}`)
  if (!payload || Array.isArray(payload) || typeof payload !== 'object') {
    throw new TypeError('Request payload must be an object')
  }
  return { protocolVersion: PROTOCOL_VERSION, type, requestId, payload }
}

function parseMessage(line) {
  let value
  try {
    value = JSON.parse(line)
  } catch {
    throw new TypeError('Helper returned invalid JSON')
  }
  if (!value || Array.isArray(value) || typeof value !== 'object') {
    throw new TypeError('Protocol message must be an object')
  }
  if (value.protocolVersion !== PROTOCOL_VERSION) {
    throw new TypeError(`Incompatible protocol version: ${String(value.protocolVersion)}`)
  }
  if (typeof value.type !== 'string' || value.type.length === 0) {
    throw new TypeError('Protocol message is missing type')
  }
  return value
}

module.exports = { PROTOCOL_VERSION, REQUEST_TYPES, createRequest, parseMessage }
