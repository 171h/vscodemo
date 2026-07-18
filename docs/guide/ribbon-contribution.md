# 扩展贡献 Ribbon

VSCodemo 在 Banner 下方提供横跨窗口的 Ribbon Part。Ribbon 默认展开，可记忆
折叠状态和最后选择的标签；折叠后点击标签会临时覆盖编辑区顶部，执行命令、点击
外部或按 `Escape` 后关闭。

当可用宽度不足时，Ribbon 会依次尝试按钮声明的紧凑布局、把相近功能合并为下拉
菜单、从右向左逐个折叠功能组；全部功能组折叠后仍然溢出时，内容区两端会按需显示
悬浮滚动按钮。原生横向滚动条始终隐藏，滚动到最左或最右边界时，对应方向的按钮也
会隐藏。

Activity Bar、任务列表上下文菜单和顶部 `File` / `View` / `Help` 菜单不会因 Ribbon
而失效。扩展应复用已有命令，在保留原入口的同时，将高频功能声明到
`contributes.ribbon`，不需要新增 Extension Host API 或重复实现命令。

::: warning 兼容范围
`contributes.ribbon` 是 VSCodemo 提供的自定义扩展点，不是 VS Code 的标准
contribution point。扩展仍可在普通 VS Code 中运行，但 Ribbon 入口只会在支持该
扩展点的 VSCodemo 中显示。
:::

## 最小完整示例

Ribbon 按钮必须引用一个已经登记在 `contributes.commands` 中的命令。推荐同时使用
`package.nls.json` 和 `package.nls.zh.json` 管理标签、分组和按钮文案。

```jsonc
// package.json
{
  "contributes": {
    "commands": [
      {
        "command": "publisher.extension.openConverter",
        "title": "%commands.openConverter%",
        "category": "Engineering"
      }
    ],
    "ribbon": {
      "tabs": [
        {
          "id": "publisher.extension.ribbon.tools",
          "title": "%ribbon.tools.title%",
          "order": 40,
          "default": false,
          "when": "workspaceFolderCount > 0",
          "groups": [
            {
              "id": "conversion",
              "title": "%ribbon.tools.conversion%",
              "order": 10,
              "items": [
                {
                  "command": "publisher.extension.openConverter",
                  "title": "%ribbon.openConverter%",
                  "icon": "$(symbol-numeric)",
                  "size": "half",
                  "style": "iconAndLabel",
                  "order": 10,
                  "when": "resourceScheme == file",
                  "arguments": [{ "source": "ribbon" }]
                }
              ]
            }
          ]
        }
      ]
    }
  }
}
```

```jsonc
// package.nls.json
{
  "commands.openConverter": "Open Converter",
  "ribbon.tools.title": "Tools",
  "ribbon.tools.conversion": "Conversion",
  "ribbon.openConverter": "Unit Converter"
}
```

```jsonc
// package.nls.zh.json
{
  "commands.openConverter": "打开换算器",
  "ribbon.tools.title": "工具",
  "ribbon.tools.conversion": "换算",
  "ribbon.openConverter": "单位换算"
}
```

按钮执行时，`arguments` 数组会展开为命令参数。因此上例等价于：

```ts
vscode.commands.executeCommand(
  'publisher.extension.openConverter',
  { source: 'ribbon' },
)
```

不需要区分入口来源时可以省略 `arguments`。

## 声明层级

```text
contributes.ribbon
└── tabs[]                  标签
    └── groups[]            标签内的功能组
        └── items[]         命令按钮、分割下拉按钮或单体下拉按钮
```

### 标签 `tabs[]`

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `id` | 是 | 全局唯一 ID，推荐使用 `<publisher>.<extension>.ribbon.<name>` |
| `title` | 是 | 标签文案，推荐使用 `%nls.key%` |
| `groups` | 是 | 至少包含一个分组 |
| `order` | 否 | 数字越小越靠前，缺省值为 `0` |
| `default` | 否 | 没有已保存选择时是否作为初始标签，缺省为 `false` |
| `when` | 否 | 控制整个标签是否显示的 Context Key 表达式 |

`id` 不能使用以下 Workbench 内置标签 ID：

- `workbench.ribbon.file`
- `workbench.ribbon.view`
- `workbench.ribbon.help`

不同扩展之间的标签 `id` 也不能重复。同一扩展通常只设置一个
`default: true`；如果多个可见标签都声明为默认项，排序后最靠前的标签生效。用户
选择过标签后，以用户保存的选择为准。

### 分组 `groups[]`

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `id` | 是 | 在当前标签内唯一，推荐使用稳定的语义名称 |
| `title` | 是 | 显示在按钮下方的分组文案 |
| `items` | 是 | 至少包含一个按钮 |
| `order` | 否 | 数字越小越靠前，缺省值为 `0` |
| `when` | 否 | 控制整个分组是否显示的 Context Key 表达式 |

### 按钮 `items[]`

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `type` | 条件必填 | 普通按钮可省略并缺省为 `button`；`splitButton`、`dropdown` 必须显式填写 |
| `command` | 条件必填 | `button`、`splitButton` 必填；`contributes.commands` 中已注册的命令 ID |
| `title` | 是 | 按钮文案和无障碍标签；`icon` 样式下不显示文案 |
| `icon` | 是 | Codicon、扩展相对资源路径或深浅主题资源对象 |
| `menu` | 条件必填 | `splitButton`、`dropdown` 的菜单内容，可包含 `items` 和/或 `custom` |
| `size` | 否 | `full`、`half` 或 `third`，缺省为 `full` |
| `style` | 否 | 紧凑按钮使用 `icon` 或 `iconAndLabel`，缺省为 `iconAndLabel` |
| `responsive` | 否 | 宽度不足时依次尝试的 `{ size, style? }` 布局数组 |
| `responsiveMenu` | 否 | 将相近按钮动态合并为下拉菜单的 `{ id, title, icon }` 声明 |
| `order` | 否 | 数字越小越靠前，缺省值为 `0` |
| `when` | 否 | 控制按钮是否显示的 Context Key 表达式 |
| `arguments` | 否 | 按顺序传给命令的参数数组 |

`icon` 支持以下三种形式：

```jsonc
// Codicon
"icon": "$(symbol-ruler)"

// 相对扩展根目录的资源路径；不要相对于 package.json 当前字段猜测其他基准
"icon": "./src/node-vscode/assets/scaffold.svg"

// 深色与浅色主题分别提供资源
"icon": {
  "light": "./assets/converter-light.svg",
  "dark": "./assets/converter-dark.svg"
}
```

资源图标路径相对于扩展根目录解析。打包扩展时必须确认这些文件未被
`.vscodeignore` 排除，并在实际安装包中存在。

### 按钮尺寸、行数与样式

Ribbon 的 74px 按钮区按 6 个逻辑轨道布局。按钮尺寸决定占用轨道数，也就决定了
一个功能组内可以形成的行数：

| `size` | 按钮高度 | 同尺寸按钮行数 | 显示方式 |
| --- | --- | --- | --- |
| `full` | 面板按钮区全高 | 1 行 | 固定为上方图标、下方标题 |
| `half` | 面板按钮区的 1/2 | 2 行 | `icon` 或左侧图标、右侧标题 |
| `third` | 面板按钮区的 1/3 | 3 行 | `icon` 或左侧图标、右侧标题 |

同一功能组可以混合三种尺寸。按钮仍按 `order`、`command` 排序并从上到下填充；
当前列剩余高度容纳不下下一个按钮时，布局会自动开始新的一列。

紧凑按钮的 `style` 支持：

- `icon`：只显示图标，`title` 仍作为无障碍标签。
- `iconAndLabel`：显示左侧图标和右侧标题，也是紧凑按钮的缺省样式。

`full` 按钮会忽略 `style` 并始终保持上图标、下标题。省略 `size` 的旧贡献仍按
`full` 渲染，因此无需迁移。

### 响应式降级链

`responsive` 按数组顺序声明按钮在宽度不足时可采用的形态。Ribbon 不会自行决定
扩展命令是否适合隐藏标题；只有扩展明确声明后才会降级。例如：

```jsonc
{
  "command": "publisher.extension.save",
  "title": "保存",
  "icon": "$(save)",
  "size": "full",
  "responsive": [
    { "size": "half" },
    { "size": "third" },
    { "size": "third", "style": "icon" }
  ]
}
```

这会依次形成“上图标、下标题”的全高按钮、“左图标、右标题”的半高和三分之一高
按钮，最后才变成纯图标。`style: "icon"` 应只用于保存、打印、撤销、查找等用户能
稳定识别的通用图标。内置菜单按钮会自动尝试全高、半高和三分之一高布局，但同样只
对这类通用命令启用纯图标形态。

多个相近按钮使用相同的 `responsiveMenu.id` 时，它们会在按钮布局无法继续压缩后
合并为一个下拉菜单。相同 `id` 的 `title` 和 `icon` 应保持一致：

```jsonc
{
  "command": "publisher.extension.cut",
  "title": "剪切",
  "icon": "$(cut)",
  "responsiveMenu": { "id": "editing", "title": "编辑", "icon": "$(edit)" }
}
```

同组的复制、粘贴按钮也声明同一个 `editing` 即可。若合并后仍放不下，Ribbon 才会
从右向左逐个把整个功能组折叠到组下拉菜单；再无可折叠空间时才显示滚动箭头。未声明
`responsive` 或 `responsiveMenu` 的旧贡献保持原布局，只参与最后的整组折叠。

## 下拉菜单组件

`items[]` 通过 `type` 声明三种组件：

- `button`：原有命令按钮，点击后执行 `command`。
- `splitButton`：Office 风格分割按钮。上方图标区域执行 `command`；下方“标题 + 箭头”
  区域只展开 `menu`。
- `dropdown`：Office 风格单体下拉按钮。图标、标题和箭头属于同一个按钮，点击只展开
  `menu`，不执行命令，因此不填写 `command`。

两种下拉组件固定使用全高纵向布局，`size`、`style` 只影响普通 `button`。示例：

```jsonc
{
  "type": "splitButton",
  "command": "publisher.extension.runDefault",
  "title": "运行",
  "icon": "$(run)",
  "menu": {
    "items": [
      {
        "command": "publisher.extension.runFast",
        "title": "快速运行",
        "icon": "$(zap)",
        "size": "half"
      },
      {
        "type": "dropdown",
        "title": "更多模式",
        "icon": "$(list-selection)",
        "menu": {
          "items": [
            {
              "command": "publisher.extension.runSafe",
              "title": "安全模式",
              "icon": "$(shield)"
            }
          ]
        }
      }
    ]
  }
}
```

菜单的 `items` 使用与 Ribbon 面板相同的 item 格式，因此支持普通按钮、分割下拉按钮、
单体下拉按钮、图标、尺寸、样式、`when`、`arguments` 和命令可用状态。菜单可以继续
嵌套；进入下一级时仍复用当前弹层，并显示“返回”按钮回到上一级，不会替换 Context
View 或丢失锚点。功能组因宽度不足折叠时，也会保留这些组件，而不是降级为仅命令列表。

### 自定义 HTML 与 CSS

`menu.custom` 在无脚本权限的 `iframe sandbox=""` 中渲染，用于说明、图例、预览等
静态内容。CSP 同时禁止脚本和网络连接；HTML、CSS 均为字符串，弹层尺寸可在限定范围
内配置：

```jsonc
{
  "type": "dropdown",
  "title": "颜色说明",
  "icon": "$(symbol-color)",
  "menu": {
    "custom": {
      "width": 320,
      "height": 180,
      "html": "<div class='swatch red'>红色</div><div class='swatch blue'>蓝色</div>",
      "css": "body { display: flex; gap: 8px; padding: 12px } .swatch { min-width: 72px }"
    }
  }
}
```

自定义内容不提供 `javascript`、`commands` 或宿主命令桥；内联脚本和事件处理器也会
被 CSP 阻止。需要交互或执行命令时应使用声明式 `menu.items`。`menu.items` 与
`menu.custom` 可以同时存在，此时先显示可交互的 Ribbon 组件，再显示静态自定义区域。

## `when` 与命令可用状态

标签、分组和按钮上的 `when` 决定元素是否可见，语法与 VS Code 的 Context Key
表达式一致。命令在 `contributes.commands` 中配置的 `enablement` 会形成命令
precondition，Ribbon 会据此同步按钮的可用状态：

- `when` 为 `false`：元素不显示。
- 命令 precondition 为 `false`：按钮仍显示，但处于禁用状态；对于 `splitButton`，仅上方命令区禁用，下方菜单区仍可展开。

上下文变化后 Ribbon 会自动刷新。禁用或卸载扩展后，对应标签和按钮也会自动移除。

## 与 Activity Bar 双入口配合

Activity Bar 用于承载视图容器，Ribbon 用于提供跨工作区始终易发现的高频命令入口。
同一功能应复用同一个命令 ID，不要为 Ribbon 复制业务命令或维护第二套打开逻辑：

```text
Activity Bar 中的功能按钮 ─┐
                            ├── 同一个 contributes.commands 命令
Ribbon 按钮 ────────────────┘
```

`ext-engineer` 采用强制双入口规范：凡是在 Activity Bar 对应视图中暴露的、面向用户
打开工具或计算页面的功能按钮，除原 Activity Bar 入口外，**必须同时注册到
`contributes.ribbon`**。内部通信、加载、保存、导出等并未作为 Activity Bar 功能按钮
暴露的命令，不要求仅为满足该规范而添加到 Ribbon。

在 `ext-engineer` 中新增功能入口时，应同步完成：

1. 在 `contributes.commands` 注册命令。
2. 在 `src/node-vscode/config.ts` 注册主页面或侧边视图。
3. 在 Activity Bar 对应视图（当前通常为
   `src/browser/pages/side/ToolsBase.vue`）添加功能按钮。
4. 在 `contributes.ribbon.tabs[].groups[].items[]` 中使用同一命令添加 Ribbon 按钮。
5. 在 `package.nls.json` 与 `package.nls.zh.json` 补齐 Ribbon 文案。
6. 若修改了 commands/configuration，按扩展仓库约定运行 `pnpm update`，再完成 lint、
   build 和 test 验证。

## 排序与分组建议

- `order` 建议按 `10`、`20`、`30` 递增，方便后续插入新项。
- 一个标签表示一个稳定业务域，例如“安全计算”或“工具”；一个分组表示该业务域内
  的一类任务，不要为每个按钮创建单独标签。
- 标签 ID 使用扩展命名空间；分组 ID 只需在标签内唯一，但也应保持稳定，避免仅以
  显示顺序命名。
- 标题保持简短，使用动宾结构或用户熟悉的工具名称；不要把实现细节写进按钮标题。
- 优先复用扩展现有 SVG 或 Codicon，并验证浅色、深色和高对比度主题下的辨识度。

## 验证清单

提交前至少检查：

- `package.json` 是合法 JSON，`tabs`、`groups`、`items` 都不是空数组。
- 每个 Ribbon `command` 都已在 `contributes.commands` 注册，命令点击后能正常激活
  扩展并执行。
- 标签 ID 全局唯一，未使用三个内置保留 ID；分组 ID 在所属标签内唯一。
- `package.nls.json` 与 `package.nls.zh.json` 均包含新增文案，没有直接显示
  `%missing.key%`。
- 图标资源已包含在扩展包中，Codicon 名称有效，深浅主题下均可辨认。
- `when`、命令 precondition、`arguments` 在目标上下文中行为符合预期。
- Activity Bar 中新增的用户功能按钮已使用同一命令同步到 Ribbon。
- 展开和折叠 Ribbon 后都已手工点击按钮；折叠模式下命令执行后覆盖层能正常关闭。
- 禁用或卸载扩展后，其 Ribbon contribution 能正常消失。

## 常见问题

### Ribbon 中没有出现标签或按钮

优先查看开发者工具和扩展宿主日志中的 contribution 校验错误，然后检查必填字段、
重复 ID、保留 ID、`when` 条件和本地化键。若整个分组或标签的 `when` 为 `false`，其
下的按钮也不会显示。

### 按钮显示但不可点击

检查命令的 precondition / `enablement` 所依赖的 Context Key。按钮的 `when` 只控制
显示，不会覆盖命令自身的可用条件。

### Codicon 显示，SVG 不显示

确认路径相对于扩展根目录、大小写完全一致，并检查 `.vscodeignore`、打包脚本和最终
VSIX 是否包含该资源。不要使用工作区绝对路径。

### 点击按钮后命令找不到

确认 `items[].command` 与 `contributes.commands[].command` 完全一致，并确认命令的
注册和扩展激活事件仍然有效。Ribbon 是声明式入口，不会替扩展注册命令，也不会单独
激活扩展。
