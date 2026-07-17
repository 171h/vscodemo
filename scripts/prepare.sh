#!/usr/bin/env bash
# =============================================================================
# prepare.sh — 开发模式准备：把 VSCodemo 品牌与 Ribbon 叠加到 ./vscode
#
# 1. 校验并应用品牌适配与 Ribbon 补丁
# 2. 将 product/product.override.json 合并进 vscode/product.json
#
# 幂等性说明：本脚本假定 vscode 检出是"干净"的（HEAD == 锁定 commit 且无本地
# 修改）。重复运行前先执行 bash scripts/reset-vscode.sh 或
# git -C vscode checkout . && git -C vscode clean -fd extensions/
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[ -d vscode ] || { echo "错误: ./vscode 不存在，请先运行 bash scripts/init.sh"; exit 1; }

# --- 0. 干净检查 --------------------------------------------------------------
if [ -n "$(git -C vscode status --porcelain)" ]; then
  echo "警告: vscode 检出存在本地修改。如果是上次 prepare 的结果，请先重置："
  echo "  git -C vscode checkout . && git -C vscode clean -fd"
  exit 1
fi

# --- 1. 应用补丁 --------------------------------------------------------------
shopt -s nullglob
PATCHES=(patches/*.patch)
if [ ${#PATCHES[@]} -gt 0 ]; then
  echo "==> 逐个应用 ${#PATCHES[@]} 个补丁..."
  for p in "${PATCHES[@]}"; do
    echo "    -> $p"
    git -C vscode apply --check "../$p" || { echo "补丁预检失败: $p"; exit 1; }
    git -C vscode apply "../$p"
  done
else
  echo "==> patches/ 下暂无补丁，跳过"
fi

# --- 2. 合并 product.json 覆盖项 -----------------------------------------------
if [ -f product/product.override.json ]; then
  echo "==> 合并 product/product.override.json -> vscode/product.json"
  # 必须用 heredoc 经 stdin 传脚本：Windows 下 node 经 cmd shim 调用时，
  # 含换行的 -e 参数会被静默吞掉（不执行且退出码仍为 0）
  node - <<'NODE'
const fs = require('fs');
const base = JSON.parse(fs.readFileSync('vscode/product.json', 'utf8'));
const over = JSON.parse(fs.readFileSync('product/product.override.json', 'utf8'));
delete over['$comment'];
fs.writeFileSync('vscode/product.json', JSON.stringify({
  ...base,
  ...over
}, null, '\t') + '\n');
NODE
fi

# 记录由本脚本生成的工作副本状态，供 update.sh 安全判断增量/全量路径。
node scripts/lib/dev-state.mjs capture

echo ""
echo "准备完成。开发模式启动（在 vscode/ 目录内）："
echo "  cd vscode && npm i && npm run watch   # 另开终端: ./scripts/code.bat (Windows) 或 ./scripts/code.sh"
