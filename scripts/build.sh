#!/usr/bin/env bash
# =============================================================================
# build.sh — 使用锁定的 VSCodium 构建链构建 VSCodemo
#
# 与开发模式（scripts/prepare.sh 叠加到根目录 ./vscode）不同，本脚本走发行
# 链路：在 vscodium/ 子模块内重新检出一份全新的 vscode 源码，并仅注入
# VSCodemo 品牌适配和 Ribbon 补丁。ext-engineer 不作为内置扩展打包。
#
# 默认行为保持原本地工作流：为当前宿主平台构建未打包的应用，然后把仓库扩展
# 注入产物。传 --assets（或 SKIP_ASSETS=no）额外执行 VSCodium 的打包阶段。
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat <<'EOF'
用法: bash scripts/build.sh [选项]

选项:
  -p, --assets       应用构建完成后继续打包安装包/压缩包产物。
  -s, --skip-source  复用已有的 vscodium/vscode 检出与 dev/build.env。
  -o, --skip-build   跳过编译，仅执行构建后处理与产物打包步骤。
  -h, --help         显示本帮助。
EOF
}

# 开关默认值（可用环境变量预设，命令行选项优先级更高）
BUILD_ASSETS="${VSCODEMO_BUILD_ASSETS:-no}"
SKIP_SOURCE="${SKIP_SOURCE:-no}"
SKIP_BUILD="${SKIP_BUILD:-no}"

# 兼容旧用法：SKIP_ASSETS=no 等价于 --assets
if [[ "${SKIP_ASSETS:-yes}" == "no" ]]; then
  BUILD_ASSETS="yes"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--assets)
      BUILD_ASSETS="yes"
      ;;
    -s|--skip-source)
      SKIP_SOURCE="yes"
      ;;
    -o|--skip-build)
      SKIP_BUILD="yes"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

# upstream.lock.json 只锁定 stable；此前允许覆盖为 insider，但 product 覆盖和
# Windows MSI 去品牌逻辑均以 stable 为基线，继续执行只会生成错配产物。
export VSCODE_QUALITY="${VSCODE_QUALITY:-stable}"
if [[ "$VSCODE_QUALITY" != "stable" ]]; then
  echo "错误: 本仓库发行构建仅支持 VSCODE_QUALITY=stable，当前为 ${VSCODE_QUALITY}" >&2
  exit 2
fi

WINDOWS_IDENTITY_LOCK="product/windows-identity.lock.json"
node scripts/lib/validate-windows-product-identity.mjs product/product.override.json "$WINDOWS_IDENTITY_LOCK"
REGISTERED_MSI_PRODUCT_UPGRADE_CODE="$(node -p "require('./${WINDOWS_IDENTITY_LOCK}').win32MsiUpgradeCode")"
if [[ -n "${MSI_PRODUCT_UPGRADE_CODE:-}" && "$MSI_PRODUCT_UPGRADE_CODE" != "$REGISTERED_MSI_PRODUCT_UPGRADE_CODE" ]]; then
  echo "错误: MSI_PRODUCT_UPGRADE_CODE 是已登记的永久安装身份，不允许通过环境变量改写" >&2
  echo "      登记值: ${REGISTERED_MSI_PRODUCT_UPGRADE_CODE}" >&2
  echo "      环境值: ${MSI_PRODUCT_UPGRADE_CODE}" >&2
  exit 2
fi
export MSI_PRODUCT_UPGRADE_CODE="$REGISTERED_MSI_PRODUCT_UPGRADE_CODE"

[ -f vscodium/prepare_vscode.sh ] || {
  echo "错误: vscodium 子模块未初始化，请先运行 bash scripts/init.sh" >&2
  exit 1
}

# 校验子模块检出与 lock 文件一致，拦截绕过 upgrade.sh 的指针漂移
# （vscode 源码版本由 overlay_upstream_lock 保证跟随 lock，这里保证的是
# vscodium 构建工具链与补丁集本身的版本）
LOCKED_VSCODIUM_COMMIT="$(node -p "require('./upstream.lock.json').vscodium.commit")"
ACTUAL_VSCODIUM_COMMIT="$(git -C vscodium rev-parse HEAD)"
if [[ "$ACTUAL_VSCODIUM_COMMIT" != "$LOCKED_VSCODIUM_COMMIT" ]]; then
  echo "错误: vscodium 子模块检出 (${ACTUAL_VSCODIUM_COMMIT})" >&2
  echo "      与 upstream.lock.json 锁定的 (${LOCKED_VSCODIUM_COMMIT}) 不一致" >&2
  echo "      请运行 bash scripts/init.sh 恢复，或通过 scripts/upgrade.sh 升级" >&2
  exit 1
fi

# 探测宿主平台/架构，映射为 VSCodium 构建链约定的 OS_NAME / VSCODE_ARCH 取值
detect_os_name() {
  case "${OSTYPE:-}" in
    darwin*) echo "osx" ;;
    msys*|cygwin*|win32*) echo "windows" ;;
    *)
      case "$(uname -s 2>/dev/null || echo unknown)" in
        Darwin*) echo "osx" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *) echo "linux" ;;
      esac
      ;;
  esac
}

detect_vscode_arch() {
  case "$(uname -m 2>/dev/null || echo x86_64)" in
    aarch64|arm64) echo "arm64" ;;
    ppc64le) echo "ppc64le" ;;
    riscv64) echo "riscv64" ;;
    loongarch64) echo "loong64" ;;
    s390x) echo "s390x" ;;
    *) echo "x64" ;;
  esac
}

# 导出 VSCodium 构建链所需的环境变量：品牌信息（APP_NAME 用于产物名，
# APP_DISPLAY_NAME 用于 MSI 展示名）、
# prepare_vscode.sh / prepare_assets.sh 使用的 product.json 与产物命名参数、
# 目标平台与版本号。上游 VS Code 检出通过 LOCKED_RELEASE_VERSION 与
# overlay_upstream_lock 固定在 upstream.lock.json。
LOCKED_RELEASE_VERSION="$(node -p "require('./upstream.lock.json').vscodium.release")"
export APP_NAME="${APP_NAME:-VSCodemo}"
export APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-$(node -p "require('./product/product.override.json').nameLong")}"
export BINARY_NAME="${BINARY_NAME:-vscodemo}"
export ORG_NAME="${ORG_NAME:-VSCodemo}"
export ASSETS_REPOSITORY="${ASSETS_REPOSITORY:-${GITHUB_REPOSITORY:-171h/vscode-magic}}"
export GH_REPO_PATH="${GH_REPO_PATH:-$ASSETS_REPOSITORY}"
export OS_NAME="${OS_NAME:-$(detect_os_name)}"
export VSCODE_ARCH="${VSCODE_ARCH:-$(detect_vscode_arch)}"
export SHOULD_BUILD="${SHOULD_BUILD:-yes}"
export CI_BUILD="${CI_BUILD:-no}"
export VSCODE_LATEST="${VSCODE_LATEST:-no}"
export VSCODE_SKIP_NODE_VERSION_CHECK="${VSCODE_SKIP_NODE_VERSION_CHECK:-yes}"
export RELEASE_VERSION="${RELEASE_VERSION:-$LOCKED_RELEASE_VERSION}"
export BUILD_SOURCEVERSION="${BUILD_SOURCEVERSION:-$(git rev-parse HEAD)}"
export BUILD_SOURCEVERSION_DATE="${BUILD_SOURCEVERSION_DATE:-$(git log -1 --format=%cI HEAD)}"
export DISABLE_UPDATE="${DISABLE_UPDATE:-yes}"
export NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=8192}"

# VS Code 1.126 的 minifyTask 会通过 map-stream 无上限并发调用 esbuild；
# Windows hosted runner 容易因此耗尽可提交内存。补丁 218 读取并发上限。
# 不要在这里全局设置 GOMEMLIMIT：tsgo 同样是 Go 程序，过低的软限制会让
# compile-src 因频繁 GC 显著变慢。
if [[ "$OS_NAME" == "windows" ]]; then
  export VSCODE_MINIFY_CONCURRENCY="${VSCODE_MINIFY_CONCURRENCY:-4}"
  export WINDOWS_PRODUCT_VERSION="$(node scripts/lib/resolve-windows-product-version.mjs "$RELEASE_VERSION")"
  echo "==> Windows 数字产品版本: ${WINDOWS_PRODUCT_VERSION}（发布版本: ${RELEASE_VERSION}）"
fi

# 构建过程会临时改写 vscodium 子模块内的文件（product.json、MSI 打包脚本），
# 先备份到临时目录，退出时（含出错中断）恢复，保证子模块工作区不留脏改动
TMP_DIR="$(mktemp -d)"
cleanup() {
  # 出错时可能仍处于 pushd 的子目录，恢复文件必须用绝对路径
  if [[ -f "$TMP_DIR/product.json" ]]; then
    cp "$TMP_DIR/product.json" "$ROOT/vscodium/product.json"
  fi
  if [[ -f "$TMP_DIR/windows-msi-build.sh" ]]; then
    cp "$TMP_DIR/windows-msi-build.sh" "$ROOT/vscodium/build/windows/msi/build.sh"
  fi
  if [[ -f "$TMP_DIR/windows-msi-vscodium.wxs" ]]; then
    cp "$TMP_DIR/windows-msi-vscodium.wxs" "$ROOT/vscodium/build/windows/msi/vscodium.wxs"
  fi
  if [[ -f "$TMP_DIR/windows-msi-variables.wxi" ]]; then
    cp "$TMP_DIR/windows-msi-variables.wxi" "$ROOT/vscodium/build/windows/msi/includes/vscodium-variables.wxi"
  fi
  if [[ -f "$TMP_DIR/windows-msi-vscodium.xsl" ]]; then
    cp "$TMP_DIR/windows-msi-vscodium.xsl" "$ROOT/vscodium/build/windows/msi/vscodium.xsl"
  fi
  if [[ -d "$TMP_DIR/windows-msi-i18n" ]]; then
    cp -R "$TMP_DIR/windows-msi-i18n/." "$ROOT/vscodium/build/windows/msi/i18n/"
  fi
  if [[ -f "$TMP_DIR/upstream-quality.json" ]]; then
    cp "$TMP_DIR/upstream-quality.json" "$ROOT/vscodium/upstream/${VSCODE_QUALITY}.json"
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# 把品牌适配与 Ribbon 补丁同步到 VSCodium 的用户补丁目录。
sync_user_patches() {
  shopt -s nullglob
  mkdir -p vscodium/patches/user
  rm -f vscodium/patches/user/*.patch

  local patches=(patches/*.patch)
  if [[ ${#patches[@]} -gt 0 ]]; then
    cp "${patches[@]}" vscodium/patches/user/
    echo "==> 已同步 ${#patches[@]} 个补丁到 vscodium/patches/user/"
  fi
}

# 把 product/product.override.json 叠加到 vscodium/product.json
# （原文件已备份，退出时恢复）。prepare_vscode.sh 随后会把这份 product.json
# merge 进 vscodium/vscode/product.json，成为产物的最终产品配置
overlay_product_json() {
  cp vscodium/product.json "$TMP_DIR/product.json"

  node - "$ROOT/vscodium/product.json" "$ROOT/product/product.override.json" <<'NODE'
const fs = require('fs');
const [productPath, overridePath] = process.argv.slice(2);
const product = JSON.parse(fs.readFileSync(productPath, 'utf8'));

if (fs.existsSync(overridePath)) {
  const override = JSON.parse(fs.readFileSync(overridePath, 'utf8'));
  delete override.$comment;
  Object.assign(product, override);
}

fs.writeFileSync(productPath, JSON.stringify(product, null, 2) + '\n');
NODE

  echo "==> 已叠加 product/product.override.json -> vscodium/product.json"
}

# 上游 MSI 把 AppName 同时用于 EXE 文件名和 UI 展示名。这里保留 APP_NAME
# 作为内部文件名，单独注入 APP_DISPLAY_NAME 供产品与快捷方式展示。helper
# 同时把 WiX 产品模板和所有本地化数据库切换到 UTF-8 代码页；上游 MSI 脚本
# 还会原地替换 variables/XSL/i18n，因此全部先备份并在退出时恢复，避免污染
# vscodium 子模块或让下次构建复用旧品牌值。
patch_windows_msi_script() {
  cp vscodium/build/windows/msi/build.sh "$TMP_DIR/windows-msi-build.sh"
  cp vscodium/build/windows/msi/vscodium.wxs "$TMP_DIR/windows-msi-vscodium.wxs"
  cp vscodium/build/windows/msi/includes/vscodium-variables.wxi "$TMP_DIR/windows-msi-variables.wxi"
  cp vscodium/build/windows/msi/vscodium.xsl "$TMP_DIR/windows-msi-vscodium.xsl"
  cp -R vscodium/build/windows/msi/i18n "$TMP_DIR/windows-msi-i18n"

  node scripts/lib/patch-windows-msi.mjs \
    "$ROOT/vscodium/build/windows/msi/build.sh" \
    "$ROOT/vscodium/build/windows/msi/vscodium.wxs"
}

# 将 upstream.lock.json 锁定的 vscode tag/commit 写入 vscodium/upstream/stable.json
# （原文件已备份，退出时恢复）。get_repo.sh 检出发行源码时从该文件读取 MS_COMMIT，
# 由此保证发行构建与根目录 ./vscode（开发副本）使用同一份锁定版本，lock 文件
# 成为构建链的唯一事实来源；若 vscode.tag 与 vscodium.release 内嵌的版本号
# 不一致，get_repo.sh 会报 "No MS_COMMIT" 直接终止，不会静默用错版本
overlay_upstream_lock() {
  local upstream_json="vscodium/upstream/${VSCODE_QUALITY}.json"
  cp "$upstream_json" "$TMP_DIR/upstream-quality.json"

  node - "$ROOT/$upstream_json" "$ROOT/upstream.lock.json" <<'NODE'
const fs = require('fs');
const [upstreamPath, lockPath] = process.argv.slice(2);
const upstream = JSON.parse(fs.readFileSync(upstreamPath, 'utf8'));
const { vscode } = JSON.parse(fs.readFileSync(lockPath, 'utf8'));

if (upstream.tag !== vscode.tag || upstream.commit !== vscode.commit) {
  console.log(`==> 注意: vscodium 子模块锁定 vscode ${upstream.tag}@${upstream.commit}`);
  console.log(`==>       与 lock 文件的 ${vscode.tag}@${vscode.commit} 不一致，以 lock 文件为准`);
}

upstream.tag = vscode.tag;
upstream.commit = vscode.commit;
fs.writeFileSync(upstreamPath, JSON.stringify(upstream, null, 2) + '\n');
NODE

  echo "==> 已将 upstream.lock.json 锁定的 vscode 版本写入 ${upstream_json}"
}

# 准备发行构建用的 vscode 源码检出（vscodium/vscode/）。
# 注意：这与根目录 ./vscode（开发模式工作副本）是两份互不相干的检出——
# 默认每次清掉旧检出，由上游 get_repo.sh 按 RELEASE_VERSION 重新拉取微软
# commit，并把版本变量记入 dev/build.env；--skip-source 时复用已有检出，
# 从 dev/build.env 恢复版本变量
prepare_vscodium_source() {
  pushd vscodium >/dev/null

  if [[ "$SKIP_SOURCE" == "no" ]]; then
    rm -rf vscode* VSCode* assets

    local build_release_version="$RELEASE_VERSION"
    local build_sourceversion="$BUILD_SOURCEVERSION"
    local build_sourceversion_date="$BUILD_SOURCEVERSION_DATE"

    # 上游脚本未按 set -u 编写（version.sh 会引用未定义的 BUILD_SOURCEVERSION 等），
    # source 期间临时关闭 nounset
    local github_env="${GITHUB_ENV:-}"
    export RELEASE_VERSION="$LOCKED_RELEASE_VERSION"
    set +u
    unset GITHUB_ENV
    . ./get_repo.sh
    if [[ -n "$github_env" ]]; then
      export GITHUB_ENV="$github_env"
    fi
    export RELEASE_VERSION="$build_release_version"
    export BUILD_SOURCEVERSION="$build_sourceversion"
    export BUILD_SOURCEVERSION_DATE="$build_sourceversion_date"
    . ./version.sh
    set -u

    {
      echo "MS_TAG=\"${MS_TAG}\""
      echo "MS_COMMIT=\"${MS_COMMIT}\""
      echo "RELEASE_VERSION=\"${RELEASE_VERSION}\""
      echo "BUILD_SOURCEVERSION=\"${BUILD_SOURCEVERSION}\""
      echo "BUILD_SOURCEVERSION_DATE=\"${BUILD_SOURCEVERSION_DATE}\""
    } > dev/build.env
  else
    if [[ ! -f dev/build.env ]]; then
      echo "错误: --skip-source 需要 vscodium/dev/build.env 已存在" >&2
      exit 1
    fi

    if [[ "$BUILD_ASSETS" != "yes" ]]; then
      rm -rf vscode-* VSCode-*
    fi

    . ./dev/build.env
    export MS_TAG MS_COMMIT RELEASE_VERSION BUILD_SOURCEVERSION BUILD_SOURCEVERSION_DATE
  fi

  popd >/dev/null
}

# 复用检出（--skip-source）时的清理：回退工作区改动与上次构建期间
# 应用补丁产生的 "VSCODIUM HELPER" 提交，恢复到干净的上游 commit，
# 避免本次构建重复应用补丁时冲突
reset_reused_vscode_tree() {
  if [[ "$SKIP_SOURCE" == "no" ]]; then
    return
  fi

  pushd vscodium/vscode >/dev/null

  git add .
  git reset -q --hard HEAD

  while [[ -n "$(git log -1 | grep "VSCODIUM HELPER" || true)" ]]; do
    git reset -q --hard HEAD~
  done

  rm -rf .build out*

  popd >/dev/null
}

# 调用 VSCodium 官方构建：build.sh 内部先执行 prepare_vscode.sh
# （品牌替换 + 应用 patches/user/ 补丁 + npm ci），再编译出 VSCode-* 产物目录
run_vscodium_build() {
  if [[ "$SKIP_BUILD" == "yes" ]]; then
    return
  fi

  reset_reused_vscode_tree

  echo "==> 调用 VSCodium 构建: OS_NAME=${OS_NAME}, VSCODE_ARCH=${VSCODE_ARCH}, RELEASE_VERSION=${RELEASE_VERSION}"
  (cd vscodium && bash build.sh)
}

normalize_appimage_names() {
  # appimagetool 用 .desktop 的 Name（nameLong，含中文与空格）命名产物，
  # 统一改成 ${APP_NAME}-${RELEASE_VERSION}.glibcX.Y-x86_64.AppImage[.zsync]
  shopt -s nullglob
  local f base suffix target
  for f in assets/*.AppImage assets/*.AppImage.zsync; do
    base="$(basename "$f")"
    [[ "$base" == *"-${RELEASE_VERSION}."* ]] || continue
    suffix="${base#*-"${RELEASE_VERSION}".}"
    target="${APP_NAME}-${RELEASE_VERSION}.${suffix}"
    if [[ "$base" != "$target" ]]; then
      mv "assets/$base" "assets/$target"
      echo "==> AppImage 产物重命名: $base -> $target"
    fi
  done
}

build_unsigned_dmg_if_needed() {
  if [[ "$OS_NAME" != "osx" || "${SHOULD_BUILD_DMG:-yes}" == "no" || "${VSCODEMO_BUILD_UNSIGNED_DMG:-yes}" != "yes" ]]; then
    return
  fi

  local dmg="assets/${APP_NAME}.${VSCODE_ARCH}.${RELEASE_VERSION}.dmg"
  if [[ -f "$dmg" ]]; then
    return
  fi

  echo "==> 未配置 macOS 签名证书，生成未签名 DMG: $dmg"
  pushd "VSCode-darwin-${VSCODE_ARCH}" >/dev/null
  # create-dmg 找不到签名证书时返回退出码 2，但 DMG 已生成，属预期行为；
  # 以产物文件是否存在为准判断成败
  npx --yes create-dmg ./*.app . || echo "==> create-dmg 退出码 $?（无签名证书时的预期行为），检查产物"
  local produced=(./*.dmg)
  if [[ ! -f "${produced[0]:-}" ]]; then
    echo "错误: create-dmg 未生成 DMG 文件" >&2
    exit 1
  fi
  mv "${produced[0]}" "../$dmg"
  popd >/dev/null
}

# 可选打包阶段（--assets）：调用 VSCodium prepare_assets.sh 生成
# 安装包/压缩包等产物到 vscodium/assets/，最后统一重算校验和
prepare_assets() {
  if [[ "$BUILD_ASSETS" != "yes" ]]; then
    return
  fi

  echo "==> 调用 VSCodium assets 打包"
  pushd vscodium >/dev/null
  rm -rf assets
  mkdir -p assets

  local original_ci_build="$CI_BUILD"
  if [[ "$OS_NAME" == "linux" && "$CI_BUILD" == "no" && ! -f stores/snapcraft/build.sh ]]; then
    echo "==> 当前 VSCodium release 未提供本地 snapcraft/build.sh，普通 Linux assets 阶段跳过 Snap"
    export CI_BUILD="yes"
  fi

  bash prepare_assets.sh
  export CI_BUILD="$original_ci_build"

  normalize_appimage_names
  build_unsigned_dmg_if_needed

  # prepare_assets.sh 在非 Windows 平台内部已跑过一次 prepare_checksums.sh，
  # 先清掉旧校验和再统一重新生成，避免出现 *.sha1.sha256 之类的嵌套校验文件
  rm -f assets/*.sha1 assets/*.sha256
  bash prepare_checksums.sh

  echo "==> assets 输出目录: $ROOT/vscodium/assets"
  popd >/dev/null
}

# --- 主流程 -------------------------------------------------------------------
sync_user_patches        # 1. 同步补丁到 vscodium/patches/user/
overlay_product_json     # 2. 叠加 VSCodemo 品牌覆盖
patch_windows_msi_script # 3. MSI 打包脚本去 VSCodium 品牌化
overlay_upstream_lock    # 4. 将 lock 文件的 vscode 版本注入 vscodium/upstream/
prepare_vscodium_source  # 5. 检出/复用 vscodium/vscode 源码
run_vscodium_build       # 6. VSCodium 构建（应用补丁 + 编译）
prepare_assets           # 7. （可选）打包安装包并生成校验和

echo ""
echo "构建完成。"
