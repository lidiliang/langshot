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
let completedPath = null

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
  if (event.key === 'Enter' && !event.repeat && resultPanel.hidden === false && permissionDialog.hidden && completedPath && !copyButton.disabled) {
    event.preventDefault()
    event.stopPropagation()
    copyCompletedImage()
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

copyButton.addEventListener('click', copyCompletedImage)

function copyCompletedImage() {
  if (!completedPath || copyButton.disabled) return
  try {
    window.langShot.copyImage(completedPath)
    showToast('图片已成功复制到剪贴板')
    copyButton.disabled = true
    copyButton.textContent = '已复制 ✓'
    clearTimeout(copyButton.resetTimer)
    copyButton.resetTimer = setTimeout(() => window.langShot.closePlugin(), 650)
  }
  catch (error) { showToast(error.message) }
}

revealButton.addEventListener('click', () => completedPath && window.langShot.revealFile(completedPath))

function missingPermissions(permissions) {
  const missing = []
  if (!permissions.screenRecording) missing.push('screenRecording')
  if (state.mode === 'automatic' && !permissions.accessibility) missing.push('accessibility')
  return missing
}

function showPermissionDialog(missing) {
  permissionItems.replaceChildren(...missing.map(createPermissionItem))
  permissionDialog.hidden = false
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
  resultPath.textContent = filePath || '已保存到 ~/langshots/'
  resultImage.src = filePath ? `file://${filePath}` : ''
  resultPanel.hidden = false
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
  state.mode = 'simple'
  state.direction = 'down'
  state.busy = false
  syncModeUI()
  for (const button of directionButtons) button.classList.toggle('selected', button.dataset.direction === state.direction)
  resultPanel.hidden = true
  resultImage.removeAttribute('src')
  resultPath.textContent = ''
  copyButton.disabled = false
  copyButton.textContent = '复制图片'
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
