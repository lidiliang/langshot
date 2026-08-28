# langShot

langShot 是一个面向 macOS 的 uTools 截图插件，同时支持普通选区截图和滚动长截图。截图、拼接和导出全部在本机完成。

## 当前能力

- 打开插件后直接进入智能框选，框选完成后再选择截图模式
- 简单截图（默认）、手动滚动、自动滚动三种模式
- 单显示器选区与 Retina 原始像素捕获
- 手动滚动、自动滚动锚点、向上/向下模式
- 滚动进度与操作面板紧贴选区，并自动避让屏幕边缘
- 自动重叠检测、固定顶/底区域抑制
- 60,000px 高度与 10 分钟保护
- `Esc` 暂停/二次丢弃、空格继续、`Cmd+Enter` 完成
- PNG 保存、结果预览、复制与访达定位
- 结果页支持拖拽箭头标注、点击定位文字标注和撤销
- 结果页支持按 `Enter` 快速复制，并显示可见快捷键提示
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

## 使用与快捷键

从 uTools 搜索结果打开“滚动长截图”后，langShot 会立即隐藏插件主页并进入鼠标框选：

1. 移动鼠标使用智能推荐区域，或拖拽自由框选；按 `Esc` 可取消。
2. 框选后仍可移动选区、拖动边框或控制点微调大小。
3. 在紧贴选区的工具栏选择“简单截图”“自动滚动”或“手动滚动”；默认是简单截图。
4. 简单截图会直接保存当前选区；滚动模式还可选择向下或向上，然后开始捕获。

截图完成后可在结果页继续编辑：

- 点击“箭头”，在图片上从起点拖到终点绘制开放式箭头。
- 点击“文字”，再点击图片中的位置，输入内容并按 `Enter` 确认；输入时按 `Esc` 取消。
- 使用默认“选择”工具拖动箭头或文字改变位置；选中箭头后可拖动两个端点调整方向和长度，双击文字可重新编辑内容。
- 点击“撤销”或按 `Cmd+Z` 撤回最近一次新增、移动、端点调整、文字修改或删除；选中标注后可按 `Delete` 删除。
- 点击“复制图片”、按结果页 `Enter` 或选择“在访达中显示”时，langShot 会先把标注按原图像素渲染到新的 PNG，再执行对应操作。

如需一按快捷键直接进入框选，可在 uTools 的“设置 → 全局快捷键”中，为现有的“滚动长截图 / 开始截图”功能配置快捷键。快捷键与搜索入口共用同一功能，因此不会额外产生一个同名搜索结果。若取消框选或需要授权，插件主页会重新显示。

## 安装非开发版本（UPXS）

不需要把插件提交到 uTools 应用市场，也可以通过 `.upxs` 离线安装包安装为本地正式插件。安装后的插件由 uTools 管理，重启 uTools 后仍然保留。

1. 按照上面的命令完成构建，确认已生成 `dist/langshot/plugin.json`。
2. 在 uTools 中搜索并打开“uTools 开发者工具”。
3. 导入现有项目，选择 `dist/langshot/plugin.json`，先在开发模式中完成一次截图验证。
4. 在开发者工具中点击“打包”，填写版本信息并选择保存位置，生成 `.upxs` 安装包。
5. 推荐通过 uTools 搜索框安装 `.upxs`：
   - 在访达中选中并复制 `.upxs` 文件。
   - 使用自己的快捷键呼出 uTools 搜索框，按 `Cmd+V` 把文件粘贴进去。
   - 在“匹配结果”中点击带绿色下载箭头图标的“安装插件应用”，然后按安全提示确认安装。不要选择“加入本地启动”或其他文件处理结果。
   - 也可以在访达中选中 `.upxs` 文件，长按鼠标右键呼出 uTools 超级面板，再选择“安装插件应用”。
6. 完全退出并重新打开 uTools，搜索 `langShot`，确认插件仍可启动。
7. 安装成功后，在 uTools 开发者工具中停止或移除 langShot 的开发项目，只保留已安装版本，避免搜索时同时出现开发版和安装版两个结果。

直接把安装包拖入 uTools 搜索框在当前版本中可能不会触发安装，请使用上面的复制粘贴或超级面板方式。

建议保留 `.upxs` 文件作为当前版本的离线安装包。后续更新时提升 `plugin/plugin.json` 中的版本号，重新构建、打包并安装新的 `.upxs` 即可覆盖升级。具体流程可参考 uTools 官方文档：[打包为离线安装包](https://www.u-tools.cn/docs/developer/basic/offline-plugin.html)和[如何离线安装插件应用](https://www.u-tools.cn/docs/guide/faq.html#如何离线安装-utools-插件应用)。

## 系统权限

首次截图需要在“系统设置 → 隐私与安全性”中授予 langShot Helper 屏幕录制权限；自动滚动还需要辅助功能权限。若在选区工具栏切换到自动滚动时发现尚未授权，langShot 会退出截图遮罩、重新显示插件主页并弹出逐步授权指引，不会静默失败。

从开发版本切换到 `.upxs` 安装版本后，由于原生 Helper 的安装路径发生变化，macOS 可能会再次请求权限，按插件内的授权指引重新开启即可。

## 项目文档

已确认需求见 `docs/product/requirements-baseline.md`，架构见 `docs/architecture.md`。
