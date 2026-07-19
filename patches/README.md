# VSCodemo 补丁

本目录只允许三类补丁：

- VSCodemo 跨平台品牌适配：`100`、`216`、`217`；
- VSCodium 构建稳定性适配：`208`、`218`；
- Ribbon 功能：`219-feature-ribbon-part.patch`。

开发模式由 `scripts/prepare.sh` 按文件名顺序应用到干净的 `vscode/`；发行构建由
`scripts/build.sh` 同步到 `vscodium/patches/user/`，在 VSCodium 官方补丁之后应用。
修改时必须对两种顺序分别执行 `git apply --check`。
