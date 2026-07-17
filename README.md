# VSCodemo（only-ribbon）

本分支构建一个用于扩展开发与调试的专用 VS Code 宿主。它以 VSCodium 构建链为
基础，仅保留 `main` 中的 Ribbon 能力，并把产品名改为 `VSCodemo`。

与 `main` 相比，本分支不包含 VSCodemo 的界面裁剪、默认语言、菜单改造、
ActivityBar/Panel 改造或自研内置扩展。`ext-engineer` 也不会内置到产物中，避免
通过 Extension Development Host 调试时同时加载两个副本。

## 保留的差异

- `patches/219-feature-ribbon-part.patch`：新增 Ribbon Part 和
  `contributes.ribbon` 扩展点。
- `product/product.override.json`：将 VSCodium 品牌隔离为 VSCodemo。
- `patches/100-*`、`216-*`、`217-*` 与 Windows MSI helper：使 VSCodemo 品牌在
  macOS/Windows 打包元数据中保持一致。这些属于产品改名的必要适配，不引入功能改造。

## 初始化与开发

所有 shell 脚本都应从 Git Bash 运行：

```bash
bash scripts/init.sh
bash scripts/prepare.sh
cd vscode
npm i
npm run watch
```

另开一个 Git Bash 终端启动开发版本：

```bash
cd vscode
./scripts/code.bat
```

随后在 `ext-engineer` 仓库中使用扩展调试配置，将 Extension Development Host
指向这个已应用 Ribbon 补丁的 `vscode` 检出或 VSCodemo 构建产物。

## 发行构建

```bash
bash scripts/build.sh
bash scripts/build.sh --assets
```

生成 changelog、创建 tag 并触发 GitHub Actions 发布构建：

```bash
bash scripts/release.sh
```

版本仍由 `upstream.lock.json` 唯一锁定；升级使用：

```bash
bash scripts/upgrade.sh <vscodium-release>
```

详细的 Ribbon contribution 格式见[扩展贡献 Ribbon](docs/guide/ribbon-contribution.md)。
