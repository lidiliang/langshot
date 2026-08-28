'use strict'

;(function exposeAnnotationModel(root, factory) {
  const api = factory()
  if (typeof module === 'object' && module.exports) module.exports = api
  else root.langShotAnnotationModel = api
})(typeof globalThis !== 'undefined' ? globalThis : this, () => {
  function mapClientPoint(clientX, clientY, rect, naturalWidth, naturalHeight) {
    if (!rect || rect.width <= 0 || rect.height <= 0 || naturalWidth <= 0 || naturalHeight <= 0) {
      throw new TypeError('Image geometry is not ready')
    }
    return {
      x: clamp((clientX - rect.left) * naturalWidth / rect.width, 0, naturalWidth),
      y: clamp((clientY - rect.top) * naturalHeight / rect.height, 0, naturalHeight)
    }
  }

  function arrowIsVisible(start, end, minimumDistance = 4) {
    return Boolean(start && end && Math.hypot(end.x - start.x, end.y - start.y) >= minimumDistance)
  }

  function arrowHeadPoints(start, end, lineWidth) {
    const angle = Math.atan2(end.y - start.y, end.x - start.x)
    const distance = Math.hypot(end.x - start.x, end.y - start.y)
    const length = Math.max(lineWidth * 3.5, Math.min(distance * 0.28, lineWidth * 6))
    const spread = Math.PI / 7
    return [
      end,
      { x: end.x - length * Math.cos(angle - spread), y: end.y - length * Math.sin(angle - spread) },
      { x: end.x - length * Math.cos(angle + spread), y: end.y - length * Math.sin(angle + spread) }
    ]
  }

  function clamp(value, minimum, maximum) {
    return Math.min(maximum, Math.max(minimum, value))
  }

  function translateAnnotation(annotation, dx, dy, imageWidth, imageHeight) {
    if (annotation.type === 'arrow') {
      const minimumX = Math.min(annotation.start.x, annotation.end.x)
      const maximumX = Math.max(annotation.start.x, annotation.end.x)
      const minimumY = Math.min(annotation.start.y, annotation.end.y)
      const maximumY = Math.max(annotation.start.y, annotation.end.y)
      const safeDX = clamp(dx, -minimumX, imageWidth - maximumX)
      const safeDY = clamp(dy, -minimumY, imageHeight - maximumY)
      return {
        ...annotation,
        start: { x: annotation.start.x + safeDX, y: annotation.start.y + safeDY },
        end: { x: annotation.end.x + safeDX, y: annotation.end.y + safeDY }
      }
    }
    return {
      ...annotation,
      x: clamp(annotation.x + dx, 0, imageWidth),
      y: clamp(annotation.y + dy, 0, imageHeight)
    }
  }

  function moveArrowEndpoint(annotation, handle, point, imageWidth, imageHeight) {
    if (annotation.type !== 'arrow' || (handle !== 'start' && handle !== 'end')) {
      throw new TypeError('A valid arrow endpoint is required')
    }
    return {
      ...annotation,
      [handle]: {
        x: clamp(point.x, 0, imageWidth),
        y: clamp(point.y, 0, imageHeight)
      }
    }
  }

  return { mapClientPoint, arrowIsVisible, arrowHeadPoints, clamp, translateAnnotation, moveArrowEndpoint }
})
