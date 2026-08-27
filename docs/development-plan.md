# langShot 实施任务

## Delivery / Proof Map

| 能力 | 主要规格 | 实现区域 | 完成证据 |
|---|---|---|---|
| 权限、选区、Retina、覆盖层排除 | `capture-selection` | `native/Sources/Overlay`, `native/Sources/Capture` | Swift 单测 + Retina/普通屏人工截图记录 |
| 手动/自动会话、方向与结束保护 | `scroll-session` | `native/Sources/Session`, `native/Sources/Scroll` | 状态机单测 + 自动/手动集成记录 |
| 重叠、固定区域、动态宽度、60k 分块 | `stitching` | `native/Sources/Stitching`, `native/Sources/SessionStore` | 黄金图 + 60k 性能报告 |
| 编辑、撤销、裁剪、格式、保存和剪贴板 | `editor-output` | `plugin/src/editor`, `native/Sources/Export` | Web 单测 + 跨格式黄金导出 |
| uTools、IPC、隐私、构建和兼容矩阵 | `platform-quality` | `plugin`, `shared`, `scripts`, `tests/manual` | 契约测试 + 构建检查 + 六应用矩阵 |

## Milestone 1 — Core MVP

### Task 1: Bootstrap project and quality gates

- **Depends on:** none
- **Affected paths:** `package.json`, `plugin/`, `native/Package.swift`, `shared/`, `scripts/`, `.gitignore`
- **Outcome:** uTools 开发入口、TypeScript 测试环境和 Swift Package 可构建；目录约定、格式检查和一键验证命令固定。
- **Evidence:** `npm test`, `swift test --package-path native`, `npm run check`

### Task 2: Define and validate the cross-language protocol

- **Depends on:** 1
- **Affected paths:** `shared/protocol/`, `plugin/src/preload/protocol.ts`, `native/Sources/Protocol`, `tests/fixtures/protocol/`
- **Outcome:** v1 JSON Lines schema、请求/事件/错误模型和共享接受/拒绝 fixtures 完成；任一端拒绝坏行、未知主版本和非法路径标识。
- **Evidence:** `npm run test:protocol`, `swift test --package-path native --filter ProtocolTests`

### Task 3: Implement helper lifecycle and session reducer

- **Depends on:** 2
- **Affected paths:** `plugin/src/preload/helper-client.ts`, `native/Sources/LangShotHelper`, `native/Sources/Session`, `native/Tests/SessionTests`
- **Outcome:** 插件可启动单实例 helper、握手、超时和处理退出；纯 reducer 覆盖全部状态、命令门禁、首次/二次 Esc 和暂停原因。
- **Evidence:** `npm run test:helper-client`, `swift test --package-path native --filter SessionTests`

### Task 4: Implement display coordinates, permissions and AppKit selection overlay

- **Depends on:** 3
- **Affected paths:** `native/Sources/Platform`, `native/Sources/Overlay`, `native/Tests/CoordinateTests`, `plugin/src/screens/permission.*`
- **Outcome:** 屏幕录制/辅助功能按模式门禁；任意单屏选区、手柄、键盘微调、重选和边界限制可用；坐标统一落为原始像素。
- **Evidence:** `swift test --package-path native --filter CoordinateTests`, `tests/manual/selection-retina.md`

### Task 5: Implement CoreGraphics capture backend

- **Depends on:** 4
- **Affected paths:** `native/Sources/Capture`, `native/Tests/CaptureTests`, `tests/manual/overlay-exclusion.md`
- **Outcome:** 使用 below-overlay-window 兼容路径捕获无 langShot UI 的原始像素帧；权限和尺寸异常返回结构化错误。
- **Evidence:** `swift test --package-path native --filter CaptureTests`, `scripts/verify-golden-capture.sh`

### Task 6: Implement atomic tile session store and recovery

- **Depends on:** 2, 5
- **Affected paths:** `native/Sources/SessionStore`, `native/Tests/SessionStoreTests`, `shared/session-manifest.schema.json`
- **Outcome:** 无损 tile、校验、原子 manifest、配额、过期清理与重启恢复完成；坏清单不会覆盖原数据。
- **Evidence:** `swift test --package-path native --filter SessionStoreTests`

### Task 7: Implement overlap and static-region stitching engine

- **Depends on:** 5, 6
- **Affected paths:** `native/Sources/Stitching`, `native/Tests/StitchingTests`, `tests/fixtures/images/`
- **Outcome:** 向上/向下多带位移估计、置信度、固定顶/底/侧区域抑制、动态宽度横坐标画布和透明空白通过黄金图。
- **Evidence:** `swift test --package-path native --filter StitchingTests`, `scripts/verify-stitching-goldens.sh`

### Task 8: Implement manual and automatic scroll controllers

- **Depends on:** 3, 4, 5, 7
- **Affected paths:** `native/Sources/Scroll`, `native/Sources/Session`, `native/Tests/ScrollTests`
- **Outcome:** 手动位移驱动采样、自动锚点滚动、速度调整、焦点保护、方向锁定、疑似到底、10 分钟和 60,000px 限制完成。
- **Evidence:** `swift test --package-path native --filter ScrollTests`, `tests/manual/scroll-controller.md`

### Task 9: Build the capture UI and complete MVP integration

- **Depends on:** 3–8
- **Affected paths:** `plugin/plugin.json`, `plugin/preload.js`, `plugin/src/screens/capture.*`, `plugin/src/state/`, `plugin/src/styles/`
- **Outcome:** uTools 关键词进入、模式选择、权限引导、实时进度、暂停卡片、继续/完成/丢弃以及 PNG 保存/按需复制形成端到端 MVP。
- **Evidence:** `npm test`, `npm run build:plugin`, `tests/manual/mvp-e2e.md`

## Milestone 2 — Complete v1

### Task 10: Generate preview pyramid and viewport tile bridge

- **Depends on:** 6, 9
- **Affected paths:** `native/Sources/Preview`, `plugin/src/preload/session-files.ts`, `plugin/src/editor/tile-source.ts`
- **Outcome:** helper 生成多级预览块，preload 仅按会话和 tile ID 暴露数据，编辑器可平滑浏览 60,000px 图而不创建整图 canvas。
- **Evidence:** `swift test --package-path native --filter PreviewTests`, `npm run test:editor`

### Task 11: Implement non-destructive editor and history

- **Depends on:** 10
- **Affected paths:** `plugin/src/editor/model/`, `plugin/src/editor/tools/`, `plugin/src/editor/view/`, `shared/edit-document.schema.json`
- **Outcome:** 箭头、矩形、圆形、文字、画笔、马赛克、自由裁剪和原始像素坐标映射完成；撤销/重做及分支语义通过测试。
- **Evidence:** `npm run test:editor`, `npm run test:edit-fixtures`

### Task 12: Implement strip-based native rendering and formats

- **Depends on:** 7, 11
- **Affected paths:** `native/Sources/Export`, `native/Tests/ExportTests`, `native/Vendor/libwebp/`, `scripts/check-package-size.sh`
- **Outcome:** CoreGraphics 流式重放编辑文档，输出 PNG/JPG/WebP；透明合成、质量档位和 60k 导出正确，WebP fallback 不突破包体门禁。
- **Evidence:** `swift test --package-path native --filter ExportTests`, `scripts/verify-export-goldens.sh`, `scripts/check-package-size.sh`

### Task 13: Complete destinations, clipboard and persistent settings

- **Depends on:** 9, 12
- **Affected paths:** `plugin/src/settings/`, `plugin/src/export/`, `plugin/src/preload/storage.ts`
- **Outcome:** 桌面/自定义路径、无冲突命名、失败重试、默认关闭的自动复制、超大图提示和设置迁移完成。
- **Evidence:** `npm run test:settings`, `npm run test:export-ui`, `tests/manual/output-failures.md`

### Task 14: Add privacy-safe diagnostics and recovery UX

- **Depends on:** 3, 6, 9
- **Affected paths:** `native/Sources/Diagnostics`, `plugin/src/diagnostics/`, `scripts/check-log-privacy.sh`
- **Outcome:** 日志只记录允许元数据；helper 崩溃、坏清单、编码/路径/剪贴板失败均提供恢复或安全丢弃；24 小时清理策略可配置执行。
- **Evidence:** `npm run test:recovery`, `swift test --package-path native --filter DiagnosticsTests`, `scripts/check-log-privacy.sh`

### Task 15: Build Universal, packaging, signing and notarization paths

- **Depends on:** 1, 9, 12, 14
- **Affected paths:** `scripts/build-native.sh`, `scripts/package-plugin.sh`, `scripts/sign-and-notarize.sh`, `docs/release.md`
- **Outcome:** 无凭据生成明确的未签名开发包；有凭据时可签名、公证、staple；产物验证双架构、10.15 deployment target 和小于 20MB。
- **Evidence:** `npm run package:dev`, `scripts/verify-bundle.sh`; 正式凭据可用后执行 `npm run package:release`

### Task 16: Run automated performance and correctness qualification

- **Depends on:** 7, 10, 12, 15
- **Affected paths:** `native/Tests/PerformanceTests`, `tests/performance/`, `scripts/benchmark.sh`
- **Outcome:** 1440×60,000 基准报告包含帧率、CPU、RSS、磁盘和编码时间；内存硬门槛和像素/尺寸校验通过。
- **Evidence:** `scripts/benchmark.sh --width 1440 --height 60000 --report tests/performance/latest.json`

### Task 17: Complete application and OS compatibility matrix

- **Depends on:** 9, 13, 15
- **Affected paths:** `tests/manual/compatibility-matrix.md`, `tests/manual/permissions.md`
- **Outcome:** Chrome、Safari、微信、飞书、VS Code、预览记录版本、手动/自动、上下方向、固定区域和已知限制；至少覆盖现代 macOS，10.15/Intel 标记实际验证证据或明确外部设备门禁。
- **Evidence:** completed `tests/manual/compatibility-matrix.md` with linked artifacts

### Task 18: Final documentation and release readiness

- **Depends on:** 13–17
- **Affected paths:** `README.md`, `docs/user-guide.md`, `docs/development.md`, `docs/privacy.md`, `docs/release.md`
- **Outcome:** 安装、授权、使用、恢复、隐私、构建和发布说明与实际行为一致；所有规格映射到通过证据或明确的外部发布前置条件。
- **Evidence:** `npm run check`, `ssf validate changes/langshot`, release checklist review
