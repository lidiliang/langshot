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

系统 SHALL 将截图完成后的 PNG 写入 `~/langshots/` 而非系统临时目录或桌面，首次保存时自动创建该目录，并使用无冲突文件名。langShot 每次启动时 SHALL 删除该目录内修改时间严格超过 7×24 小时、名称以 `langShot-` 开头且扩展名为受支持图片格式的普通文件；MUST NOT 跟随符号链接或删除无关文件。后续显式导出 SHALL 支持其他用户选择的路径，并 MUST 在写入失败时保留当前会话以便重试。

#### Scenario: Capture completes

- **WHEN** 长截图完成且 `~/langshots/` 尚不存在
- **THEN** 系统创建该目录并以唯一文件名保存 PNG，桌面和系统临时目录不会自动出现结果文件

#### Scenario: Destination is not writable

- **WHEN** 导出路径无写权限或磁盘空间不足
- **THEN** 系统显示具体失败原因、允许重新选择路径，且编辑内容和原始块仍存在

### Requirement: Clipboard policy

自动复制 SHALL 是默认关闭的持久设置；超大图片复制前 MUST 提示，复制失败不得影响保存能力。

#### Scenario: Clipboard write fails

- **WHEN** 系统或目标格式无法接受生成的长图
- **THEN** 界面报告复制失败并突出显示保存 PNG 操作，不关闭编辑器

#### Scenario: Clipboard write succeeds

- **WHEN** 用户点击“复制图片”且图片成功写入剪贴板
- **THEN** 结果界面显示不会被其他面板遮挡的成功提示，同时把复制按钮短暂切换为“已复制”状态，随后自动退出 langShot 插件页面

### Requirement: Fresh plugin entry state

uTools MAY 复用同一个 Web 页面实例，但 langShot MUST 在每次 `onPluginEnter` 时呈现新的默认首页，并 SHALL 隔离前后两次 helper 进程的退出事件。

#### Scenario: User reopens after copying a result

- **WHEN** 复制成功自动退出后，用户再次通过 uTools 搜索进入 langShot
- **THEN** 页面恢复自动模式、向下方向和可用的“选择截图区域”按钮，不显示旧图片、旧路径、旧复制状态或旧提示；前一个 helper 的延迟退出不得中断新 helper
