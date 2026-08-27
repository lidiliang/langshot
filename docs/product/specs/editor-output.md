# Editor and Output Specification

## ADDED Requirements

### Requirement: Post-capture non-destructive editor

系统 SHALL 仅在长图生成后提供箭头、矩形、圆形、文字、画笔、马赛克和裁剪，并 MUST 以非破坏性操作模型保存编辑状态直到导出。

#### Scenario: Annotation is edited before export

- **WHEN** 用户添加标注后移动、修改或删除它
- **THEN** 原始拼接块不被改写，预览和导出使用最新操作模型

### Requirement: Undo and redo

编辑器 MUST 支持 `Cmd+Z` 撤销和 `Cmd+Shift+Z` 重做，并 SHALL 在产生新分支操作后清空不可达的重做分支。

#### Scenario: User undoes and branches

- **WHEN** 用户撤销一个操作后创建新的标注
- **THEN** 新标注生效，原先被撤销操作不可再通过重做恢复

### Requirement: Scaled preview with original-coordinate edits

编辑器 SHALL 使用缩略/分块预览显示超长图，但所有裁剪和标注几何 MUST 存储为原始物理像素坐标。

#### Scenario: Annotation is placed while zoomed out

- **WHEN** 用户在非 100% 缩放下添加箭头
- **THEN** 导出时箭头落在对应的原始像素位置，缩放预览不会降低底图清晰度

### Requirement: Output formats and quality

系统 MUST 支持无损 PNG、JPG 和 WebP；高/中/低质量设置 SHALL 只影响 JPG/WebP。无 alpha 格式 MUST 使用可配置背景色填充透明像素，默认白色。

#### Scenario: PNG is exported

- **WHEN** 用户选择 PNG，不论当前有损质量档位为何
- **THEN** 导出使用无损编码并保留透明区域

#### Scenario: JPG is exported from a dynamic-width image

- **WHEN** 透明长图导出为 JPG
- **THEN** 透明像素先以当前背景色合成，再按选择的质量编码

### Requirement: Save destinations

系统 SHALL 支持保存到桌面和用户选择的路径，使用无冲突文件名，并 MUST 在写入失败时保留当前会话以便重试。

#### Scenario: Destination is not writable

- **WHEN** 导出路径无写权限或磁盘空间不足
- **THEN** 系统显示具体失败原因、允许重新选择路径，且编辑内容和原始块仍存在

### Requirement: Clipboard policy

自动复制 SHALL 是默认关闭的持久设置；超大图片复制前 MUST 提示，复制失败不得影响保存能力。

#### Scenario: Clipboard write fails

- **WHEN** 系统或目标格式无法接受生成的长图
- **THEN** 界面报告复制失败并突出显示保存 PNG 操作，不关闭编辑器
