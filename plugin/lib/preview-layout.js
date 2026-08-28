'use strict'

;(function exposePreviewLayout(root, factory) {
  const api = factory()
  if (typeof module === 'object' && module.exports) module.exports = api
  else root.langShotPreviewLayout = api
})(typeof globalThis !== 'undefined' ? globalThis : this, () => {
  function calculatePreviewLayout({ naturalWidth, naturalHeight, availableWidth, devicePixelRatio = 1, mode = 'actual' }) {
    if (naturalWidth <= 0 || naturalHeight <= 0 || availableWidth <= 0) {
      throw new TypeError('Image geometry is not ready')
    }
    const pixelRatio = Math.max(1, Number(devicePixelRatio) || 1)
    const actualPixelWidth = naturalWidth / pixelRatio
    const displayWidth = mode === 'fit' ? availableWidth : actualPixelWidth
    const displayHeight = naturalHeight * displayWidth / naturalWidth
    const physicalScale = displayWidth * pixelRatio / naturalWidth
    return {
      displayWidth,
      displayHeight,
      physicalScale,
      percentage: Math.max(1, Math.round(physicalScale * 100))
    }
  }

  return { calculatePreviewLayout }
})
