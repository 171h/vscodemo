#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const [buildScriptPath, wixSourcePath, wixVariablesPath] = process.argv.slice(2);

if (!buildScriptPath || !wixSourcePath || !wixVariablesPath) {
  console.error('usage: node scripts/lib/patch-windows-msi.mjs <build.sh> <vscodium.wxs> <vscodium-variables.wxi>');
  process.exit(2);
}

function replaceRequired(text, from, to, label) {
  const occurrences = text.split(from).length - 1;
  if (occurrences !== 1) {
    throw new Error(`${label}: 预期匹配 1 次，实际匹配 ${occurrences} 次`);
  }

  return text.replace(from, to);
}

let buildScript = fs.readFileSync(buildScriptPath, 'utf8');
const newline = buildScript.includes('\r\n') ? '\r\n' : '\n';
buildScript = replaceRequired(
  buildScript,
  'if [[ "${VSCODE_QUALITY}" == "insider" ]]; then',
  `PRODUCT_DISPLAY_NAME="\${APP_DISPLAY_NAME}"${newline}${newline}if [[ "\${VSCODE_QUALITY}" == "insider" ]]; then`,
  'MSI 展示名称变量注入'
);
buildScript = replaceRequired(
  buildScript,
  '  PRODUCT_NAME="VSCodium"',
  '  PRODUCT_NAME="${APP_NAME}"',
  'MSI 内部名称品牌化'
);
buildScript = replaceRequired(
  buildScript,
  '  PRODUCT_CODE="VSCodium"',
  '  PRODUCT_CODE="${APP_NAME}"',
  'MSI ProductCode 品牌化'
);
buildScript = replaceRequired(
  buildScript,
  '  PRODUCT_UPGRADE_CODE="965370CD-253C-4720-82FC-2E6B02A53808"',
  '  PRODUCT_UPGRADE_CODE="${MSI_PRODUCT_UPGRADE_CODE}"',
  'MSI UpgradeCode 独立化'
);
buildScript = replaceRequired(
  buildScript,
  'OUTPUT_BASE_FILENAME="VSCodium-${VSCODE_ARCH}-${RELEASE_VERSION}"',
  'OUTPUT_BASE_FILENAME="${APP_NAME}-${VSCODE_ARCH}-${RELEASE_VERSION}"',
  'MSI 普通产物名品牌化'
);
buildScript = replaceRequired(
  buildScript,
  'OUTPUT_BASE_FILENAME="VSCodium-${VSCODE_ARCH}-${1}-${RELEASE_VERSION}"',
  'OUTPUT_BASE_FILENAME="${APP_NAME}-${VSCODE_ARCH}-${1}-${RELEASE_VERSION}"',
  'MSI 禁用更新产物名品牌化'
);
buildScript = replaceRequired(
  buildScript,
  'find i18n -name \'*.wxl\' -print0 | xargs -0 sed -i "s|@@PRODUCT_NAME@@|${PRODUCT_NAME}|g"',
  'find i18n -name \'*.wxl\' -print0 | xargs -0 sed -i "s|@@PRODUCT_NAME@@|${PRODUCT_DISPLAY_NAME}|g"',
  'MSI 本地化展示名称品牌化'
);
buildScript = replaceRequired(
  buildScript,
  '-dAppName="${PRODUCT_NAME}"',
  '-dAppName="${PRODUCT_NAME}" -dAppDisplayName="${PRODUCT_DISPLAY_NAME}"',
  'MSI WiX 展示名称参数注入'
);
buildScript = replaceRequired(
  buildScript,
  '-dManufacturerName="VSCodium"',
  '-dManufacturerName="${ORG_NAME}"',
  'MSI 发布者品牌化'
);
buildScript = replaceRequired(
  buildScript,
  '-dProductVersion="${RELEASE_VERSION%-insider}"',
  '-dProductVersion="${WINDOWS_PRODUCT_VERSION:-${RELEASE_VERSION%%[-+]*}}"',
  'MSI 数字产品版本规范化'
);
fs.writeFileSync(buildScriptPath, buildScript);

let wixSource = fs.readFileSync(wixSourcePath, 'utf8');
wixSource = replaceRequired(
  wixSource,
  '<Product Id="$(var.ProductId)"',
  '<Product Codepage="65001" Id="$(var.ProductId)"',
  'MSI 数据库 UTF-8 代码页'
);
wixSource = replaceRequired(
  wixSource,
  '<Directory Id="$(var.AppCodeName)ProgramMenuFolder" Name="$(var.AppName)">',
  '<Directory Id="$(var.AppCodeName)ProgramMenuFolder" Name="$(var.AppDisplayName)">',
  'MSI 开始菜单目录展示名称'
);
wixSource = replaceRequired(
  wixSource,
  '<Shortcut Id="$(var.AppCodeName)StartMenuShortcut" Advertise="no" Name="$(var.AppName)"',
  '<Shortcut Id="$(var.AppCodeName)StartMenuShortcut" Advertise="no" Name="$(var.AppDisplayName)"',
  'MSI 开始菜单快捷方式展示名称'
);
wixSource = replaceRequired(
  wixSource,
  '<Shortcut Id="$(var.AppCodeName)DesktopShortcut" Advertise="no" Name="$(var.AppName)"',
  '<Shortcut Id="$(var.AppCodeName)DesktopShortcut" Advertise="no" Name="$(var.AppDisplayName)"',
  'MSI 桌面快捷方式展示名称'
);
fs.writeFileSync(wixSourcePath, wixSource);

// VSCodium 上游在 vscodium-variables.wxi 硬编码 RTMProductVersion="0.0.1"，
// 配合 vscodium.wxs:27 的 UpgradeVersion 形成 [RTM, current) 升级区间。
// vscodemo 首发版本同样是 0.0.1，导致 Minimum == Maximum 且 IncludeMaximum=no，
// 区间退化为空集，WiX light.exe 链接 MSI 时触发 ICE61 (LGHT0204)。把 RTM
// 起点下调到 0.0.0，使 [0.0.0, 0.0.1) 非空，升级语义保持正确（任何早于
// 当前的版本都可被检测升级），同时避开 ICE61 边界。
let wixVariables = fs.readFileSync(wixVariablesPath, 'utf8');
wixVariables = replaceRequired(
  wixVariables,
  '<?define RTMProductVersion="0.0.1" ?>',
  '<?define RTMProductVersion="0.0.0" ?>',
  'MSI RTM 版本下放（规避 ICE61: RTM==ProductVersion）'
);
fs.writeFileSync(wixVariablesPath, wixVariables);

// APP_DISPLAY_NAME 会被注入每一种本地化资源。只修改 Product 不足以覆盖
// light.exe 的 -loc 输入；任一 .wxl 保留 1252/其他单字节代码页，都会在
// 构建对应 MSI/transform 时因中文产品名触发 LGHT0311。
const localizationDir = path.join(path.dirname(wixSourcePath), 'i18n');
const localizationFiles = fs.readdirSync(localizationDir)
  .filter(fileName => fileName.endsWith('.wxl'))
  .sort();

if (localizationFiles.length === 0) {
  throw new Error(`MSI 本地化 UTF-8 代码页: ${localizationDir} 中没有 .wxl 文件`);
}

for (const fileName of localizationFiles) {
  const localizationPath = path.join(localizationDir, fileName);
  let localization = fs.readFileSync(localizationPath, 'utf8');
  const codepagePattern = /(<WixLocalization\b[^>]*\bCodepage=")[^"]+("[^>]*>)/g;
  const matches = [...localization.matchAll(codepagePattern)];
  if (matches.length !== 1) {
    throw new Error(`MSI 本地化 UTF-8 代码页 (${fileName}): 预期匹配 1 次，实际匹配 ${matches.length} 次`);
  }

  localization = localization.replace(
    codepagePattern,
    (_match, prefix, suffix) => `${prefix}65001${suffix}`
  );
  fs.writeFileSync(localizationPath, localization);
}
