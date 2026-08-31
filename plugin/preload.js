'use strict'

const { HelperClient } = require('./lib/helper-client')
const { clipboard, nativeImage, shell } = require('electron')

const client = new HelperClient()
const listeners = new Set()

// Preload runs before the page paints. A fresh renderer is always entering a
// new capture flow, so hide it here as well as in the re-entry callback below.
if (globalThis.utools) utools.hideMainWindow()

client.on('event', event => {
  for (const listener of listeners) listener(event)
})

client.on('diagnostic', message => console.info('[langShot helper]', message))
client.on('protocolError', error => console.error('[langShot protocol]', error.message))

window.langShot = Object.freeze({
  request(type, payload) {
    return client.request(type, payload)
  },
  subscribe(listener) {
    if (typeof listener !== 'function') throw new TypeError('listener must be a function')
    listeners.add(listener)
    return () => listeners.delete(listener)
  },
  onPluginEnter(listener) {
    if (typeof listener !== 'function') throw new TypeError('listener must be a function')
    if (globalThis.utools) {
      utools.onPluginEnter(action => {
        // The native selection overlay is the primary entry surface. Hide the
        // reused uTools page synchronously so its homepage never flashes first.
        utools.hideMainWindow()
        listener(action)
      })
    }
    else window.addEventListener('focus', listener)
  },
  hideMainWindow() {
    if (globalThis.utools) utools.hideMainWindow()
  },
  showMainWindow() {
    if (globalThis.utools) utools.showMainWindow()
  },
  closePlugin() {
    if (globalThis.utools) utools.outPlugin()
    else window.close()
  },
  chooseSavePath(defaultName) {
    if (!globalThis.utools) return null
    return utools.showSaveDialog({ defaultPath: defaultName })
  },
  copyImage(filePath) {
    const image = nativeImage.createFromPath(filePath)
    if (image.isEmpty()) throw new Error('无法读取生成的图片')
    clipboard.writeImage(image)
  },
  revealFile(filePath) {
    shell.showItemInFolder(filePath)
  }
})

if (globalThis.utools) {
  utools.onPluginOut(() => client.stop())
}
