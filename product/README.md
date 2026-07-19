# VSCodemo 产品配置

`product.override.json` 只负责把 VSCodium 品牌隔离为 VSCodemo。它使用独立的数据
目录、URL protocol、Windows AppId/CLSID 与 MSI UpgradeCode，因此可与官方 VS Code
和 VSCodium 并存。

`windows-identity.lock.json` 是 VSCodemo 的永久 Windows 安装身份。发布后不得重新
生成；`scripts/build.sh` 会在构建前校验它与 product override 完全一致。

VSCodemo 默认禁用自动更新，防止调试宿主被不含 Ribbon 扩展点的官方 VSCodium 覆盖。
