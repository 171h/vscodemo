#!/usr/bin/env bash
# =============================================================================
# act-verify.sh - 使用 nektos/act 在本地验证 GitHub Actions workflow
#
# 默认执行 dry-run：检查 workflow 是否能被 act 解析、调度和展开。
# 如需真正执行 job，显式传入 --run；注意 act 主要通过 Docker 模拟 Linux runner，
# Windows/macOS runner 只能做有限验证，不能视为等价复现。
#
# 在 Git Bash 中运行：
#   bash scripts/act-verify.sh
#   bash scripts/act-verify.sh --run -j publish
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DEFAULT_WORKFLOW=".github/workflows/release-vscode.yml"
DEFAULT_EVENT="workflow_dispatch"
DEFAULT_RELEASE_TAG="$(node -p "require('./upstream.lock.json').vscodium.release" 2>/dev/null || printf '1.126.04524')"
DEFAULT_ACT_IMAGE="ghcr.io/catthehacker/ubuntu:act-22.04"

WORKFLOW="$DEFAULT_WORKFLOW"
EVENT="$DEFAULT_EVENT"
RELEASE_TAG="$DEFAULT_RELEASE_TAG"
MODE="dry-run"
JOB=""
SECRET_FILE=""
ENV_FILE=""
RUN_ACTIONLINT="auto"
MAP_NON_LINUX=0
ACT_IMAGE="${ACT_IMAGE:-$DEFAULT_ACT_IMAGE}"
EXTRA_ACT_ARGS=()

usage() {
  cat <<'EOF'
用法:
  bash scripts/act-verify.sh [选项] [-- act 额外参数]

常用:
  bash scripts/act-verify.sh
  bash scripts/act-verify.sh --list
  bash scripts/act-verify.sh --run -j publish
  bash scripts/act-verify.sh --run -j build --map-non-linux
  bash scripts/act-verify.sh --release-tag v1.126.04524
  bash scripts/act-verify.sh --secret-file .secrets.local

选项:
  -W, --workflow <file>       指定 workflow 文件，默认 .github/workflows/release-vscode.yml
  -e, --event <name>          指定事件，默认 workflow_dispatch
  -j, --job <name>            只验证/运行某个 job
      --release-tag <tag>     workflow_dispatch 的 release_tag 输入，默认读取 upstream.lock.json
      --secret-file <file>    传给 act 的 secrets 文件；未指定时自动使用 .secrets（如存在）
      --env-file <file>       传给 act 的 env 文件
      --run                   真正执行 act；默认只 dry-run
      --dry-run               只做 dry-run（默认）
      --list                  列出 act 识别到的 workflows/jobs
      --no-actionlint         跳过 actionlint 静态检查
      --map-non-linux         将 windows/macos runner label 映射到 Linux act 镜像
      --image <image>         指定 act 使用的 Linux runner 镜像
  -h, --help                  显示帮助

环境变量:
  ACT_IMAGE                   覆盖默认 act 镜像
  GITHUB_TOKEN                作为同名 secret 注入 act

说明:
  act 适合本地验证 workflow 结构、表达式展开和 Linux job 的命令链路。
  Windows/macOS 构建、GitHub 权限、OIDC、artifact/cache/release 等行为仍需在 GitHub 上最终验证。
EOF
}

die() {
  echo "错误: $*" >&2
  exit 1
}

warn() {
  echo "警告: $*" >&2
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "未找到命令 '$1'，请先安装并加入 PATH"
}

need_act() {
  if ! command -v act >/dev/null 2>&1; then
    cat >&2 <<'EOF'
错误: 未找到命令 'act'，请先安装 nektos/act 并加入 PATH。

安装说明:
  https://github.com/nektos/act#installation

Windows 上建议在 Git Bash 中运行本脚本，并确认 Docker Desktop 已启动。
EOF
    exit 1
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -W|--workflow)
      [ "$#" -ge 2 ] || die "$1 需要参数"
      WORKFLOW="$2"
      shift 2
      ;;
    -e|--event)
      [ "$#" -ge 2 ] || die "$1 需要参数"
      EVENT="$2"
      shift 2
      ;;
    -j|--job)
      [ "$#" -ge 2 ] || die "$1 需要参数"
      JOB="$2"
      shift 2
      ;;
    --release-tag)
      [ "$#" -ge 2 ] || die "$1 需要参数"
      RELEASE_TAG="$2"
      shift 2
      ;;
    --secret-file)
      [ "$#" -ge 2 ] || die "$1 需要参数"
      SECRET_FILE="$2"
      shift 2
      ;;
    --env-file)
      [ "$#" -ge 2 ] || die "$1 需要参数"
      ENV_FILE="$2"
      shift 2
      ;;
    --image)
      [ "$#" -ge 2 ] || die "$1 需要参数"
      ACT_IMAGE="$2"
      shift 2
      ;;
    --run)
      MODE="run"
      shift
      ;;
    --dry-run)
      MODE="dry-run"
      shift
      ;;
    --list)
      MODE="list"
      shift
      ;;
    --no-actionlint)
      RUN_ACTIONLINT="never"
      shift
      ;;
    --map-non-linux)
      MAP_NON_LINUX=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      EXTRA_ACT_ARGS=("$@")
      break
      ;;
    *)
      die "未知参数: $1"
      ;;
  esac
done

[ -f "$WORKFLOW" ] || die "workflow 文件不存在: $WORKFLOW"

need_act
need_cmd git
need_cmd node

if [ "$MODE" = "run" ]; then
  need_cmd docker
  docker info >/dev/null 2>&1 || die "Docker 未运行，act 需要可用的 Docker daemon"
fi

if [ "$RUN_ACTIONLINT" != "never" ]; then
  if command -v actionlint >/dev/null 2>&1; then
    echo "==> actionlint: 静态检查 .github/workflows"
    actionlint
  else
    warn "未找到 actionlint，跳过静态检查；如需更早发现 YAML/表达式问题，可安装 actionlint"
  fi
fi

ACT_ARGS=("$EVENT" "-W" "$WORKFLOW")

if [ "$MODE" = "dry-run" ]; then
  ACT_ARGS+=("--dryrun")
fi

if [ -n "$JOB" ]; then
  ACT_ARGS+=("-j" "$JOB")
fi

if [ "$MODE" = "list" ]; then
  echo "==> act: 列出 workflows/jobs"
  exec act -W "$WORKFLOW" -l "${EXTRA_ACT_ARGS[@]}"
fi

TMP_EVENT=""
cleanup() {
  if [ -n "$TMP_EVENT" ] && [ -f "$TMP_EVENT" ]; then
    rm -f "$TMP_EVENT"
  fi
}
trap cleanup EXIT

if [ "$EVENT" = "workflow_dispatch" ]; then
  TMP_EVENT="$(mktemp)"
  node -e '
const fs = require("fs");
const path = process.argv[1];
const releaseTag = process.argv[2];
fs.writeFileSync(path, JSON.stringify({ inputs: { release_tag: releaseTag } }, null, 2) + "\n");
' "$TMP_EVENT" "$RELEASE_TAG"
  ACT_ARGS+=("-e" "$TMP_EVENT")
  echo "==> workflow_dispatch 输入: release_tag=${RELEASE_TAG}"
fi

if [ -z "$SECRET_FILE" ] && [ -f ".secrets" ]; then
  SECRET_FILE=".secrets"
fi

if [ -n "$SECRET_FILE" ]; then
  [ -f "$SECRET_FILE" ] || die "secret 文件不存在: $SECRET_FILE"
  ACT_ARGS+=("--secret-file" "$SECRET_FILE")
fi

if [ -n "$ENV_FILE" ]; then
  [ -f "$ENV_FILE" ] || die "env 文件不存在: $ENV_FILE"
  ACT_ARGS+=("--env-file" "$ENV_FILE")
fi


if [ -n "${GITHUB_TOKEN:-}" ]; then
  ACT_ARGS+=("--secret" "GITHUB_TOKEN=${GITHUB_TOKEN}")
fi

PLATFORM_ARGS=(
  "-P" "ubuntu-latest=${ACT_IMAGE}"
  "-P" "ubuntu-22.04=${ACT_IMAGE}"
)

if [ "$MODE" = "dry-run" ] || [ "$MAP_NON_LINUX" -eq 1 ]; then
  PLATFORM_ARGS+=(
    "-P" "windows-latest=${ACT_IMAGE}"
    "-P" "windows-2022=${ACT_IMAGE}"
    "-P" "macos-latest=${ACT_IMAGE}"
    "-P" "macos-15-intel=${ACT_IMAGE}"
  )
fi

if [ "$MODE" = "run" ] && [ "$MAP_NON_LINUX" -eq 1 ]; then
  warn "--map-non-linux 只是把 runner label 映射到 Linux 容器；Windows/macOS 专有命令可能仍会失败"
fi

echo "==> act: workflow=${WORKFLOW}, event=${EVENT}, mode=${MODE}${JOB:+, job=${JOB}}"
act "${ACT_ARGS[@]}" "${PLATFORM_ARGS[@]}" "${EXTRA_ACT_ARGS[@]}"
