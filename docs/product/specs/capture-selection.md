# Capture and Selection Specification

## ADDED Requirements

### Requirement: Capture-first plugin entry

系统 MUST 将原生鼠标框选作为搜索结果与快捷键打开插件后的第一交互界面，并 SHALL 在任何异步权限检查前同步隐藏 uTools 插件主窗口，避免首页在框选前出现或闪烁。

#### Scenario: User opens langShot from uTools

- **WHEN** 用户通过搜索结果或快捷键进入 langShot，且屏幕录制权限可用
- **THEN** 系统直接显示鼠标框选覆盖层，默认使用简单截图，不经过可见的插件首页

#### Scenario: User cancels region selection

- **WHEN** 用户在框选阶段按 `Esc` 或点击取消
- **THEN** 系统关闭框选覆盖层并显示插件首页，且不生成截图或保留本次临时帧

### Requirement: Permission-gated capture

系统 MUST 在进入选区前检查屏幕录制权限，并在自动滚动前额外检查辅助功能权限；权限不足时不得启动一个注定失败的会话。

#### Scenario: Screen recording permission is denied

- **WHEN** 用户启动截图但屏幕录制权限不可用
- **THEN** 系统显示阻断式授权引导弹窗，解释权限用途、提示在系统设置中查找 `langshot-helper`（部分系统可能显示为 `uTools`）、提供请求授权和对应设置页入口，并提供“我已授权，重新检测”操作；授权成功前不创建采集会话

#### Scenario: Multiple required permissions are missing

- **WHEN** 自动滚动模式同时缺少屏幕录制和辅助功能权限
- **THEN** 引导弹窗逐项列出两项权限及各自用途，用户可以分别请求授权，重新检测时只保留仍缺失的项目

#### Scenario: macOS requires the application to reopen

- **WHEN** 用户打开权限开关且 macOS 提示退出并重新打开应用
- **THEN** 引导明确要求遵循系统提示，并说明重新进入 langShot 后再次检测权限

#### Scenario: Manual capture does not need accessibility permission

- **WHEN** 屏幕录制权限已授予而辅助功能权限未授予，且用户选择手动滚动
- **THEN** 系统允许进入手动采集，不要求与该模式无关的权限

### Requirement: Single-display region selection

系统 SHALL 允许用户在任意单块显示器内拖拽选区，通过四边、四角和键盘进行像素级调整，并 MUST 阻止选区跨越显示器边界。

#### Scenario: Pointer recommends an accessible element

- **WHEN** 鼠标移动到目标应用暴露的网页内容区、侧栏、列表、表格、对话框或其他可访问元素上
- **THEN** 系统实时高亮一个位于当前显示器内的元素级候选区域，且不立即锁定或开始截图

#### Scenario: Element recommendation is unavailable

- **WHEN** 目标应用没有暴露可靠的辅助功能元素，或当前没有辅助功能权限
- **THEN** 系统回退到鼠标下方的应用窗口候选，用户仍可自由拖拽框选

#### Scenario: Recommended region is clicked

- **WHEN** 用户单击当前推荐区域
- **THEN** 系统锁定该候选并显示四边、四角及最终确认操作，但用户仍可移动、缩放或重新框选

#### Scenario: Locked recommendation is finally confirmed

- **WHEN** 用户点击“确认选区”或按 `Enter`
- **THEN** 系统才把当前可调整选区提交给后续锚点或采集流程

#### Scenario: User finishes a freeform drag

- **WHEN** 用户自由拖拽出有效选区并松开鼠标，或移动/缩放已锁定选区后松开鼠标
- **THEN** 系统立即确认最终矩形并进入后续流程，不要求再点击一次“确认选区”

#### Scenario: Selection reaches a display edge

- **WHEN** 用户把选区手柄拖过当前显示器边缘
- **THEN** 选区被限制在该显示器可捕获边界内，尺寸反馈保持有效

#### Scenario: User reselects or cancels

- **WHEN** 用户点击重新框选或在框选阶段按 `Esc`
- **THEN** 系统分别清除当前选区并重新进入框选，或立即退出截图且不保留临时帧；即使遮罩视图不是当前键盘焦点也必须响应 `Esc`

### Requirement: Native-pixel capture

系统 SHALL 使用当前显示器的原始物理像素捕获选区，不得因 Web 预览、显示缩放或输出流程对最终图像降采样。

#### Scenario: Retina selection is captured

- **WHEN** 逻辑尺寸为 720×450 point、缩放系数为 2 的选区被捕获
- **THEN** 对应帧的物理尺寸为 1440×900 pixel，像素级验证不包含人为缩放

### Requirement: Overlay exclusion

系统 MUST 从捕获帧中排除选区边框、遮罩、工具栏、状态卡片和 langShot 自身窗口。

#### Scenario: Capture occurs while overlay is visible

- **WHEN** 用户正在看到覆盖层且采样器生成一帧
- **THEN** 该帧只包含覆盖层下方的目标应用内容，不包含 langShot UI 像素

### Requirement: Manual dynamic selection

手动滚动会话 SHALL 允许采集中改变选区；每一帧 MUST 记录捕获时的显示器、物理像素矩形和缩放系数。

#### Scenario: Width changes during manual capture

- **WHEN** 用户在已有帧后扩大或缩小选区宽度
- **THEN** 后续帧使用新矩形，已有帧保持不变，并可按全局横坐标重建最终画布

### Requirement: Automatic selection lock and anchor

自动滚动会话 MUST 在开始前要求用户在选区内设置滚动锚点，并 SHALL 在开始后锁定选区。

#### Scenario: Anchor is outside selection

- **WHEN** 用户点击选区外作为滚动锚点
- **THEN** 系统拒绝该点并继续等待选区内的有效锚点

#### Scenario: Resize is attempted during automatic scrolling

- **WHEN** 自动滚动已开始且用户尝试拖动选区边界
- **THEN** 选区保持不变，界面提示自动模式已锁定区域
