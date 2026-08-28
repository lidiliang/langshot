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
  assert.equal(manifest.pluginName, '滚动长截图')
  assert.equal(new Set(normalized).size, normalized.length)
  assert.deepEqual(commands, ['长截屏', '滚动截屏', '滚动截图', 'langShot'])
})

test('release metadata is synchronized for version 1.0.0', () => {
  const projectRoot = path.resolve(__dirname, '../..')
  const manifest = JSON.parse(fs.readFileSync(path.join(projectRoot, 'plugin', 'plugin.json'), 'utf8'))
  const packageMetadata = JSON.parse(fs.readFileSync(path.join(projectRoot, 'package.json'), 'utf8'))
  const helperInfo = fs.readFileSync(path.join(projectRoot, 'scripts', 'helper-Info.plist'), 'utf8')

  assert.equal(manifest.version, '1.0.0')
  assert.equal(packageMetadata.version, manifest.version)
  assert.match(helperInfo, /<key>CFBundleShortVersionString<\/key><string>1\.0\.0<\/string>/)
  assert.equal(manifest.homepage, 'https://github.com/lidiliang/langshot')
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

test('capture opens directly in simple screenshot mode', () => {
  const projectRoot = path.resolve(__dirname, '../..')
  const manifest = JSON.parse(fs.readFileSync(path.join(projectRoot, 'plugin', 'plugin.json'), 'utf8'))
  const app = fs.readFileSync(path.join(projectRoot, 'plugin', 'app.js'), 'utf8')
  const html = fs.readFileSync(path.join(projectRoot, 'plugin', 'index.html'), 'utf8')

  assert.equal(manifest.features[0].explain, '开始截图')
  assert.match(app, /const state = \{ mode: 'simple'/)
  assert.match(app, /function resetForNewEntry\(\)[\s\S]*void startCaptureFlow\(\)/)
  assert.match(html, /class="mode-card selected" data-mode="simple"/)
  assert.ok(html.indexOf('data-mode="automatic"') < html.indexOf('data-mode="manual"'))
  assert.match(html, /自动滚动[\s\S]*推荐[\s\S]*拼接更准确/)
})

test('the completed result exposes Enter as the copy shortcut', () => {
  const projectRoot = path.resolve(__dirname, '../..')
  const app = fs.readFileSync(path.join(projectRoot, 'plugin', 'app.js'), 'utf8')
  const html = fs.readFileSync(path.join(projectRoot, 'plugin', 'index.html'), 'utf8')

  assert.match(app, /event\.key === 'Enter'[\s\S]*copyCompletedImage\(\)/)
  assert.match(html, /aria-keyshortcuts="Enter"/)
  assert.match(html, /按 Enter 快速复制/)
})
