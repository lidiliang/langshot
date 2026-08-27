# Stitching Delta Specification

## ADDED Requirements

### Requirement: Lossless intermediate frames

系统 MUST 以内存缓冲或无损本地块保存采集帧，不得在重叠检测和最终导出前使用有损压缩。

#### Scenario: Session is restored from disk tiles

- **WHEN** 已接受帧从会话临时目录重新加载
- **THEN** 加载后的像素与原捕获帧逐像素一致

### Requirement: Vertical overlap estimation

拼接器 SHALL 在相邻有效帧的共同横向区域内估计垂直位移，并 MUST 使用多条内容带的一致性和匹配分数生成置信度。

#### Scenario: Valid overlapping frames are supplied

- **WHEN** 两帧包含足够纹理且具有已知垂直重叠
- **THEN** 估计位移位于验收容差内，仅把非重复内容追加到结果

#### Scenario: Content is ambiguous

- **WHEN** 大面积纯色、动画或重复纹理使候选位移缺乏一致性
- **THEN** 匹配结果标记为低置信度，会话暂停而不是静默接受

### Requirement: Static region suppression

系统 SHALL 识别在屏幕坐标中持续不动、而邻近内容发生滚动的顶部、底部或侧向固定区域，并 MUST 在最终图像中仅合成一份固定内容。

#### Scenario: Sticky header remains unchanged

- **WHEN** 顶部导航在多帧中保持屏幕坐标不变且正文向同一方向移动
- **THEN** 导出图顶部只出现一份导航，导航像素不参与主内容位移投票

#### Scenario: Fixed bottom input remains unchanged

- **WHEN** 底部输入栏在多帧中固定而聊天内容滚动
- **THEN** 输入栏只在最终图底部出现一次，滚动正文保持连续

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

