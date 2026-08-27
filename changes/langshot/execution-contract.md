# langShot 执行契约

## Intent Lock

- **变更名称**：`langshot`
- **要解决的问题**：在 uTools 中提供无需逐帧点击、手动采集可动态调整选区、保持 Retina 原始像素且能可靠处理固定区域和失败恢复的 macOS 滚动长截图工具。
- **范围内**：uTools 插件、Swift/AppKit helper、单屏选区、手动/自动单向纵向滚动、权限与覆盖层、无损采集、智能拼接、60,000px 分块画布、截图后编辑、PNG/JPG/WebP、保存/剪贴板、Universal 构建及签名公证入口。
- **范围外**：跨屏、横向/二维或单次往返拼接；自动模式动态选区；采集时标注；自建全局快捷键；云服务/遥测；DRM 绕过；对矩阵外全部应用作保证。

## Approved Behavior

### 已批准需求摘要与任务映射

| 规格需求 | 批次任务 | 测试义务 |
|---|---|---|
| Permission-gated capture | 4, 9 | 手动模式不误要辅助功能；自动模式缺权限被门禁；拒绝/重试路径 |
| Single-display region selection | 4 | 任意单屏、边界限制、键盘微调、重选/取消 |
| Native-pixel capture | 4, 5 | point→pixel 黄金夹具；Retina 实图尺寸 |
| Overlay exclusion | 5 | 覆盖层可见时黄金截图不含 langShot UI |
| Manual dynamic selection | 4, 7, 9 | 选区改变后续帧；横向并集和透明空白 |
| Automatic selection lock and anchor | 4, 8, 9 | 锚点内约束；开始后禁止 resize |
| Explicit session state machine | 3, 8 | 全状态/命令矩阵和非法命令不变性 |
| Manual automatic sampling | 7, 8 | 慢速位移、静止去重、无需逐帧点击 |
| Controlled automatic scrolling | 8 | 调速、暂停/继续、焦点与锚点失效 |
| Single locked direction | 7, 8 | 向上/向下；反转暂停且帧不入库 |
| Recoverable Escape behavior | 3, 9 | 首次暂停保留、暂停后二次丢弃 |
| End detection and limits | 3, 8 | 疑似到底倒计时、10 分钟、60,000px |
| Progress feedback | 3, 8, 9 | 高度/帧数/方向/模式/状态/原因非阻塞更新 |
| Lossless intermediate frames | 6 | tile round-trip 像素一致 |
| Vertical overlap estimation | 7 | 已知偏移容差、低纹理/重复纹理拒绝 |
| Static region suppression | 7 | 固定顶/底/侧只保留一次 |
| Dynamic-width canvas alignment | 7 | 全局横坐标、不缩放、alpha 透明 |
| Tile-backed composition | 6, 7, 10, 12, 16 | 1440×60,000 有界内存和流式编码 |
| Deterministic recovery data | 6, 14 | 原子清单、重启恢复、坏清单不覆盖 |
| Post-capture non-destructive editor | 10, 11, 12 | 七类编辑操作不改原 tile |
| Undo and redo | 11 | Cmd 快捷键、撤销分支清空 redo |
| Scaled preview with original-coordinate edits | 10, 11, 12 | 非 100% 缩放的原像素落点 |
| Output formats and quality | 12 | PNG 无损/alpha；JPG/WebP 质量和背景色 |
| Save destinations | 9, 13 | 桌面/自定义/冲突名；失败保留会话 |
| Clipboard policy | 9, 13 | 默认关闭、超大图提示、失败可保存 |
| uTools integration | 1, 3, 9 | API v2 manifest、入口、helper 版本门禁 |
| Versioned local IPC | 2, 3 | 跨语言接受/拒绝夹具、坏行和未知版本 |
| Universal and minimum-version build | 1, 15 | lipo 双架构、10.15 deployment target |
| Local-only privacy | 2, 14, 15 | 无网络路径；日志敏感内容扫描 |
| Performance baseline | 7, 8, 12, 16 | 10fps/CPU 目标、RSS <500MB 硬门槛 |
| Compatibility matrix | 9, 17 | 六应用、上下、手动/自动、固定区域记录 |
| Recoverable errors and cleanup | 3, 6, 13, 14 | helper/路径/编码/剪贴板失败和过期清理 |
| Signed and unsigned delivery paths | 15 | 无凭据开发包；有凭据签名公证验证 |

### 关键验收场景

- 普通屏与 Retina 的选区尺寸、像素内容、坐标转换和覆盖层排除。
- 手动慢速滚动和自动锚点滚动；向上/向下各自锁定，反转安全暂停。
- 动态选区横向并集、固定顶栏/底栏、低纹理和动画干扰的接受/拒绝。
- 疑似到底、首次/二次 Esc、焦点丢失、10 分钟和 60,000px 边界。
- helper 崩溃恢复、坏 manifest、不可写路径、编码和剪贴板失败。
- 60,000px 编辑预览和导出不创建整图多份 RGBA 缓冲。

### 验收检查

- 所有 Swift、TypeScript、协议契约和黄金图测试通过。
- `ssf validate changes/langshot` 为 0 错误、0 警告。
- Apple Silicon 1440×60,000 基准峰值 RSS 小于 500MB；帧率/CPU 目标有报告。
- Universal 产物含 arm64/x86_64，deployment target 不高于 10.15，插件包小于 20MB。
- 六应用兼容矩阵填写实际版本、场景、结果和限制。

## Design Constraints

- **架构约束**：uTools renderer → 枚举化 preload API → 单实例 Swift helper；helper 是会话状态唯一权威。覆盖层、捕获、滚动和拼接在原生侧；Web 仅负责控制和非破坏性编辑。
- **接口约束**：stdin/stdout JSON Lines v1；每条消息含协议版本和 request ID，事件含 session ID/sequence；图片不得 Base64 进 IPC；renderer 不接受任意文件路径或 shell 能力。
- **依赖约束**：最低路径仅使用 macOS 10.15 可用 API；CoreGraphics/Accelerate/ImageIO 优先；不得引入导致 20MB 门禁失败的大型依赖。WebP 若 ImageIO 不可用，只允许体积受控的 bundled libwebp fallback。
- **数据约束**：跨语言持久化使用左上角原始物理像素坐标；无损 tile + 原子 versioned manifest；Web 预览与原始 tile 分离；日志不含图像、OCR、窗口标题或可见内容。
- **构建约束**：Swift Package 是源码权威；当前环境必须先通过未签名开发构建。正式签名、公证实跑依赖完整 Xcode、Developer ID 和凭据，不得伪造通过证据。
- **工作区约束**：现有 `changes/langshot/` 规划材料属于批准基线；实现不得静默改写其行为。

## Build Rules

1. 行为实现必须先有能失败的测试或黄金夹具；纯样式/文档/人工系统步骤允许使用边界验证而非伪造单测。
2. 每个 wave 只修改列出的任务区域及为测试/构建必需的共享文件；发现范围外行为先停止并按 Escalation Rules 处理。
3. 不以降低原始分辨率、跳过低置信度门禁或牺牲恢复数据来通过性能指标。
4. 任何真实系统测试产生的截图只保留在被忽略的临时目录，不提交仓库；提交的黄金图必须为程序生成或无隐私夹具。
5. 每个 wave 在 review 前运行该 wave 的聚焦测试和当时可运行的全量检查，并保存报告。

## Execution Plan

DP-3 批准后先运行 `ssf execution recommend`，使用下列固定 waves 生成与当前 artifact/contract hash 匹配的 recommendation receipt。用户在 DP-4 选择 `inline`、`batch-inline` 或 `sdd` 后，才运行 `ssf execution plan --confirm` 并开始实现。模式不写死在本契约内。

## Execution Waves

### Wave 1 — foundation

- **Wave ID**：`foundation`
- **任务**：1, 2, 3
- **依赖 wave**：无
- **策略**：`serial`
- **目标**：建立可构建项目、跨语言协议、helper 生命周期和会话 reducer。
- **输入**：批准规划包、协议与状态规格。
- **输出**：uTools/Swift 脚手架、协议 fixtures、helper-client、状态机及测试。
- **完成标准**：任务 1–3 的证据命令通过；无未映射协议/状态需求。
- **Review gate**：`changes/langshot/reviews/foundation.md`，记录实际 base/head SHA，并写入 `ssf execution review --wave foundation ... --verdict pass|fail`。

### Wave 2 — native-capture

- **Wave ID**：`native-capture`
- **任务**：4, 5, 6
- **依赖 wave**：`foundation`
- **策略**：`serial`
- **目标**：完成权限、坐标、选区覆盖层、原始像素捕获和原子 tile 恢复。
- **输入**：通过 review 的 foundation、真实显示器环境。
- **输出**：Platform/Overlay/Capture/SessionStore 模块与证据。
- **完成标准**：坐标/捕获/存储测试通过；Retina 与覆盖层排除人工记录可复核。
- **Review gate**：`changes/langshot/reviews/native-capture.md` + current pass receipt。

### Wave 3 — stitching-scroll

- **Wave ID**：`stitching-scroll`
- **任务**：7, 8
- **依赖 wave**：`native-capture`
- **策略**：`serial`
- **目标**：实现重叠、静止区域、动态宽度和两种滚动控制器。
- **输入**：通过 review 的 capture/store、生成式黄金图。
- **输出**：Stitching/Scroll 模块、黄金结果和边界测试。
- **完成标准**：向上/下、固定区域、反转、到底、时长和高度限制全部通过。
- **Review gate**：`changes/langshot/reviews/stitching-scroll.md` + current pass receipt。

### Wave 4 — mvp

- **Wave ID**：`mvp`
- **任务**：9
- **依赖 wave**：`stitching-scroll`
- **策略**：`serial`
- **目标**：形成 uTools 内可运行的端到端核心 MVP。
- **输入**：通过 review 的原生采集与滚动链路。
- **输出**：plugin manifest/preload/UI、PNG、保存/复制和 MVP 验收记录。
- **完成标准**：构建成功，权限—选区—采集—完成—PNG 路径贯通。
- **Review gate**：`changes/langshot/reviews/mvp.md` + current pass receipt。

### Wave 5 — editor

- **Wave ID**：`editor`
- **任务**：10, 11
- **依赖 wave**：`mvp`
- **策略**：`serial`
- **目标**：完成 tile 预览和非破坏性编辑模型/交互。
- **输入**：通过 review 的会话文件和 MVP UI。
- **输出**：preview pyramid、受控 tile bridge、七类工具和历史。
- **完成标准**：60,000px viewport 不创建整图 canvas；原像素坐标和撤销分支测试通过。
- **Review gate**：`changes/langshot/reviews/editor.md` + current pass receipt。

### Wave 6 — output-hardening

- **Wave ID**：`output-hardening`
- **任务**：12, 13, 14
- **依赖 wave**：`editor`
- **策略**：`serial`
- **目标**：流式导出三格式、完整保存/剪贴板设置及隐私安全恢复。
- **输入**：通过 review 的 edit document 和 tile store。
- **输出**：Native Export、格式黄金图、设置/失败 UI、诊断与清理。
- **完成标准**：三格式、透明/背景、质量、失败恢复和日志扫描证据通过；包体仍可满足门禁。
- **Review gate**：`changes/langshot/reviews/output-hardening.md` + current pass receipt。

### Wave 7 — release-qualification

- **Wave ID**：`release-qualification`
- **任务**：15, 16, 17, 18
- **依赖 wave**：`output-hardening`
- **策略**：`serial`
- **目标**：完成构建、性能、兼容矩阵和交付文档。
- **输入**：通过 review 的完整 v1 实现、可用测试机器/应用；正式签名步骤另需证书。
- **输出**：开发包、构建验证、性能报告、兼容矩阵、用户/开发/隐私/发布文档。
- **完成标准**：自动检查通过；人工矩阵有真实证据；无法在本机完成的 10.15/Intel/正式公证明确列为外部发布门禁，不伪报完成。
- **Review gate**：`changes/langshot/reviews/release-qualification.md` + current pass receipt。

## Test Obligations

- **必须先从失败测试开始的行为**：协议解析/版本门禁、会话转换、坐标换算、动态宽度布局、位移/置信度、固定区域、tile 原子恢复、编辑历史/坐标、输出几何/格式、设置迁移、日志过滤。
- **必需的边界情况**：0/1 帧、最小选区、屏幕边缘、普通/Retina、纯色/重复纹理/动画、向上/向下/反转、固定顶/底/侧、锚点外、焦点丢失、二次 Esc、疑似到底、10 分钟、59,999/60,000/超限、坏 JSON/manifest、helper 退出、不可写路径、磁盘不足、剪贴板失败、缺签名凭据。
- **回归敏感区域**：AppKit/Quartz 坐标系、覆盖层层级捕获、协议 schema、manifest 原子性、静止掩码误判、60k 内存、Web 与 native edit schema、10.15 API 可用性、Universal bundle 结构和权限 bundle id。

## Execution Mode

- **可用方式与推荐**：DP-3 后运行匹配七个 waves 的 `ssf execution recommend`。
- **用户确认的模式**：待 DP-4 确认；未确认前不得实现。
- **推荐理由 / 项目事实**：18 项任务、7 个强依赖 waves、新原生模块、跨语言协议、系统权限和高风险图像算法；应按 recommendation receipt 选择。
- **非推荐选择的风险确认**：若用户选择非推荐方式，`ssf execution plan` 必须带 `--acknowledge-recommendation`。
- **执行计划命令**：在 DP-4 使用本契约的 wave ID、策略、任务及依赖生成，不允许静默改写。
- **允许的修订**：只允许保留或升级为 `sdd`；修订前重新 recommend，并清除旧 review receipts。
- **计划 revision / artifact hash**：待 DP-4 工具生成。

## Verification Dimensions

| 维度 | 状态 | 发现 |
|---|---|---|
| Completeness | Pass | 33 个 Requirement 均映射到任务和测试义务 |
| Correctness | Pass | 契约保留全部已确认边界；未扩大用户可见范围 |
| Coherence | Pass | waves 按 tasks 依赖排序，后续 wave 仅依赖通过 review 的前置 wave |

**总体结论**：契约可供 DP-3 审核；没有未映射需求或待定行为。

## Review Gates

- **强制审查点**：每个 wave 完成后生成 review report，并以实际 base/head SHA 写入 `ssf execution review`。
- **阻塞类别**：依赖 wave 无 current pass receipt；聚焦/全量测试失败；review 为 fail；artifact/contract hash 变化；发现未批准用户行为。
- **收口条件**：七个 wave 都有 current pass receipt，自动化与可用人工验证完成，delta specs 已发布，外部发布前置条件明确且未被伪报完成。

## Escalation Rules

- **回退到 `specifying`**：用户可见行为、范围、兼容承诺、权限、数据/隐私、60,000px/10 分钟边界或格式要求发生变化；WebP fallback 无法在 20MB 内实现且需改变产品承诺。
- **回退到 `bridging`**：规划不变但 waves、实现边界、测试义务、依赖或 review 时点需实质调整；契约与 artifacts hash 不一致。
- **不得继续实现**：DP-3/DP-4 未记录；当前 wave 不 eligible；依赖 review 缺失/失败；发现 bug 尚未走调查流程；测试失败；真实权限/OS/证书证据缺失却试图标记通过。

