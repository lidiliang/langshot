# Platform and Quality Specification

## ADDED Requirements

### Requirement: uTools integration

插件 SHALL 提供符合 uTools API v2 的 manifest、preload 和入口，使用 uTools 平台快捷键机制，并 MUST 管理原生辅助程序的单实例生命周期和版本兼容。

#### Scenario: Helper protocol version mismatches

- **WHEN** 插件启动的辅助程序报告不兼容协议版本
- **THEN** 插件停止截图入口并提示重新安装匹配版本，不向其发送会话命令

### Requirement: Versioned local IPC

插件与辅助程序 MUST 使用版本化、带请求 ID 的本地消息协议；未知消息或字段 SHALL 返回结构化错误且不得执行未确认的外部路径或命令。

#### Scenario: Malformed message is received

- **WHEN** 任一端收到无法解析或不符合 schema 的消息
- **THEN** 记录不含截图内容的诊断信息并返回协议错误，进程保持可用

### Requirement: Universal and minimum-version build

辅助程序 MUST 可构建为同时包含 `arm64` 与 `x86_64` 的 Universal Binary，部署目标为 macOS 10.15；构建流程 SHALL 提供架构和最低版本验证。

#### Scenario: Release artifact is inspected

- **WHEN** 构建脚本完成 Universal 产物
- **THEN** `lipo` 报告两种架构，Mach-O 最低系统版本检查不高于 10.15

### Requirement: Local-only privacy

运行时代码 MUST 不上传截图、帧、标注或使用数据；日志 SHALL 只包含时间、版本、状态、尺寸、耗时、置信度和错误码等元数据。

#### Scenario: Diagnostic bundle is produced

- **WHEN** 用户导出调试日志
- **THEN** 日志不包含图像文件、图像编码、OCR 文本或目标应用可见内容

### Requirement: Performance baseline

在当前 Apple Silicon 开发机、约 1440px 宽选区的基准场景中，采样目标 SHALL 达到至少 10 帧/秒，采集中 CPU 目标 SHALL 低于 30%，正常场景峰值内存 MUST 低于 500MB；任何降频 MUST 保持结果正确并反映在状态中。

#### Scenario: Maximum-height benchmark runs

- **WHEN** 60,000px 合成场景执行基准测试
- **THEN** 报告帧率、CPU、峰值内存、编码时长和输出校验，内存不超过硬限制

### Requirement: Compatibility matrix

发布验收 MUST 覆盖 Chrome、Safari、微信、飞书、VS Code 和 macOS 预览的手动/自动、向上/向下及典型固定区域场景；矩阵外应用 SHALL 标记为尽力兼容。

#### Scenario: Release candidate is evaluated

- **WHEN** 准备发布完整 v1
- **THEN** 每个正式验收应用均有版本、场景、结果和已知限制记录，不以单一浏览器通过替代矩阵

### Requirement: Recoverable errors and cleanup

权限拒绝、辅助程序退出、低置信度、路径写入失败和编码失败 MUST 产生明确错误并保留可恢复数据；成功、明确丢弃或超过保留期后 SHALL 清理临时帧。

#### Scenario: Helper crashes during capture

- **WHEN** 插件检测到辅助程序异常退出
- **THEN** 插件显示会话恢复或安全丢弃选项，并避免把临时目录误报为完成图片

### Requirement: Signed and unsigned delivery paths

项目 SHALL 支持未签名开发构建，并提供可在注入 Apple Developer Team、Developer ID 和公证凭据后执行的签名、公证与验证脚本。

#### Scenario: Credentials are absent

- **WHEN** 开发者执行普通开发构建且未配置发布凭据
- **THEN** 构建仍成功生成明确标记的未签名产物，不尝试上传公证服务
