#!/usr/bin/env bash
# 日常开发增量更新：扩展走快速同步，核心层变化自动重放完整 prepare。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[ -d vscode ] || { echo "错误: ./vscode 不存在，请先运行 bash scripts/init.sh"; exit 1; }

MODE="${1:-}"

if [ "$MODE" = "--adopt" ]; then
  if [ ! -f vscode/product.json ]; then
    echo "错误: vscode/ 看起来尚未完成 prepare，不能接管"
    exit 1
  fi
  node scripts/lib/dev-state.mjs capture
  echo "已将当前 vscode/ 工作副本接管为增量更新基线。"
  exit 0
fi

INSPECTION="$(node scripts/lib/dev-state.mjs inspect)"

read_json() {
  node -e "const x=JSON.parse(process.argv[1]); const v=$1; console.log(Array.isArray(v) ? v.join(' ') : v)" "$INSPECTION"
}

EXISTS="$(read_json 'x.exists')"
if [ "$EXISTS" != "true" ]; then
  if [ -n "$(git -C vscode status --porcelain)" ]; then
    echo "错误: 尚无开发态快照，但 vscode/ 已有修改。"
    echo "如果这些修改全部来自最近一次 prepare，可运行："
    echo "  bash scripts/update.sh --adopt"
    echo "否则请先保存手工改动，再重置 vscode/ 后运行本脚本。"
    exit 1
  fi
  echo "==> 首次运行，执行完整 prepare ..."
  bash scripts/prepare.sh
  exit 0
fi

HEAD_MATCHES="$(read_json 'x.headMatches')"
WORKTREE_MATCHES="$(read_json 'x.worktreeMatches')"
CHANGED="$(read_json 'x.changed')"

if [ "$HEAD_MATCHES" != "true" ]; then
  echo "错误: vscode/ HEAD 已改变，请先运行 bash scripts/init.sh 重新校准锁定版本。"
  exit 1
fi

if [ "$WORKTREE_MATCHES" != "true" ]; then
  echo "错误: vscode/ 包含快照之外的修改，为避免覆盖，已停止更新。"
  echo "请保存这些手工改动；确认无需保留后，可重置并重新运行 prepare.sh。"
  exit 1
fi

if [[ " $CHANGED " == *" patches "* ]] ||
   [[ " $CHANGED " == *" product "* ]]; then
  echo "==> 检测到核心层变化（$CHANGED），自动重放完整 prepare ..."
  git -C vscode checkout .
  git -C vscode clean -fd
  bash scripts/prepare.sh
  exit 0
fi

echo "没有检测到需要同步的修改。"
