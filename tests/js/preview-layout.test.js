'use strict'

const test = require('node:test')
const assert = require('node:assert/strict')
const { calculatePreviewLayout } = require('../../plugin/lib/preview-layout')

test('actual pixel preview maps one image pixel to one physical display pixel on Retina', () => {
  const layout = calculatePreviewLayout({
    naturalWidth: 1283,
    naturalHeight: 8888,
    availableWidth: 1000,
    devicePixelRatio: 2,
    mode: 'actual'
  })
  assert.equal(layout.displayWidth, 641.5)
  assert.equal(layout.displayHeight, 4444)
  assert.equal(layout.physicalScale, 1)
  assert.equal(layout.percentage, 100)
})

test('fit width preview reports the real physical scaling percentage', () => {
  const layout = calculatePreviewLayout({
    naturalWidth: 1280,
    naturalHeight: 2560,
    availableWidth: 800,
    devicePixelRatio: 2,
    mode: 'fit'
  })
  assert.equal(layout.displayWidth, 800)
  assert.equal(layout.displayHeight, 1600)
  assert.equal(layout.physicalScale, 1.25)
  assert.equal(layout.percentage, 125)
})
