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

#### Scenario: User scrolls by most of a viewport

- **WHEN** 相邻采样画面之间产生较大位移但仍保留至少约 12% 的唯一可辨识重叠
- **THEN** 手动模式扩大搜索窗口并恢复真实位移，不因旧的 35% 最小重叠限制而跳过内容；固定左右边带不得把位移结果拉小

### Requirement: Controlled automatic scrolling

自动模式 SHALL 向确认的滚动锚点发送可调速的滚轮事件，并提供开始、暂停、继续和完成控制；焦点或目标应用异常时 MUST 暂停。

#### Scenario: User changes speed

- **WHEN** 自动采集处于 `capturing` 且用户调整速度
- **THEN** 后续滚动事件使用新速度，已捕获帧和拼接状态不被重置

#### Scenario: Target loses safe focus

- **WHEN** 自动滚动期间前台应用发生变化或锚点所在屏幕失效
- **THEN** 系统停止发送滚动事件并进入带原因的暂停状态

#### Scenario: User moves the pointer away from the anchor

- **WHEN** 自动滚动正在向锚点所属目标进程发送滚轮事件，且用户把鼠标移出截图区域
- **THEN** 系统继续向目标进程滚动但不得移动、锁定或抢回鼠标指针，用户仍可操作状态控制卡或其他应用

#### Scenario: Capture overlay yields focus to the target

- **WHEN** 用户确认自动滚动锚点并进入采集
- **THEN** 截图框和控制卡继续置顶可见但不得激活 helper 或抢走目标应用焦点；系统滚轮事件使用锚点位置进入系统事件流并驱动目标内容滚动

#### Scenario: Previous automatic frame is still being processed

- **WHEN** 自动模式已发送一次滚轮事件，而对应画面尚未完成稳定等待、捕获、重叠识别和帧入库
- **THEN** 系统不得发送下一次滚轮事件；只有当前步确认入库或确认画面没有移动后，反馈闭环才能进入下一步

#### Scenario: Automatic alignment confidence drops

- **WHEN** 当前自动滚动帧发生变化但无法可靠对齐
- **THEN** 系统把滚动步长降到最小并在当前位置持续重采，不继续向前滚动，也不得丢弃该帧后从更靠后的位置重新同步

#### Scenario: Initial weak match has no displacement history

- **WHEN** 自动模式首个小步滚动已经产生画面变化，但尚无历史位移，候选略低于常规阈值且位移不超过探针高度四分之一
- **THEN** 系统按安全下限接受该首段以建立历史；若仍无法接受，连续六次重采后自动追加一次最小恢复探测，并继续相对最后有效帧匹配，不等待用户手动滚动

#### Scenario: Capture controls remain clickable

- **WHEN** 长截图处于采集或暂停状态
- **THEN** 蓝色截图选框和独立可点击的“暂停/继续”“完成”“取消”状态卡始终置顶可见；目标应用重新获得焦点或 helper 失去激活状态时不得隐藏，全屏捕获遮罩不得拦截其鼠标事件

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

#### Scenario: Enter is pressed while capturing or paused

- **WHEN** 用户按下普通 `Enter` 或数字键盘 `Enter`
- **THEN** 系统立即停止滚动并进入 `finishing`，无论截图目标应用还是控制卡当前持有键盘焦点

### Requirement: Non-blocking recognition recovery and limits

系统 MUST 支持到底、高度上限和自动滚动时长上限三类结束保护。无位移或匹配置信度不足属于内部识别状态，MUST NOT 自动进入暂停、显示“点击继续”或要求用户介入；只有用户主动暂停才可把控制卡切换为“继续”。

#### Scenario: No effective movement remains

- **WHEN** 连续规定数量的帧均没有通过有效位移阈值
- **THEN** 系统继续保持采集控制可用但不追加重复画面，不自动完成、不跳转结果页，也不插入“疑似到底”或“点击继续”的暂停；等待用户点击“完成”或按 `Enter`

#### Scenario: Automatic scrolling has not produced its first movement

- **WHEN** 已保存首帧但从未检测到真实滚动位移，包括滚动事件未生效或锚点无效的情况
- **THEN** 系统继续发送滚动并采样，不暂停、不显示“尚未检测到滚动”或“点击继续”、不自动完成；用户仍可随时主动完成或取消，主动完成后可在结果页提示可能只包含首屏

#### Scenario: Frame matching is temporarily uncertain

- **WHEN** 当前画面相对上一有效帧发生变化，但重叠匹配置信度不足
- **THEN** 系统先在不追加错误内容的前提下原地重采，连续失败时跳过不可靠过渡并重新同步后续帧；采集控制保持运行，完整性提示只允许在截图成功后非阻塞显示

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
