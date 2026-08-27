# Capture and Selection Specification

## ADDED Requirements

### Requirement: Permission-gated capture

系统 MUST 在进入选区前检查屏幕录制权限，并在自动滚动前额外检查辅助功能权限；权限不足时不得启动一个注定失败的会话。

#### Scenario: Screen recording permission is denied

- **WHEN** 用户启动截图但屏幕录制权限不可用
- **THEN** 系统显示所缺权限、打开系统设置的操作入口和授权后重试入口，且不创建采集会话

#### Scenario: Manual capture does not need accessibility permission

- **WHEN** 屏幕录制权限已授予而辅助功能权限未授予，且用户选择手动滚动
- **THEN** 系统允许进入手动采集，不要求与该模式无关的权限

### Requirement: Single-display region selection

系统 SHALL 允许用户在任意单块显示器内拖拽选区，通过四边、四角和键盘进行像素级调整，并 MUST 阻止选区跨越显示器边界。

#### Scenario: Selection reaches a display edge

- **WHEN** 用户把选区手柄拖过当前显示器边缘
- **THEN** 选区被限制在该显示器可捕获边界内，尺寸反馈保持有效

#### Scenario: User reselects or cancels

- **WHEN** 用户点击重新框选或在框选阶段按 `Esc`
- **THEN** 系统分别清除当前选区并重新进入框选，或退出截图且不保留临时帧

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
