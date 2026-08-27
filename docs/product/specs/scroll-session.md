# Scroll Session Specification

## ADDED Requirements

### Requirement: Explicit session state machine

采集会话 MUST 使用可验证的状态机表达 `selecting`、`ready`、`capturing`、`paused`、`finishing`、`completed`、`discarded` 和 `failed`，所有外部命令 SHALL 仅在允许的状态生效。

#### Scenario: Invalid command is received

- **WHEN** 会话处于 `finishing` 且收到 `resume`
- **THEN** 系统拒绝命令、保持当前状态并返回结构化错误，不崩溃也不破坏临时数据

### Requirement: Manual automatic sampling

手动模式 SHALL 监听用户滚动产生的内容位移，并在存在足够新内容时自动截帧；用户无需逐帧点击。

#### Scenario: User scrolls slowly

- **WHEN** 内容持续产生小于一屏的同向位移
- **THEN** 采样器按位移而非固定点击生成可拼接帧，且不会因相同内容重复堆叠高度

### Requirement: Controlled automatic scrolling

自动模式 SHALL 向确认的滚动锚点发送可调速的滚轮事件，并提供开始、暂停、继续和完成控制；焦点或目标应用异常时 MUST 暂停。

#### Scenario: User changes speed

- **WHEN** 自动采集处于 `capturing` 且用户调整速度
- **THEN** 后续滚动事件使用新速度，已捕获帧和拼接状态不被重置

#### Scenario: Target loses safe focus

- **WHEN** 自动滚动期间前台应用发生变化或锚点所在屏幕失效
- **THEN** 系统停止发送滚动事件并进入带原因的暂停状态

### Requirement: Single locked direction

每次会话 SHALL 支持向上或向下的单一垂直方向，并 MUST 在确认首个有效位移后锁定方向。

#### Scenario: Reverse movement is detected

- **WHEN** 已锁定向下而后续有效位移达到反向阈值
- **THEN** 系统暂停并提示方向反转，不把反向帧并入结果

### Requirement: Recoverable Escape behavior

采集中的第一次 `Esc` MUST 暂停并显示继续、完成、丢弃；暂停状态再次按 `Esc` MUST 丢弃会话。

#### Scenario: Escape is pressed while capturing

- **WHEN** 会话处于 `capturing` 且收到第一次 `Esc`
- **THEN** 系统进入 `paused`，停止采样和自动滚动，但保留全部有效帧

#### Scenario: Escape is pressed again while paused

- **WHEN** 会话因 `Esc` 暂停且再次收到 `Esc`
- **THEN** 系统要求明确的视觉反馈后进入 `discarded` 并清理会话临时目录

### Requirement: End detection and limits

系统 MUST 支持疑似到底、高度上限和自动滚动时长上限三类结束保护。疑似到底 SHALL 暂停倒计时并允许继续；高度达到 60,000 物理像素或默认 10 分钟到期 SHALL 暂停等待完成或丢弃。

#### Scenario: No effective movement remains

- **WHEN** 连续规定数量的帧均没有通过有效位移阈值
- **THEN** 系统进入“疑似到底”暂停并开始倒计时，倒计时无操作则完成，用户继续则恢复采集

#### Scenario: Height limit is reached

- **WHEN** 下一段有效内容会使结果超过 60,000 物理像素
- **THEN** 系统只保留不超过上限的内容并暂停提示完成，不分配超过限制的最终画布

#### Scenario: Configured duration expires

- **WHEN** 自动滚动达到用户配置的时长，且该值不大于默认 10 分钟
- **THEN** 系统停止滚动并暂停，保留已有内容等待用户决定

### Requirement: Progress feedback

采集期间系统 SHALL 至少报告有效高度、有效帧数、方向、模式、当前状态和暂停原因，并不得用阻塞拼接冻结覆盖层交互。

#### Scenario: A frame is accepted

- **WHEN** 拼接器接受一帧并计算出新内容
- **THEN** 状态卡片在可感知时间内更新高度和帧数，采集控制仍可响应
