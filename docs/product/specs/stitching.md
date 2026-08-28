# Stitching Specification

## ADDED Requirements

### Requirement: Lossless intermediate frames

系统 MUST 以内存缓冲或无损本地块保存采集帧，不得在重叠检测和最终导出前使用有损压缩。

#### Scenario: Session is restored from disk tiles

- **WHEN** 已接受帧从会话临时目录重新加载
- **THEN** 加载后的像素与原捕获帧逐像素一致

### Requirement: Vertical overlap estimation

拼接器 SHALL 在相邻有效帧的共同横向区域内估计垂直位移，并 MUST 使用多条内容带的一致性和匹配分数生成置信度。

拼接器 SHALL 保留最近若干有效位移，以中位数预测下一帧候选范围。每个最终段 MUST 来自已经捕获的无损帧及其验证过的重叠关系；滚动控制不能替代后台多帧拼接。

#### Scenario: Valid overlapping frames are supplied

- **WHEN** 两帧包含足够纹理且具有已知垂直重叠
- **THEN** 估计位移位于验收容差内，仅把非重复内容追加到结果

#### Scenario: A weak match agrees with recent motion

- **WHEN** 候选置信度略低于常规阈值，但高于安全下限，且位移落在最近有效位移中位数的容差范围内
- **THEN** 系统可按历史预测接受该候选；若位移明显跳变或绝对置信度过低则仍拒绝，避免重复纹理制造错误拼接

#### Scenario: Content is ambiguous

- **WHEN** 大面积纯色、动画或重复纹理使多个候选位移近似同分，或候选不能满足最小重叠比例
- **THEN** 匹配结果标记为低置信度且不追加错误大位移；采集器在后台重采，连续失败时重新同步并记录完成后完整性提示，不暂停用户流程

#### Scenario: Repetitive rows create several exact matches

- **WHEN** 周期性列表、表格或代码行使多个不同位移都得到相同或近似的最佳分数
- **THEN** 若没有稳定的历史位移，系统判定结果存在歧义并拒绝该帧；若最近多帧位移稳定，系统优先选择历史预测范围内且像素误差接近全局最优值的候选，不得仅凭绝对相似度接受明显偏离历史运动的候选，也不得要求用户点击继续

#### Scenario: Captured frames are composed vertically

- **WHEN** 输入帧顶部和底部包含可区分的像素条带并生成最终长图
- **THEN** 每帧内部的上下像素方向和帧间的阅读顺序均与屏幕内容一致，不得上下翻转

### Requirement: Static region suppression

系统 SHALL 识别在屏幕坐标中持续不动、而邻近内容发生滚动的顶部、底部或侧向固定区域，并 MUST 在最终图像中仅合成一份固定内容。

系统 SHALL 同时识别选区内部尺寸较小、连续多帧位置和外观稳定的悬浮控件。若被遮挡的正文像素可从前后重叠帧恢复，拼接器 MUST 使用真实重叠帧补回正文，不得简单涂白或生成虚构内容；无法可靠恢复的末端位置 MAY 保留至多一个原始控件。

#### Scenario: A floating scroll button stays inside the content area

- **WHEN** 圆形箭头、返回顶部或向下滚动按钮在连续帧中保持同一屏幕坐标，而其周围正文按已确认位移滚动
- **THEN** 系统将其识别为内部悬浮控件，从下一张重叠帧提取同一正文位置的真实像素覆盖重复实例，最终长图不得沿滚动方向重复出现该按钮

#### Scenario: Sticky header remains unchanged

- **WHEN** 顶部导航在多帧中保持屏幕坐标不变且正文向同一方向移动
- **THEN** 导出图顶部只出现一份导航，导航像素不参与主内容位移投票

#### Scenario: Fixed bottom input remains unchanged

- **WHEN** 底部输入栏在多帧中固定而聊天内容滚动
- **THEN** 输入栏只在最终图底部出现一次，滚动正文保持连续

#### Scenario: Fixed sidebars remain unchanged

- **WHEN** 左侧导航、右侧工具栏或空白边带在滚动前后保持屏幕坐标不变
- **THEN** 这些连续静止的左右边带不参与垂直位移投票，正文位移不得因此被低估并产生重复内容

### Requirement: Dynamic-width canvas alignment

手动模式最终画布 SHALL 使用所有帧物理屏幕矩形的横向并集，并 MUST 按全局横坐标放置每段；未覆盖像素保持透明。

#### Scenario: Later frame is narrower and shifted

- **WHEN** 后续帧的左右边界均不同于前一帧
- **THEN** 两帧按各自横坐标对齐，较窄段之外的像素 alpha 为零，内容不得横向拉伸

### Requirement: Tile-backed composition

拼接器 MUST 以有界内存的分块画布处理最长 60,000px 输出，编辑缩略预览 SHALL 与原始块分离。

#### Scenario: Maximum-size synthetic image is composed

- **WHEN** 约 1440px 宽、60,000px 高的合成会话完成
- **THEN** 系统无需分配同尺寸的多份连续 RGBA 缓冲即可编码，峰值内存满足验收基准

### Requirement: Deterministic recovery data

每个活动会话 MUST 维护原子更新的清单，记录帧块、选区、位移、静止掩码、有效高度和协议版本；完成或丢弃后 SHALL 按策略清理。

#### Scenario: Helper restarts after frames were accepted

- **WHEN** 辅助程序意外退出后重新读取一个结构完整的活动会话
- **THEN** 系统能报告可恢复会话并从最后一个已提交帧继续完成或导出

#### Scenario: Manifest is incomplete

- **WHEN** 清单校验失败或引用缺失块
- **THEN** 系统拒绝继续拼接、保留诊断元数据并提供安全丢弃，不覆盖原有块
