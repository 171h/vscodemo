#!/usr/bin/env bash
# =============================================================================
# upgrade.sh — 升级到新的 VS Code / VSCodium 版本
#
# 用法: bash scripts/upgrade.sh <vscodium-release-tag>
# 示例: bash scripts/upgrade.sh 1.126.04524
#
# 流程：
#   1. 将 vscodium 子模块 checkout 到新 release
#   2. 从 vscodium/upstream/stable.json 读取新的 vscode tag + commit
#   3. 写回 upstream.lock.json
#   4. 重新检出 vscode 到新 commit
#   5. 逐个预检补丁（git apply --check），列出冲突清单
#
# 冲突时逐个重做补丁，并分别验证干净 VS Code 与 VSCodium 后置基线。
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[ $# -eq 1 ] || { echo "用法: bash scripts/upgrade.sh <vscodium-release-tag>"; exit 1; }
NEW_RELEASE="$1"

# --- 1. 更新 vscodium 子模块 ----------------------------------------------------
echo "==> 更新 vscodium 到 ${NEW_RELEASE} ..."
git -C vscodium fetch --tags origin
git -C vscodium checkout "$NEW_RELEASE"
# 立即暂存 gitlink，保证提交的子模块指针与锁定 release 一致
git add vscodium
NEW_VSCODIUM_COMMIT=$(git -C vscodium rev-parse HEAD)

# --- 2. 读取新的 vscode 版本 ----------------------------------------------------
NEW_TAG=$(node -p "require('./vscodium/upstream/stable.json').tag")
NEW_COMMIT=$(node -p "require('./vscodium/upstream/stable.json').commit")
echo "==> 新版本: vscode ${NEW_TAG} (${NEW_COMMIT})"

# --- 3. 写回锁定文件 ------------------------------------------------------------
# 必须用 heredoc 经 stdin 传脚本：Windows 下 node 经 cmd shim 调用时，
# 含换行的 -e 参数会被静默吞掉（不执行且退出码仍为 0）
NEW_TAG="$NEW_TAG" NEW_COMMIT="$NEW_COMMIT" \
NEW_RELEASE="$NEW_RELEASE" NEW_VSCODIUM_COMMIT="$NEW_VSCODIUM_COMMIT" \
node - <<'NODE'
const fs = require('fs');
const lock = JSON.parse(fs.readFileSync('upstream.lock.json', 'utf8'));
lock.vscode.tag = process.env.NEW_TAG;
lock.vscode.commit = process.env.NEW_COMMIT;
lock.vscodium.release = process.env.NEW_RELEASE;
lock.vscodium.commit = process.env.NEW_VSCODIUM_COMMIT;
fs.writeFileSync('upstream.lock.json', JSON.stringify(lock, null, 2) + '\n');
NODE
echo "==> upstream.lock.json 已更新"

# --- 4. 重新检出 vscode ---------------------------------------------------------
HAS_VSCODE=false
if [ -d vscode/.git ]; then
  if [ -n "$(git -C vscode status --porcelain)" ]; then
    echo "错误: vscode 检出有本地修改，请先重置（git -C vscode checkout . && git -C vscode clean -fd）"
    exit 1
  fi
  git -C vscode fetch --depth 1 origin "$NEW_COMMIT"
  git -C vscode checkout "$NEW_COMMIT"
  HAS_VSCODE=true
else
  echo "提示: ./vscode 不存在，稍后运行 bash scripts/init.sh 获取并完成补丁预检"
fi

# --- 5. 补丁预检 ----------------------------------------------------------------
if [ "$HAS_VSCODE" = true ]; then
  # 使用临时 index 按实际顺序叠加预检。部分补丁明确依赖前置补丁，逐个对干净
  # HEAD 执行 apply --check 会把这类依赖误报为冲突。
  TMP_INDEX=$(mktemp)
  rm -f "$TMP_INDEX"
  trap 'rm -f "$TMP_INDEX"' EXIT
  GIT_INDEX_FILE="$TMP_INDEX" git -C vscode read-tree HEAD

  shopt -s nullglob
  FAILED=()
  for p in patches/*.patch; do
    if GIT_INDEX_FILE="$TMP_INDEX" git -C vscode apply --cached "../$p" 2>/dev/null; then
      echo "  [OK]   $p"
    else
      echo "  [冲突] $p"
      FAILED+=("$p")
      break
    fi
  done
  rm -f "$TMP_INDEX"
  trap - EXIT

  echo ""
  if [ ${#FAILED[@]} -gt 0 ]; then
    echo "补丁按顺序叠加到 $p 时失败："
    printf '  %s\n' "${FAILED[@]}"
    exit 1
  fi

  echo "所有补丁预检通过。请运行构建并回归测试，然后记录本次升级。"
else
  echo "版本锁定已更新；初始化 vscode 后请重新运行本脚本完成补丁预检。"
fi
