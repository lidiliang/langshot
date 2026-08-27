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

## 开发

要求 macOS、Node.js 18+ 和 Swift 5.9+。

```bash
npm test
swift test --package-path native
npm run build:native
npm run package:dev
```

生成的 uTools 开发插件位于 `dist/langshot`。在 uTools 开发者工具中选择该目录的 `plugin.json` 即可加载。

首次截图需要在“系统设置 → 隐私与安全性”中授予 langShot Helper 屏幕录制权限；自动滚动还需要辅助功能权限。

已确认需求见 `docs/product/requirements-baseline.md`，架构见 `docs/architecture.md`。

