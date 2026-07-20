# 实现记录

本仓库维护下列源码补丁：

| 补丁 | 作用 | 保留理由 |
| --- | --- | --- |
| `100-build-darwin-app-name.patch` | macOS 应用包名读取 `product.nameShort` | VSCodemo 品牌适配 |
| `208-build-fromlocalnormal-no-npm.patch` | 非 esbuild 内置扩展打包时跳过不必要的 npm 依赖解析 | 避免 Windows Node.js 22 下 `@vscodium/vsce` 的 `checkNPM()` 偶发 `spawn UNKNOWN`；hunk 同时兼容干净 VS Code 与 VSCodium 后置基线 |
| `216-build-product-company-name.patch` | Electron 元数据读取 product 公司名与版权 | VSCodemo 品牌适配 |
| `217-build-win32-inno-publisher.patch` | Windows Inno 安装器读取 product 发布者信息，并把预发布 SemVer 映射为纯数字文件版本 | VSCodemo 品牌适配；避免 Inno 拒绝带连字符的 `VersionInfoVersion` |
| `218-build-limit-minify-concurrency.patch` | 允许通过 `VSCODE_MINIFY_CONCURRENCY` 限制 minify 阶段的 esbuild 并发 | 防止 Windows hosted runner 在 `vscode-min-prepack` 阶段耗尽内存；不设置全局 `GOMEMLIMIT`，避免拖慢 tsgo |
| `219-feature-ribbon-part.patch` | 新增全宽 Ribbon Part、折叠交互、内置 File/View/Help 标签、按菜单分隔线生成的命名功能组、`contributes.ribbon` 与回归测试；按钮支持全高、半高、三分之一高及纵向、纯图标、横向图文布局，可组成一至三行；全高图标占满标题外的可用高度，并通过锚定在 `.monaco-workbench .part.ribbon` 与 `.monaco-workbench .ribbon-overlay` 的 (0,5,0) 特异性规则同时压过 `.codicon[class*='codicon-']` (0,2,0) 简写与 `.monaco-workbench .part .codicon` (0,4,0) 缩放规则，让响应式字号真正生效，紧凑图文垂直居中；支持 Office 风格分割下拉按钮、单体下拉按钮、带代表图标且纵向排列标题与箭头的折叠组按钮、同一 Context View 内带返回导航的递归 Ribbon 菜单项，以及在无脚本 sandbox iframe 中显示 HTML/CSS 静态内容；展开内容区高 98px；宽度不足时按声明逐级切换按钮尺寸/图文样式、将相近功能合并为下拉菜单，再从右向左逐组折叠，最后通过按边界显示的悬浮箭头无滚动条滚动 | Ribbon 核心功能 |

### `219-feature-ribbon-part.patch` 维护记录

- 2026-07-19：彻底修复全高纵向按钮（`ribbon-item-full` + `ribbon-item-vertical`）的 Codicon 图标过小问题。前两次修复用 `.ribbon-root .ribbon-item-icon.codicon`（特异性 0,3,0）尝试覆盖 Codicon 固定 16px 字号，但打包后的 `workbench.desktop.main.css` 里存在一条更狠的上游规则 `.monaco-workbench .part .codicon[class*='codicon-'] { font-size: calc(var(--vscode-workbench-font-size) * 1.230769) }`（特异性 0,4,0），它把字号锁回 13px；规则在 `src/vs` 源码中搜不到，疑似由 esbuild postprocess 或运行时 zoom 处理注入，但只要它存在于打包产物中就会压制 0,3,0 覆盖。修复方案是把覆盖选择器锚到 `.monaco-workbench .part.ribbon .ribbon-root .ribbon-item-icon.codicon` 与 `.monaco-workbench .ribbon-overlay .ribbon-item-icon.codicon`（特异性 0,5,0，针对折叠浮层用 `.monaco-workbench` 前缀而非 `.part`，因为 ContextView 容器位于 Workbench 直接子级而非 Part 内），同时给 `ribbon-group-dropdown-icon` 提供等价覆盖。完整 workbench CSS 环境下，icon 实际 `font-size` 从 13px 提升到 55px，图标高度占按钮高度从约 18% 提升到约 74%。
- 2026-07-19：降低内置 Ribbon tab 优先级。`BUILTIN_TABS` 的 `order` 从 `10 / 20 / 100` 调至 `1000 / 2000 / 3000`，扩展声明的 tab（默认 `order=0`）会自然排在内置 `File / View / Help` 之前；同步把 `ensureActiveTab` 的 fallback 从硬编码 `File` 改为排序后第一个 tab，使启动激活的 tab 与视觉首位一致。内置 tab 当前仅作为 Ribbon 实现的测试占位，正式版将移除。
- 2026-07-19：内置 Ribbon tab 与内置菜单分组标题按当前界面语言显示；中文语言环境下 `File / View / Help` 与对应分组标题显示中文，非中文语言环境保留 VS Code 常规本地化结果。
- 2026-07-19：去掉 `localizeRibbonLabel` 包装函数，改为模块顶层 `isZhHansLocale` 常量配合 `isZhHansLocale ? "中文" : localize('key', "Default")` 内联三元。原因：上游 `build/lib/nls-analysis.ts` 的 `parseLocalizeKeyOrValue` 会对源码里每个 `localize(...)` 的第一参数做 `eval`，第一参数必须是字面量；而包装函数里的 `localize(key, defaultValue)` 第一参数是变量 `key`，eval 时抛 `ReferenceError: key is not defined`，导致发行 CI 在 `vscode-min-prepack` 阶段失败。本地 `prepare.sh` 不跑 min-prepack，所以 CI 才暴露。
- 2026-07-20：修复占用 ribbon 面板全高的两类按钮（「上 icon + 下 标题」= `ribbon-item-full` + `ribbon-item-vertical`，以及「icon + 标题 + 下拉按钮」= `ribbon-dropdown-item` 系列，含 splitButton 主按钮/trigger 与 dropdown-single footer）的三个问题。① 图标过大：把 `.ribbon-item-vertical .ribbon-item-icon`、`.ribbon-dropdown-primary .ribbon-item-icon`、`.ribbon-dropdown-single > .ribbon-item-icon` 的 `--ribbon-icon-size` 由 `calc(var(--ribbon-item-full-height) - 19px / 22px)`（实际 52–55px）统一改为固定 40px，并去掉 `flex: 1 1 0` 拉伸，改为 `flex: 0 0 auto` 固定 40×40 盒子。② 内容贴底：原 vertical 按钮因 icon 拉伸把 label 顶到面板底、dropdown 因 primary `flex: 1 1 0` 把 trigger 推到底；改为 `.ribbon-item-vertical` 加 `justify-content: flex-start`、`.ribbon-dropdown-item` 加 `justify-content: flex-start`、primary/single 改 `flex: 0 0 auto`，让 icon + 标题从顶部开始排列、底部留白。③ chevron-down 水平对齐：因不同按钮标题 1 行/2 行混排，trigger/footer 默认 `flex-direction: row` 让 chevron 垂直位置参差；新增 `watchRibbonLabelLines()` 私有方法，在 trigger/footer 渲染后用 `ResizeObserver` + window `resize` 监听 `.ribbon-item-label` 的 `offsetHeight`，超过单行行高（>15px）即判定为 2 行，给容器 toggle `ribbon-label-single` / `ribbon-label-double` class：`.ribbon-label-single` 让 chevron 排在标题下方（`flex-direction: column`），`.ribbon-label-double` 保持标题右侧（`flex-direction: row; align-items: flex-end`），两种情况下 chevron 都落在按钮底部附近，保证整排水平对齐。`createDropdownTrigger` 同步新增 `store: DisposableStore` 参数以托管监听器生命周期。

## Ribbon 内部 API 登记

| 内部 API / 耦合点 | 上游位置 | 用途 |
| --- | --- | --- |
| `Part` / `SerializableGrid` | `src/vs/workbench/browser/part.ts`、`browser/layout.ts` | 注册全宽 Ribbon Part 并参与 Workbench 布局 |
| `ExtensionsRegistry` | `services/extensions/common/extensionsRegistry.ts` | 注册并校验 `contributes.ribbon` |
| `IContextViewService` | `platform/contextview/browser/contextView.ts` | 显示 Ribbon 菜单弹层与折叠状态临时覆盖层；递归菜单在同一 Context View 内导航 |
| `IPartsSplash` | `workbench/contrib/splash/browser/partsSplash.ts` | 在启动 Splash 中保留 Ribbon 高度 |

修改以上任一补丁时，必须同时验证干净 VS Code 基线和 VSCodium 官方补丁后的发行基线。
