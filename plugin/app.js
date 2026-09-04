'use strict'

const state = { mode: 'simple', direction: 'down', busy: false }
const modeButtons = Array.from(document.querySelectorAll('.mode-card'))
const directionButtons = Array.from(document.querySelectorAll('.direction'))
const directionRow = document.querySelector('.direction-row')
const startButton = document.getElementById('startButton')
const permissionDialog = document.getElementById('permissionDialog')
const permissionItems = document.getElementById('permissionItems')
const retryPermissionButton = document.getElementById('retryPermissionButton')
const cancelPermissionButton = document.getElementById('cancelPermissionButton')
const toast = document.getElementById('toast')
const resultPanel = document.getElementById('resultPanel')
const resultImage = document.getElementById('resultImage')
const resultPath = document.getElementById('resultPath')
const copyButton = document.getElementById('copyButton')
const revealButton = document.getElementById('revealButton')
const selectToolButton = document.getElementById('selectToolButton')
const arrowToolButton = document.getElementById('arrowToolButton')
const rectangleToolButton = document.getElementById('rectangleToolButton')
const textToolButton = document.getElementById('textToolButton')
const undoEditButton = document.getElementById('undoEditButton')
const actualPixelsButton = document.getElementById('actualPixelsButton')
const fitWidthButton = document.getElementById('fitWidthButton')
const previewScale = document.getElementById('previewScale')
const editorHelp = document.getElementById('editorHelp')
const editorWorkspace = document.getElementById('editorWorkspace')
const editorStage = document.getElementById('editorStage')
const annotationLayer = document.getElementById('annotationLayer')
const textEditor = document.getElementById('textEditor')
const textEditorInput = document.getElementById('textEditorInput')
const annotationModel = window.langShotAnnotationModel
const previewLayoutModel = window.langShotPreviewLayout
let completedPath = null
let editorTool = 'select'
let annotations = []
let draftArrow = null
let draftRectangle = null
let textOrigin = null
let editingTextId = null
let selectedAnnotationId = null
let annotationDrag = null
let annotationHistory = []
let annotationSequence = 0
let resultBusy = false
let previewMode = 'actual'

window.langShot.onPluginEnter(resetForNewEntry)

const permissionDetails = {
  screenRecording: {
    icon: '▣',
    title: '屏幕录制',
    description: '用于读取选区的原始屏幕像素，不会录制或上传其他内容。'
  },
  accessibility: {
    icon: '⌁',
    title: '辅助功能',
    description: '用于识别窗口内元素，并在自动模式中发送滚动操作。'
  }
}

for (const button of modeButtons) {
  button.addEventListener('click', () => {
    state.mode = button.dataset.mode
    syncModeUI()
    closePermissionDialog()
  })
}

for (const button of directionButtons) {
  button.addEventListener('click', () => {
    state.direction = button.dataset.direction
    for (const candidate of directionButtons) candidate.classList.toggle('selected', candidate === button)
  })
}

startButton.addEventListener('click', startCaptureFlow)

async function startCaptureFlow() {
  if (state.busy) return
  // Hide before the first asynchronous permission request. The homepage is a
  // fallback after cancellation, not an intermediate step on every entry.
  window.langShot.hideMainWindow()
  setBusy(true)
  try {
    const permissions = await window.langShot.request('permissions.get')
    const missing = missingPermissions(permissions)
    if (missing.length) {
      showPermissionDialog(missing)
      return
    }
    await beginCapture()
  } catch (error) {
    showToast(error.message || '无法启动截图')
    window.langShot.showMainWindow()
  } finally {
    setBusy(false)
  }
}

permissionItems.addEventListener('click', async event => {
  const button = event.target.closest('[data-permission]')
  if (!button) return
  const kind = button.dataset.permission
  button.disabled = true
  button.textContent = '正在请求…'
  try {
    await window.langShot.request('permissions.request', { kind })
    const permissions = await window.langShot.request('permissions.get')
    const missing = missingPermissions(permissions)
    if (missing.includes(kind)) {
      await window.langShot.request('permissions.openSettings', { kind })
      showToast(`请在系统设置中打开“${permissionDetails[kind].title}”权限`)
    }
    if (missing.length) showPermissionDialog(missing)
    else await resumeAfterPermission()
  } catch (error) {
    showToast(error.message || '无法打开系统权限设置')
    button.disabled = false
    button.textContent = '请求授权'
  }
})

retryPermissionButton.addEventListener('click', async () => {
  retryPermissionButton.disabled = true
  retryPermissionButton.textContent = '正在检测…'
  try {
    const permissions = await window.langShot.request('permissions.get')
    const missing = missingPermissions(permissions)
    if (missing.length) {
      showPermissionDialog(missing)
      showToast(`仍未获得${missing.map(kind => permissionDetails[kind].title).join('、')}权限`)
      return
    }
    await resumeAfterPermission()
  } catch (error) {
    showToast(error.message || '权限检测失败')
  } finally {
    retryPermissionButton.disabled = false
    retryPermissionButton.textContent = '我已授权，重新检测'
  }
})

cancelPermissionButton.addEventListener('click', closePermissionDialog)

document.addEventListener('keydown', event => {
  if (event.key === 'Escape' && !permissionDialog.hidden) {
    closePermissionDialog()
    return
  }
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'z' && resultPanel.hidden === false && textEditor.hidden) {
    event.preventDefault()
    undoLastAnnotation()
    return
  }
  if ((event.key === 'Backspace' || event.key === 'Delete') && resultPanel.hidden === false && textEditor.hidden && selectedAnnotationId) {
    event.preventDefault()
    deleteSelectedAnnotation()
    return
  }
  if (event.key === 'Enter' && !event.repeat && resultPanel.hidden === false && permissionDialog.hidden && textEditor.hidden && completedPath && !copyButton.disabled) {
    event.preventDefault()
    event.stopPropagation()
    void copyCompletedImage()
  }
})

window.langShot.subscribe(event => {
  if (event.type === 'permission.required') {
    state.mode = event.payload?.mode || 'automatic'
    syncModeUI()
    window.langShot.showMainWindow()
    showPermissionDialog(event.payload?.permissions || ['accessibility'])
    return
  }
  if (event.type === 'session.completed' || event.type === 'session.cancelled' || event.type === 'error') {
    window.langShot.showMainWindow()
  }
  if (event.type === 'session.completed') showResult(event.payload?.path, event.payload?.warnings)
})

copyButton.addEventListener('click', () => { void copyCompletedImage() })

async function copyCompletedImage() {
  if (!completedPath || resultBusy) return
  if (!textEditor.hidden) commitTextAnnotation()
  setResultBusy(true, annotations.length ? '正在应用编辑…' : '正在复制…')
  try {
    const exportPath = await exportAnnotationsIfNeeded()
    window.langShot.copyImage(exportPath)
    showToast('图片已成功复制到剪贴板')
    copyButton.textContent = '已复制 ✓'
    clearTimeout(copyButton.resetTimer)
    copyButton.resetTimer = setTimeout(() => window.langShot.closePlugin(), 650)
  }
  catch (error) {
    setResultBusy(false)
    showToast(error.message || '复制图片失败')
  }
}

revealButton.addEventListener('click', async () => {
  if (!completedPath || resultBusy) return
  if (!textEditor.hidden) commitTextAnnotation()
  setResultBusy(true, annotations.length ? '正在保存编辑…' : '复制图片')
  try {
    const exportPath = await exportAnnotationsIfNeeded()
    window.langShot.revealFile(exportPath)
  } catch (error) {
    showToast(error.message || '无法保存编辑后的图片')
  } finally {
    setResultBusy(false)
  }
})

selectToolButton.addEventListener('click', () => setEditorTool('select'))
arrowToolButton.addEventListener('click', () => setEditorTool(editorTool === 'arrow' ? 'select' : 'arrow'))
rectangleToolButton.addEventListener('click', () => setEditorTool(editorTool === 'rectangle' ? 'select' : 'rectangle'))
textToolButton.addEventListener('click', () => setEditorTool(editorTool === 'text' ? 'select' : 'text'))
undoEditButton.addEventListener('click', undoLastAnnotation)
actualPixelsButton.addEventListener('click', () => setPreviewMode('actual'))
fitWidthButton.addEventListener('click', () => setPreviewMode('fit'))
resultImage.addEventListener('load', layoutEditorImage)
window.addEventListener('resize', () => {
  if (!resultPanel.hidden) layoutEditorImage()
})

annotationLayer.addEventListener('pointerdown', event => {
  if (event.button !== 0 || resultBusy) return
  const point = editorPoint(event)
  const handle = event.target.closest?.('[data-handle]')
  const object = event.target.closest?.('[data-annotation-id]')
  if (editorTool === 'select') {
    if (handle) {
      beginAnnotationDrag(event, point, handle.dataset.annotationId, handle.dataset.handle)
    } else if (object) {
      beginAnnotationDrag(event, point, object.dataset.annotationId, 'move')
    } else {
      selectedAnnotationId = null
      renderAnnotations()
    }
    return
  }
  if (editorTool === 'arrow') {
    event.preventDefault()
    annotationLayer.setPointerCapture(event.pointerId)
    draftArrow = { id: nextAnnotationId(), type: 'arrow', start: point, end: point, lineWidth: editorLineWidth(), color: '#ff4d67' }
    renderAnnotations()
  } else if (editorTool === 'rectangle') {
    event.preventDefault()
    annotationLayer.setPointerCapture(event.pointerId)
    draftRectangle = {
      id: nextAnnotationId(),
      type: 'rectangle',
      ...annotationModel.rectangleFromPoints(point, point),
      lineWidth: editorLineWidth(),
      color: '#ff4d67'
    }
    draftRectangle.origin = point
    renderAnnotations()
  } else if (editorTool === 'text') {
    event.preventDefault()
    openTextEditor(point)
  }
})

annotationLayer.addEventListener('pointermove', event => {
  if (!annotationLayer.hasPointerCapture(event.pointerId)) return
  if (draftArrow) {
    draftArrow.end = editorPoint(event)
    renderAnnotations()
  } else if (draftRectangle) {
    const rectangle = annotationModel.rectangleFromPoints(draftRectangle.origin, editorPoint(event))
    Object.assign(draftRectangle, rectangle)
    renderAnnotations()
  } else if (annotationDrag) {
    updateAnnotationDrag(editorPoint(event))
  }
})

annotationLayer.addEventListener('pointerup', event => {
  if (draftArrow) {
    draftArrow.end = editorPoint(event)
    if (annotationModel.arrowIsVisible(draftArrow.start, draftArrow.end, Math.max(3, draftArrow.lineWidth))) {
      recordAnnotationHistory()
      annotations.push(draftArrow)
      selectedAnnotationId = draftArrow.id
      setEditorTool('select')
    }
    draftArrow = null
    renderAnnotations()
  } else if (draftRectangle) {
    const rectangle = annotationModel.rectangleFromPoints(draftRectangle.origin, editorPoint(event))
    Object.assign(draftRectangle, rectangle)
    delete draftRectangle.origin
    if (annotationModel.rectangleIsVisible(draftRectangle, Math.max(3, draftRectangle.lineWidth))) {
      recordAnnotationHistory()
      annotations.push(draftRectangle)
      selectedAnnotationId = draftRectangle.id
      setEditorTool('select')
    }
    draftRectangle = null
    renderAnnotations()
  } else if (annotationDrag) {
    finishAnnotationDrag()
  }
})

annotationLayer.addEventListener('pointercancel', () => {
  draftArrow = null
  draftRectangle = null
  cancelAnnotationDrag()
  renderAnnotations()
})

annotationLayer.addEventListener('dblclick', event => {
  if (editorTool !== 'select' || resultBusy) return
  const object = event.target.closest?.('[data-annotation-id]')
  const annotation = object && annotationById(object.dataset.annotationId)
  if (annotation?.type === 'text') {
    event.preventDefault()
    openTextEditor({ x: annotation.x, y: annotation.y }, annotation.id)
  }
})

textEditorInput.addEventListener('keydown', event => {
  if (event.key === 'Enter') {
    event.preventDefault()
    event.stopPropagation()
    commitTextAnnotation()
  } else if (event.key === 'Escape') {
    event.preventDefault()
    event.stopPropagation()
    closeTextEditor()
  }
})

function setEditorTool(tool) {
  editorTool = tool || 'select'
  if (tool !== 'text') closeTextEditor()
  selectToolButton.classList.toggle('active', editorTool === 'select')
  arrowToolButton.classList.toggle('active', editorTool === 'arrow')
  rectangleToolButton.classList.toggle('active', editorTool === 'rectangle')
  textToolButton.classList.toggle('active', editorTool === 'text')
  selectToolButton.setAttribute('aria-pressed', String(editorTool === 'select'))
  arrowToolButton.setAttribute('aria-pressed', String(editorTool === 'arrow'))
  rectangleToolButton.setAttribute('aria-pressed', String(editorTool === 'rectangle'))
  textToolButton.setAttribute('aria-pressed', String(editorTool === 'text'))
  annotationLayer.classList.add('editing')
  annotationLayer.classList.toggle('select-mode', editorTool === 'select')
  annotationLayer.classList.toggle('arrow-mode', editorTool === 'arrow')
  annotationLayer.classList.toggle('rectangle-mode', editorTool === 'rectangle')
  annotationLayer.classList.toggle('text-mode', editorTool === 'text')
  editorHelp.textContent = editorTool === 'arrow'
    ? '在图片上拖拽以绘制箭头'
    : editorTool === 'rectangle'
      ? '在图片上拖拽以圈定重点区域'
    : editorTool === 'text'
      ? '点击图片位置，然后输入文字'
      : '点击标注可选择并拖动；箭头端点和矩形四角可调整，双击文字可重写'
}

function layoutEditorImage() {
  if (!resultImage.naturalWidth || !resultImage.naturalHeight || resultPanel.hidden) return
  const availableWidth = Math.max(220, editorWorkspace.clientWidth - 24)
  const layout = previewLayoutModel.calculatePreviewLayout({
    naturalWidth: resultImage.naturalWidth,
    naturalHeight: resultImage.naturalHeight,
    availableWidth,
    devicePixelRatio: window.devicePixelRatio,
    mode: previewMode
  })
  editorStage.style.width = `${layout.displayWidth}px`
  editorStage.style.height = `${layout.displayHeight}px`
  previewScale.textContent = `${layout.percentage}%`
  annotationLayer.setAttribute('viewBox', `0 0 ${resultImage.naturalWidth} ${resultImage.naturalHeight}`)
  renderAnnotations()
}

function setPreviewMode(mode) {
  previewMode = mode === 'fit' ? 'fit' : 'actual'
  actualPixelsButton.classList.toggle('active', previewMode === 'actual')
  fitWidthButton.classList.toggle('active', previewMode === 'fit')
  actualPixelsButton.setAttribute('aria-pressed', String(previewMode === 'actual'))
  fitWidthButton.setAttribute('aria-pressed', String(previewMode === 'fit'))
  layoutEditorImage()
}

function editorPoint(event) {
  return annotationModel.mapClientPoint(
    event.clientX,
    event.clientY,
    annotationLayer.getBoundingClientRect(),
    resultImage.naturalWidth,
    resultImage.naturalHeight
  )
}

function editorScale() {
  return resultImage.naturalWidth > 0 ? editorStage.clientWidth / resultImage.naturalWidth : 1
}

function editorLineWidth() {
  return Math.max(2, 3.5 / Math.max(0.01, editorScale()))
}

function renderAnnotations() {
  const draft = draftArrow || draftRectangle
  const visible = draft ? [...annotations, draft] : annotations
  annotationLayer.replaceChildren(...visible.map(createSvgAnnotation))
  undoEditButton.disabled = resultBusy || annotationHistory.length === 0
}

function createSvgAnnotation(annotation) {
  const namespace = 'http://www.w3.org/2000/svg'
  const group = document.createElementNS(namespace, 'g')
  if (annotation.id) group.dataset.annotationId = annotation.id
  if (annotation.type === 'arrow') {
    const hitLine = document.createElementNS(namespace, 'line')
    setLineGeometry(hitLine, annotation)
    hitLine.setAttribute('stroke', 'transparent')
    hitLine.setAttribute('stroke-width', Math.max(annotation.lineWidth * 4, 12 / Math.max(0.01, editorScale())))
    hitLine.setAttribute('pointer-events', 'stroke')
    hitLine.dataset.annotationId = annotation.id
    const line = document.createElementNS(namespace, 'line')
    setLineGeometry(line, annotation)
    line.setAttribute('stroke', annotation.color)
    line.setAttribute('stroke-width', annotation.lineWidth)
    line.setAttribute('stroke-linecap', 'round')
    line.setAttribute('pointer-events', 'none')
    const head = document.createElementNS(namespace, 'polyline')
    const points = annotationModel.arrowHeadPoints(annotation.start, annotation.end, annotation.lineWidth)
    head.setAttribute('points', [points[1], points[0], points[2]].map(point => `${point.x},${point.y}`).join(' '))
    head.setAttribute('fill', 'none')
    head.setAttribute('stroke', annotation.color)
    head.setAttribute('stroke-width', annotation.lineWidth)
    head.setAttribute('stroke-linecap', 'round')
    head.setAttribute('stroke-linejoin', 'round')
    head.setAttribute('pointer-events', 'none')
    group.append(hitLine, line, head)
    if (annotation.id === selectedAnnotationId) appendArrowSelection(group, annotation)
    return group
  }

  if (annotation.type === 'rectangle') {
    const hitBox = document.createElementNS(namespace, 'rect')
    setRectangleGeometry(hitBox, annotation)
    hitBox.setAttribute('fill', 'transparent')
    hitBox.setAttribute('stroke', 'transparent')
    hitBox.setAttribute('stroke-width', Math.max(annotation.lineWidth * 4, 12 / Math.max(0.01, editorScale())))
    hitBox.setAttribute('pointer-events', 'all')
    hitBox.dataset.annotationId = annotation.id
    const rectangle = document.createElementNS(namespace, 'rect')
    setRectangleGeometry(rectangle, annotation)
    rectangle.setAttribute('fill', 'none')
    rectangle.setAttribute('stroke', annotation.color)
    rectangle.setAttribute('stroke-width', annotation.lineWidth)
    rectangle.setAttribute('rx', Math.max(annotation.lineWidth * 1.5, 3))
    rectangle.setAttribute('ry', Math.max(annotation.lineWidth * 1.5, 3))
    rectangle.setAttribute('pointer-events', 'none')
    group.append(hitBox, rectangle)
    if (annotation.id === selectedAnnotationId) appendRectangleSelection(group, annotation)
    return group
  }

  const estimatedWidth = Math.max(annotation.fontSize, annotation.text.length * annotation.fontSize * 0.66)
  const estimatedHeight = annotation.fontSize * 1.25
  const hitBox = document.createElementNS(namespace, 'rect')
  hitBox.setAttribute('x', annotation.x - annotation.fontSize * 0.12)
  hitBox.setAttribute('y', annotation.y - annotation.fontSize * 0.12)
  hitBox.setAttribute('width', estimatedWidth + annotation.fontSize * 0.24)
  hitBox.setAttribute('height', estimatedHeight + annotation.fontSize * 0.24)
  hitBox.setAttribute('fill', 'transparent')
  hitBox.setAttribute('pointer-events', 'all')
  hitBox.dataset.annotationId = annotation.id
  const text = document.createElementNS(namespace, 'text')
  text.setAttribute('x', annotation.x)
  text.setAttribute('y', annotation.y)
  text.setAttribute('fill', annotation.color)
  text.setAttribute('font-size', annotation.fontSize)
  text.setAttribute('font-family', '-apple-system, BlinkMacSystemFont, PingFang SC, sans-serif')
  text.setAttribute('font-weight', '600')
  text.setAttribute('dominant-baseline', 'hanging')
  text.setAttribute('pointer-events', 'none')
  text.textContent = annotation.text
  group.append(hitBox, text)
  if (annotation.id === selectedAnnotationId) {
    const box = document.createElementNS(namespace, 'rect')
    box.setAttribute('x', annotation.x - annotation.fontSize * 0.18)
    box.setAttribute('y', annotation.y - annotation.fontSize * 0.18)
    box.setAttribute('width', estimatedWidth + annotation.fontSize * 0.36)
    box.setAttribute('height', estimatedHeight + annotation.fontSize * 0.36)
    styleSelectionBox(box)
    box.setAttribute('pointer-events', 'none')
    group.append(box)
  }
  return group
}

function setLineGeometry(line, annotation) {
  line.setAttribute('x1', annotation.start.x)
  line.setAttribute('y1', annotation.start.y)
  line.setAttribute('x2', annotation.end.x)
  line.setAttribute('y2', annotation.end.y)
}

function setRectangleGeometry(rectangle, annotation) {
  rectangle.setAttribute('x', annotation.x)
  rectangle.setAttribute('y', annotation.y)
  rectangle.setAttribute('width', annotation.width)
  rectangle.setAttribute('height', annotation.height)
}

function appendArrowSelection(group, annotation) {
  const namespace = 'http://www.w3.org/2000/svg'
  const padding = Math.max(annotation.lineWidth * 2.5, 7 / Math.max(0.01, editorScale()))
  const box = document.createElementNS(namespace, 'rect')
  box.setAttribute('x', Math.min(annotation.start.x, annotation.end.x) - padding)
  box.setAttribute('y', Math.min(annotation.start.y, annotation.end.y) - padding)
  box.setAttribute('width', Math.abs(annotation.end.x - annotation.start.x) + padding * 2)
  box.setAttribute('height', Math.abs(annotation.end.y - annotation.start.y) + padding * 2)
  styleSelectionBox(box)
  box.setAttribute('pointer-events', 'none')
  group.append(box)
  group.append(createArrowHandle(annotation, 'start'), createArrowHandle(annotation, 'end'))
}

function appendRectangleSelection(group, annotation) {
  const namespace = 'http://www.w3.org/2000/svg'
  const padding = Math.max(annotation.lineWidth * 2, 5 / Math.max(0.01, editorScale()))
  const box = document.createElementNS(namespace, 'rect')
  box.setAttribute('x', annotation.x - padding)
  box.setAttribute('y', annotation.y - padding)
  box.setAttribute('width', annotation.width + padding * 2)
  box.setAttribute('height', annotation.height + padding * 2)
  styleSelectionBox(box)
  box.setAttribute('pointer-events', 'none')
  group.append(box)
  for (const handle of ['nw', 'ne', 'se', 'sw']) group.append(createRectangleHandle(annotation, handle))
}

function styleSelectionBox(box) {
  box.setAttribute('fill', 'none')
  box.setAttribute('stroke', '#78a9ff')
  box.setAttribute('stroke-width', 1.5 / Math.max(0.01, editorScale()))
  box.setAttribute('stroke-dasharray', `${5 / Math.max(0.01, editorScale())} ${4 / Math.max(0.01, editorScale())}`)
}

function createArrowHandle(annotation, handle) {
  const circle = document.createElementNS('http://www.w3.org/2000/svg', 'circle')
  const point = annotation[handle]
  circle.setAttribute('cx', point.x)
  circle.setAttribute('cy', point.y)
  circle.setAttribute('r', Math.max(annotation.lineWidth * 1.8, 5 / Math.max(0.01, editorScale())))
  circle.setAttribute('fill', '#ffffff')
  circle.setAttribute('stroke', '#4b8cff')
  circle.setAttribute('stroke-width', 2 / Math.max(0.01, editorScale()))
  circle.dataset.annotationId = annotation.id
  circle.dataset.handle = handle
  return circle
}

function createRectangleHandle(annotation, handle) {
  const circle = document.createElementNS('http://www.w3.org/2000/svg', 'circle')
  const east = handle.includes('e')
  const south = handle.includes('s')
  circle.setAttribute('cx', east ? annotation.x + annotation.width : annotation.x)
  circle.setAttribute('cy', south ? annotation.y + annotation.height : annotation.y)
  circle.setAttribute('r', Math.max(annotation.lineWidth * 1.8, 5 / Math.max(0.01, editorScale())))
  circle.setAttribute('fill', '#ffffff')
  circle.setAttribute('stroke', '#4b8cff')
  circle.setAttribute('stroke-width', 2 / Math.max(0.01, editorScale()))
  circle.dataset.annotationId = annotation.id
  circle.dataset.handle = handle
  return circle
}

function openTextEditor(point, annotationId = null) {
  textOrigin = point
  editingTextId = annotationId
  const existing = annotationId ? annotationById(annotationId) : null
  const scale = editorScale()
  const renderedX = point.x * scale
  const renderedY = point.y * scale
  const maximumLeft = Math.max(0, editorStage.clientWidth - 220)
  textEditor.style.left = `${Math.min(maximumLeft, Math.max(0, renderedX))}px`
  const maximumTop = Math.max(0, editorStage.clientHeight - 72)
  textEditor.style.top = `${Math.min(maximumTop, Math.max(0, renderedY))}px`
  textEditorInput.value = existing?.text || ''
  textEditor.hidden = false
  textEditorInput.focus()
}

function commitTextAnnotation() {
  const value = textEditorInput.value.trim()
  if (value && textOrigin && editingTextId) {
    const annotation = annotationById(editingTextId)
    if (annotation && annotation.text !== value) {
      recordAnnotationHistory()
      annotation.text = value
    }
    selectedAnnotationId = editingTextId
  } else if (value && textOrigin) {
    recordAnnotationHistory()
    const annotation = {
      id: nextAnnotationId(),
      type: 'text',
      x: textOrigin.x,
      y: textOrigin.y,
      text: value,
      fontSize: Math.max(12, 20 / Math.max(0.01, editorScale())),
      color: '#ff4d67'
    }
    annotations.push(annotation)
    selectedAnnotationId = annotation.id
  }
  closeTextEditor()
  setEditorTool('select')
  renderAnnotations()
}

function closeTextEditor() {
  textOrigin = null
  editingTextId = null
  textEditor.hidden = true
  textEditorInput.value = ''
}

function undoLastAnnotation() {
  if (resultBusy || annotationHistory.length === 0) return
  annotations = annotationHistory.pop()
  selectedAnnotationId = null
  closeTextEditor()
  renderAnnotations()
}

function deleteSelectedAnnotation() {
  const index = annotations.findIndex(annotation => annotation.id === selectedAnnotationId)
  if (index < 0 || resultBusy) return
  recordAnnotationHistory()
  annotations.splice(index, 1)
  selectedAnnotationId = null
  renderAnnotations()
}

function beginAnnotationDrag(event, point, annotationId, kind) {
  const annotation = annotationById(annotationId)
  if (!annotation) return
  event.preventDefault()
  selectedAnnotationId = annotationId
  annotationLayer.setPointerCapture(event.pointerId)
  annotationDrag = {
    annotationId,
    kind,
    start: point,
    original: cloneAnnotation(annotation),
    changed: false
  }
  renderAnnotations()
}

function updateAnnotationDrag(point) {
  const drag = annotationDrag
  const annotation = drag && annotationById(drag.annotationId)
  if (!annotation) return
  const dx = point.x - drag.start.x
  const dy = point.y - drag.start.y
  drag.changed = drag.changed || Math.hypot(dx, dy) >= 0.5
  const index = annotations.findIndex(candidate => candidate.id === drag.annotationId)
  if (drag.original.type === 'arrow' && (drag.kind === 'start' || drag.kind === 'end')) {
    annotations[index] = annotationModel.moveArrowEndpoint(
      drag.original,
      drag.kind,
      point,
      resultImage.naturalWidth,
      resultImage.naturalHeight
    )
  } else if (drag.original.type === 'rectangle' && ['nw', 'ne', 'se', 'sw'].includes(drag.kind)) {
    annotations[index] = annotationModel.resizeRectangle(
      drag.original,
      drag.kind,
      point,
      resultImage.naturalWidth,
      resultImage.naturalHeight,
      Math.max(3, drag.original.lineWidth)
    )
  } else {
    annotations[index] = annotationModel.translateAnnotation(
      drag.original,
      dx,
      dy,
      resultImage.naturalWidth,
      resultImage.naturalHeight
    )
  }
  renderAnnotations()
}

function finishAnnotationDrag() {
  if (annotationDrag?.changed) annotationHistory.push(annotationsBeforeDrag(annotationDrag))
  annotationDrag = null
  trimAnnotationHistory()
  renderAnnotations()
}

function cancelAnnotationDrag() {
  if (!annotationDrag) return
  const index = annotations.findIndex(annotation => annotation.id === annotationDrag.annotationId)
  if (index >= 0) annotations[index] = annotationDrag.original
  annotationDrag = null
}

function annotationsBeforeDrag(drag) {
  return annotations.map(annotation => annotation.id === drag.annotationId ? cloneAnnotation(drag.original) : cloneAnnotation(annotation))
}

function recordAnnotationHistory() {
  annotationHistory.push(annotations.map(cloneAnnotation))
  trimAnnotationHistory()
}

function trimAnnotationHistory() {
  if (annotationHistory.length > 100) annotationHistory.splice(0, annotationHistory.length - 100)
}

function annotationById(id) {
  return annotations.find(annotation => annotation.id === id)
}

function cloneAnnotation(annotation) {
  return annotation.type === 'arrow'
    ? { ...annotation, start: { ...annotation.start }, end: { ...annotation.end } }
    : { ...annotation }
}

function nextAnnotationId() {
  annotationSequence += 1
  return `annotation-${annotationSequence}`
}

function resetAnnotationEditor() {
  annotations = []
  annotationHistory = []
  draftArrow = null
  draftRectangle = null
  annotationDrag = null
  selectedAnnotationId = null
  resultBusy = false
  closeTextEditor()
  setEditorTool('select')
  annotationLayer.replaceChildren()
  editorStage.style.removeProperty('width')
  editorStage.style.removeProperty('height')
  selectToolButton.disabled = false
  arrowToolButton.disabled = false
  rectangleToolButton.disabled = false
  textToolButton.disabled = false
  undoEditButton.disabled = true
}

function serializedAnnotations() {
  return annotations.map(annotation => {
    if (annotation.type === 'arrow') return {
        type: 'arrow',
        startX: annotation.start.x,
        startY: annotation.start.y,
        endX: annotation.end.x,
        endY: annotation.end.y,
        lineWidth: annotation.lineWidth,
        color: annotation.color
      }
    if (annotation.type === 'rectangle') return {
      type: 'rectangle',
      x: annotation.x,
      y: annotation.y,
      width: annotation.width,
      height: annotation.height,
      lineWidth: annotation.lineWidth,
      color: annotation.color
    }
    return {
        type: 'text',
        x: annotation.x,
        y: annotation.y,
        text: annotation.text,
        fontSize: annotation.fontSize,
        color: annotation.color
      }
  })
}

async function exportAnnotationsIfNeeded() {
  if (annotations.length === 0) return completedPath
  const response = await window.langShot.request('editor.export', {
    sourcePath: completedPath,
    annotations: serializedAnnotations()
  })
  if (!response?.path) throw new Error('原生编辑器没有返回图片路径')
  completedPath = response.path
  resultPath.textContent = completedPath
  annotations = []
  annotationHistory = []
  draftArrow = null
  draftRectangle = null
  selectedAnnotationId = null
  closeTextEditor()
  setEditorTool('select')
  renderAnnotations()
  resultImage.src = `file://${completedPath}`
  return completedPath
}

function setResultBusy(value, label = '复制图片') {
  resultBusy = value
  copyButton.disabled = value
  revealButton.disabled = value
  selectToolButton.disabled = value
  arrowToolButton.disabled = value
  rectangleToolButton.disabled = value
  textToolButton.disabled = value
  copyButton.textContent = value ? label : '复制图片'
  renderAnnotations()
}

function missingPermissions(permissions) {
  const missing = []
  if (!permissions.screenRecording) missing.push('screenRecording')
  if (state.mode === 'automatic' && !permissions.accessibility) missing.push('accessibility')
  return missing
}

function showPermissionDialog(missing) {
  permissionItems.replaceChildren(...missing.map(createPermissionItem))
  permissionDialog.hidden = false
  window.langShot.showMainWindow()
  retryPermissionButton.focus()
}

function createPermissionItem(kind) {
  const details = permissionDetails[kind]
  const item = document.createElement('article')
  item.className = 'permission-item'

  const icon = document.createElement('span')
  icon.className = 'permission-item-icon'
  icon.textContent = details.icon

  const copy = document.createElement('div')
  const title = document.createElement('strong')
  title.textContent = details.title
  const description = document.createElement('small')
  description.textContent = details.description
  copy.append(title, description)

  const button = document.createElement('button')
  button.className = 'secondary permission-request'
  button.dataset.permission = kind
  button.textContent = '请求授权'
  item.append(icon, copy, button)
  return item
}

function closePermissionDialog() {
  permissionDialog.hidden = true
}

async function resumeAfterPermission() {
  closePermissionDialog()
  setBusy(true)
  try {
    await beginCapture()
  } catch (error) {
    showToast(error.message || '无法启动截图')
    window.langShot.showMainWindow()
  } finally {
    setBusy(false)
  }
}

async function beginCapture() {
  window.langShot.hideMainWindow()
  await window.langShot.request('session.begin', { mode: state.mode, direction: state.direction })
}

function showResult(filePath, warnings = []) {
  completedPath = filePath
  setPreviewMode('actual')
  resetAnnotationEditor()
  setResultBusy(false)
  resultPath.textContent = filePath || '已保存到 ~/langshots/'
  resultPanel.hidden = false
  resultImage.src = filePath ? `file://${filePath}` : ''
  requestAnimationFrame(layoutEditorImage)
  copyButton.focus()
  const warning = captureWarningMessage(warnings)
  if (warning) showToast(warning)
}

function captureWarningMessage(warnings) {
  const messages = []
  if (warnings?.includes('noMovementDetected')) messages.push('未检测到有效滚动，结果可能只包含首屏')
  if (warnings?.includes('matchingSkipped')) messages.push('部分画面未能可靠匹配，请检查长图是否完整')
  return messages.join('；')
}

function resetForNewEntry() {
  clearTimeout(copyButton.resetTimer)
  clearTimeout(showToast.timer)
  completedPath = null
  previewMode = 'actual'
  resetAnnotationEditor()
  state.mode = 'simple'
  state.direction = 'down'
  state.busy = false
  syncModeUI()
  for (const button of directionButtons) button.classList.toggle('selected', button.dataset.direction === state.direction)
  resultPanel.hidden = true
  resultImage.removeAttribute('src')
  resultPath.textContent = ''
  setResultBusy(false)
  permissionDialog.hidden = true
  permissionItems.replaceChildren()
  toast.hidden = true
  toast.textContent = ''
  startButton.disabled = false
  startButton.textContent = '选择截图区域'
  void startCaptureFlow()
}

function syncModeUI() {
  for (const button of modeButtons) button.classList.toggle('selected', button.dataset.mode === state.mode)
  directionRow.hidden = state.mode === 'simple'
}

function setBusy(value) {
  state.busy = value
  startButton.disabled = value
  startButton.textContent = value ? '正在准备…' : '选择截图区域'
}

function showToast(message) {
  toast.textContent = message
  toast.hidden = false
  clearTimeout(showToast.timer)
  showToast.timer = setTimeout(() => { toast.hidden = true }, 3200)
}
