'use strict'

const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')

test('uTools manifest references a bundled 256px PNG logo', () => {
  const pluginRoot = path.resolve(__dirname, '../../plugin')
  const manifest = JSON.parse(fs.readFileSync(path.join(pluginRoot, 'plugin.json'), 'utf8'))
  assert.equal(manifest.logo, 'logo.png')

  const logo = fs.readFileSync(path.join(pluginRoot, manifest.logo))
  assert.deepEqual(Array.from(logo.subarray(0, 8)), [137, 80, 78, 71, 13, 10, 26, 10])
  assert.equal(logo.readUInt32BE(16), 256)
  assert.equal(logo.readUInt32BE(20), 256)
})

test('uTools commands remain unique after case-insensitive normalization', () => {
  const pluginRoot = path.resolve(__dirname, '../../plugin')
  const manifest = JSON.parse(fs.readFileSync(path.join(pluginRoot, 'plugin.json'), 'utf8'))
  const commands = manifest.features.flatMap(feature => feature.cmds || [])
  const normalized = commands.map(command => String(command).trim().toLocaleLowerCase('en-US'))
  assert.equal(new Set(normalized).size, normalized.length)
  assert.deepEqual(commands.filter(command => /^langshot$/i.test(command)), ['langShot'])
})

test('the reused uTools page resets whenever the plugin is entered', () => {
  const pluginRoot = path.resolve(__dirname, '../../plugin')
  const preload = fs.readFileSync(path.join(pluginRoot, 'preload.js'), 'utf8')
  const app = fs.readFileSync(path.join(pluginRoot, 'app.js'), 'utf8')
  assert.match(preload, /utools\.onPluginEnter\(listener\)/)
  assert.match(app, /window\.langShot\.onPluginEnter\(resetForNewEntry\)/)
  assert.match(app, /resultPanel\.hidden = true/)
  assert.match(app, /completedPath = null/)
})
