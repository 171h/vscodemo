#!/usr/bin/env bash
# =============================================================================
# init.sh — 初始化工作区
#
# 1. 添加/更新 vscodium 子模块，并 checkout 到 upstream.lock.json 锁定的 release
# 2. 将 microsoft/vscode 克隆到 ./vscode（gitignore 的工作副本），
#    checkout 到锁定的 commit，并校验 hash
#
# 在 Git Bash（Windows）或任意 POSIX shell 中运行：bash scripts/init.sh
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VSCODE_TAG=$(node -p "require('./upstream.lock.json').vscode.tag")
VSCODE_COMMIT=$(node -p "require('./upstream.lock.json').vscode.commit")
VSCODE_REPO=$(node -p "require('./upstream.lock.json').vscode.repo")
VSCODIUM_RELEASE=$(node -p "require('./upstream.lock.json').vscodium.release")
VSCODIUM_COMMIT=$(node -p "require('./upstream.lock.json').vscodium.commit")
VSCODIUM_REPO=$(node -p "require('./upstream.lock.json').vscodium.repo")

echo "==> 锁定版本: vscode ${VSCODE_TAG} (${VSCODE_COMMIT}) / vscodium ${VSCODIUM_RELEASE}"

# --- 1. VSCodium 子模块 -------------------------------------------------------
# 检查 .gitmodules 是否已注册，而非检查文件系统（.gitmodules 可能在但文件未检出）
if ! git config --file .gitmodules --get submodule.vscodium.path >/dev/null 2>&1; then
  echo "==> 添加 vscodium 子模块..."
  git submodule add "$VSCODIUM_REPO" vscodium
fi
git submodule update --init vscodium
git -C vscodium fetch --tags origin
git -C vscodium checkout "$VSCODIUM_RELEASE"

# tag 可能被上游移动，锁定 commit 才是最终依据（与下方 vscode 的校验对称）
ACTUAL_VSCODIUM=$(git -C vscodium rev-parse HEAD)
if [ "$ACTUAL_VSCODIUM" != "$VSCODIUM_COMMIT" ]; then
  echo "==> release tag 当前指向 ($ACTUAL_VSCODIUM) 与锁定 commit 不一致（上游可能移动过 tag），按锁定 commit 检出..."
  git -C vscodium fetch origin "$VSCODIUM_COMMIT"
  git -C vscodium checkout "$VSCODIUM_COMMIT"
fi

# 立即暂存 gitlink，避免提交到"submodule add 时的 master tip"而不是锁定的 release
git add vscodium
echo "==> vscodium 已就位: $(git -C vscodium describe --tags) ($(git -C vscodium rev-parse HEAD))"

# --- 2. VS Code 源码检出 ------------------------------------------------------
if [ ! -d "vscode/.git" ]; then
  echo "==> 克隆 vscode @ ${VSCODE_TAG}（浅克隆）..."
  git clone --branch "$VSCODE_TAG" --depth 1 "$VSCODE_REPO" vscode
fi

ACTUAL_COMMIT=$(git -C vscode rev-parse HEAD)
if [ "$ACTUAL_COMMIT" != "$VSCODE_COMMIT" ]; then
  echo "==> 当前 HEAD ($ACTUAL_COMMIT) 与锁定 commit 不一致，尝试精确 checkout..."
  git -C vscode fetch --depth 1 origin "$VSCODE_COMMIT"
  git -C vscode checkout "$VSCODE_COMMIT"
fi
echo "==> vscode 已就位: $(git -C vscode rev-parse HEAD)"

echo ""
echo "初始化完成。下一步: bash scripts/prepare.sh（应用 VSCodemo 品牌与 Ribbon 补丁）"
