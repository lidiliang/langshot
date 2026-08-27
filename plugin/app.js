'use strict'

const state = { mode: 'manual', direction: 'down', busy: false }
const modeButtons = Array.from(document.querySelectorAll('.mode-card'))
const directionButtons = Array.from(document.querySelectorAll('.direction'))
const startButton = document.getElementById('startButton')
const permissionCard = document.getElementById('permissionCard')
const permissionMessage = document.getElementById('permissionMessage')
const openSettingsButton = document.getElementById('openSettingsButton')
const toast = document.getElementById('toast')
const resultPanel = document.getElementById('resultPanel')
const resultImage = document.getElementById('resultImage')
const resultPath = document.getElementById('resultPath')
const copyButton = document.getElementById('copyButton')
const revealButton = document.getElementById('revealButton')
let completedPath = null

for (const button of modeButtons) {
  button.addEventListener('click', () => {
    state.mode = button.dataset.mode
    for (const candidate of modeButtons) candidate.classList.toggle('selected', candidate === button)
    permissionCard.hidden = true
  })
}

for (const button of directionButtons) {
  button.addEventListener('click', () => {
    state.direction = button.dataset.direction
    for (const candidate of directionButtons) candidate.classList.toggle('selected', candidate === button)
  })
}

startButton.addEventListener('click', async () => {
  if (state.busy) return
  setBusy(true)
  try {
    const permissions = await window.langShot.request('permissions.get')
    const missing = []
    if (!permissions.screenRecording) missing.push('屏幕录制')
    if (state.mode === 'automatic' && !permissions.accessibility) missing.push('辅助功能')
    if (missing.length) {
      permissionMessage.textContent = `请允许 ${missing.join('、')} 权限后重试。`
      permissionCard.hidden = false
      return
    }
    window.langShot.hideMainWindow()
    await window.langShot.request('session.begin', { mode: state.mode, direction: state.direction })
  } catch (error) {
    showToast(error.message || '无法启动截图')
    window.langShot.showMainWindow()
  } finally {
    setBusy(false)
  }
})

openSettingsButton.addEventListener('click', async () => {
  try { await window.langShot.request('permissions.openSettings', { mode: state.mode }) }
  catch (error) { showToast(error.message) }
})

window.langShot.subscribe(event => {
  if (event.type === 'session.completed' || event.type === 'session.cancelled' || event.type === 'error') {
    window.langShot.showMainWindow()
  }
  if (event.type === 'session.completed') showResult(event.payload?.path)
})

copyButton.addEventListener('click', () => {
  try { window.langShot.copyImage(completedPath); showToast('已复制到剪贴板') }
  catch (error) { showToast(error.message) }
})

revealButton.addEventListener('click', () => completedPath && window.langShot.revealFile(completedPath))

function showResult(filePath) {
  completedPath = filePath
  resultPath.textContent = filePath || '已保存到桌面'
  resultImage.src = filePath ? `file://${filePath}` : ''
  resultPanel.hidden = false
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
