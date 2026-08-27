# langShot

langShot 是一个面向 macOS 的 uTools 滚动长截图插件。截图、拼接和导出全部在本机完成。

## 当前能力

- 单显示器选区与 Retina 原始像素捕获
- 手动滚动、自动滚动锚点、向上/向下模式
- 自动重叠检测、固定顶/底区域抑制
- 60,000px 高度与 10 分钟保护
- `Esc` 暂停/二次丢弃、空格继续、`Cmd+Enter` 完成
- PNG 保存、结果预览、复制与访达定位
- arm64/x86_64 Universal helper 开发包

## 技术栈

- **插件界面**：HTML5、CSS3、原生 JavaScript，无前端框架和线上运行时依赖。
- **uTools 集成**：uTools 插件 API、Electron preload、Node.js CommonJS，通过受控的 preload API 调用剪贴板、文件定位和窗口能力。
- **macOS 原生能力**：Swift 5.9、Swift Package Manager、AppKit、CoreGraphics、ApplicationServices、ImageIO 和 CoreServices。
- **进程通信**：插件通过 Node.js 子进程启动 `langshot-helper`，使用基于标准输入/输出的版本化 JSON Lines 协议通信。
- **截图与拼接**：按屏幕原始像素捕获，使用重叠区域匹配、位移历史和固定边缘抑制完成本地无损拼接。
- **测试与构建**：JavaScript 使用 Node.js `node:test`，Swift 使用 Swift Testing；Shell 脚本分别构建 arm64 和 x86_64 release 二进制，再通过 `lipo` 合并为 Universal Helper。

运行平台为 macOS 10.15 及以上；开发环境要求 Node.js 18+ 和 Swift 5.9+。

## 开发与构建

安装依赖后，在项目根目录执行：

```bash
npm run check
npm run build:native
npm run package:dev
```

构建会生成 `dist/langshot`，其中包含插件页面和 arm64/x86_64 Universal 原生 Helper。在 uTools 开发者工具中选择 `dist/langshot/plugin.json` 即可加载开发版本。

## 安装非开发版本（UPXS）

不需要把插件提交到 uTools 应用市场，也可以通过 `.upxs` 离线安装包安装为本地正式插件。安装后的插件由 uTools 管理，重启 uTools 后仍然保留。

1. 按照上面的命令完成构建，确认已生成 `dist/langshot/plugin.json`。
2. 在 uTools 中搜索并打开“uTools 开发者工具”。
3. 导入现有项目，选择 `dist/langshot/plugin.json`，先在开发模式中完成一次截图验证。
4. 在开发者工具中点击“打包”，填写版本信息并选择保存位置，生成 `.upxs` 安装包。
5. 使用以下任一官方方式安装 `.upxs`：
   - 在访达中复制 `.upxs` 文件，使用自己的快捷键呼出 uTools 搜索框，按 `Cmd+V` 粘贴文件，然后选择“安装插件应用”。
   - 在访达中选中 `.upxs` 文件，长按鼠标右键呼出 uTools 超级面板，然后选择“安装插件应用”。
6. 完全退出并重新打开 uTools，搜索 `langShot`，确认插件仍可启动。
7. 安装成功后，在 uTools 开发者工具中停止或移除 langShot 的开发项目，只保留已安装版本，避免搜索时同时出现开发版和安装版两个结果。

直接把安装包拖入 uTools 搜索框在当前版本中可能不会触发安装，请使用上面的复制粘贴或超级面板方式。

建议保留 `.upxs` 文件作为当前版本的离线安装包。后续更新时提升 `plugin/plugin.json` 中的版本号，重新构建、打包并安装新的 `.upxs` 即可覆盖升级。具体流程可参考 uTools 官方文档：[打包为离线安装包](https://www.u-tools.cn/docs/developer/basic/offline-plugin.html)和[如何离线安装插件应用](https://www.u-tools.cn/docs/guide/faq.html#如何离线安装-utools-插件应用)。

## 系统权限

首次截图需要在“系统设置 → 隐私与安全性”中授予 langShot Helper 屏幕录制权限；自动滚动还需要辅助功能权限。

从开发版本切换到 `.upxs` 安装版本后，由于原生 Helper 的安装路径发生变化，macOS 可能会再次请求权限，按插件内的授权指引重新开启即可。

## 项目文档

已确认需求见 `docs/product/requirements-baseline.md`，架构见 `docs/architecture.md`。
