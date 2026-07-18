# 实现记录

`only-ribbon` 分支只保留下列源码补丁：

| 补丁 | 作用 | 保留理由 |
| --- | --- | --- |
| `100-build-darwin-app-name.patch` | macOS 应用包名读取 `product.nameShort` | VSCodemo 品牌适配 |
| `208-build-fromlocalnormal-no-npm.patch` | 非 esbuild 内置扩展打包时跳过不必要的 npm 依赖解析 | 避免 Windows Node.js 22 下 `@vscodium/vsce` 的 `checkNPM()` 偶发 `spawn UNKNOWN`；hunk 同时兼容干净 VS Code 与 VSCodium 后置基线 |
| `216-build-product-company-name.patch` | Electron 元数据读取 product 公司名与版权 | VSCodemo 品牌适配 |
| `217-build-win32-inno-publisher.patch` | Windows Inno 安装器读取 product 发布者信息，并把预发布 SemVer 映射为纯数字文件版本 | VSCodemo 品牌适配；避免 Inno 拒绝带连字符的 `VersionInfoVersion` |
| `218-build-limit-minify-concurrency.patch` | 允许通过 `VSCODE_MINIFY_CONCURRENCY` 限制 minify 阶段的 esbuild 并发 | 防止 Windows hosted runner 在 `vscode-min-prepack` 阶段耗尽内存；不设置全局 `GOMEMLIMIT`，避免拖慢 tsgo |
| `219-feature-ribbon-part.patch` | 新增全宽 Ribbon Part、折叠交互、内置 File/View/Help 标签、按菜单分隔线生成的命名功能组、`contributes.ribbon` 与回归测试；按钮支持全高、半高、三分之一高及纵向、纯图标、横向图文布局，可组成一至三行；展开内容区高 98px；宽度不足时将全部功能组折叠为下拉菜单，全部折叠后通过按边界显示的悬浮箭头无滚动条滚动 | 本分支唯一功能差异 |

## Ribbon 内部 API 登记

| 内部 API / 耦合点 | 上游位置 | 用途 |
| --- | --- | --- |
| `Part` / `SerializableGrid` | `src/vs/workbench/browser/part.ts`、`browser/layout.ts` | 注册全宽 Ribbon Part 并参与 Workbench 布局 |
| `ExtensionsRegistry` | `services/extensions/common/extensionsRegistry.ts` | 注册并校验 `contributes.ribbon` |
| `IContextViewService` | `platform/contextview/browser/contextView.ts` | 在折叠状态显示临时覆盖层 |
| `IPartsSplash` | `workbench/contrib/splash/browser/partsSplash.ts` | 在启动 Splash 中保留 Ribbon 高度 |

修改以上任一补丁时，必须同时验证干净 VS Code 基线和 VSCodium 官方补丁后的发行基线。
