'use strict'

const test = require('node:test')
const assert = require('node:assert/strict')
const { mapClientPoint, arrowIsVisible, arrowHeadPoints, translateAnnotation, moveArrowEndpoint } = require('../../plugin/lib/annotation-model')

test('preview pointer coordinates map to original image pixels', () => {
  const point = mapClientPoint(210, 120, { left: 10, top: 20, width: 400, height: 200 }, 1600, 800)
  assert.deepEqual(point, { x: 800, y: 400 })
})

test('tiny arrow gestures are ignored', () => {
  assert.equal(arrowIsVisible({ x: 10, y: 10 }, { x: 11, y: 11 }, 4), false)
  assert.equal(arrowIsVisible({ x: 10, y: 10 }, { x: 30, y: 10 }, 4), true)
})

test('arrow head points terminate at the requested endpoint', () => {
  const points = arrowHeadPoints({ x: 10, y: 10 }, { x: 80, y: 30 }, 4)
  assert.deepEqual(points[0], { x: 80, y: 30 })
  assert.equal(points.length, 3)
})

test('arrow objects move as one object and stay inside the image', () => {
  const arrow = { id: 'a', type: 'arrow', start: { x: 10, y: 20 }, end: { x: 80, y: 60 } }
  assert.deepEqual(translateAnnotation(arrow, 15, 10, 100, 100), {
    ...arrow,
    start: { x: 25, y: 30 },
    end: { x: 95, y: 70 }
  })
  assert.deepEqual(translateAnnotation(arrow, 80, 80, 100, 100).end, { x: 100, y: 100 })
})

test('either arrow endpoint can be adjusted independently', () => {
  const arrow = { id: 'a', type: 'arrow', start: { x: 10, y: 20 }, end: { x: 80, y: 60 } }
  const edited = moveArrowEndpoint(arrow, 'end', { x: 140, y: -10 }, 100, 100)
  assert.deepEqual(edited.start, arrow.start)
  assert.deepEqual(edited.end, { x: 100, y: 0 })
})

test('text objects can be repositioned inside the image', () => {
  const annotation = { id: 't', type: 'text', x: 20, y: 30, text: '重点' }
  assert.deepEqual(translateAnnotation(annotation, -40, 90, 100, 100), { ...annotation, x: 0, y: 100 })
})
