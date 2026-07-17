# 开发指南

## 准备专用宿主

在 Git Bash 中运行：

```bash
bash scripts/init.sh
bash scripts/prepare.sh
cd vscode
npm i
npm run watch
```

另开终端，从 `vscode/` 运行 `./scripts/code.bat`。这个开发实例已经包含 Ribbon
扩展点，但没有内置 `ext-engineer`，可作为 Extension Development Host 的宿主。

## 修改后的增量更新

修改 `patches/` 或 `product/` 后运行：

```bash
bash scripts/update.sh
```

脚本会在确认 `vscode/` 仅包含上一次 prepare 产生的改动后，重放品牌与 Ribbon
补丁。Ribbon contribution 的声明格式见[扩展贡献 Ribbon](./ribbon-contribution.md)。

## 构建 VSCodemo

```bash
bash scripts/build.sh
bash scripts/build.sh --assets
```

默认禁用自动更新，避免专用调试宿主被 VSCodium 官方版本覆盖并丢失 Ribbon 能力。
