#!/usr/bin/env bash
# =============================================================================
# release.sh — 发布新版本
#
# 用法: bash scripts/release.sh
#
# 流程:
#   1. 提示用户输入 tag 版本号
#   2. 校验版本号格式
#   3. 检查本地/远程 tag 冲突，冲突时提示用户确认
#   4. 创建/更新 git tag
#   5. 自动在 docs/changelog/ 生成版本日志文档
#   6. 更新 vitepress changelog 侧边栏配置
#   7. 提交 changelog 并推送 tag
#
# 推送 tag 后 GitHub Actions（release-vscode.yml）会触发构建，
# 构建完成后自动将 changelog 文档内容写入 GitHub Release 页面。
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# --- 样式常量 ---
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()  { echo -e "${CYAN}[信息]${NC} $*"; }
warn()  { echo -e "${YELLOW}[警告]${NC} $*"; }
error() { echo -e "${RED}[错误]${NC} $*" >&2; }
ok()    { echo -e "${GREEN}[完成]${NC} $*"; }

# --- 1. 输入版本号 ---
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         VSCodemo 发布脚本                ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""

read -r -p "请输入发布版本号 (如 0.1.0): " INPUT_TAG

# 去掉首尾空白
INPUT_TAG="$(echo "$INPUT_TAG" | xargs)"

if [[ -z "$INPUT_TAG" ]]; then
  error "版本号不能为空"
  exit 1
fi

# 版本号格式校验（支持可选 v 前缀）
if [[ ! "$INPUT_TAG" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]]; then
  error "版本号格式无效: $INPUT_TAG"
  echo "  期望格式: v0.1.0 或 0.1.0（可选预发布后缀如 -alpha.1）"
  exit 1
fi

# 统一加上 v 前缀
TAG="${INPUT_TAG#v}"
TAG="v${TAG}"
VERSION="${TAG#v}"

echo ""
info "版本号: ${BOLD}${TAG}${NC} (${VERSION})"

# --- 2. 获取当前分支和最新 commit ---
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
CURRENT_COMMIT="$(git rev-parse HEAD)"
COMMIT_DATE="$(git log -1 --format=%cI)"

info "当前分支: ${CURRENT_BRANCH}"
info "当前 commit: ${CURRENT_COMMIT:0:8}"

# 检查是否有未提交的更改
if [ -n "$(git status --porcelain)" ]; then
  warn "工作目录存在未提交的更改，建议先提交再发布"
  echo ""
  read -r -p "是否继续？(y/N): " DIRTY_CONFIRM
  if [[ ! "$DIRTY_CONFIRM" =~ ^[Yy]$ ]]; then
    info "已取消"
    exit 0
  fi
fi

# --- 3. 检查 tag 冲突 ---
LOCAL_CONFLICT=false
REMOTE_CONFLICT=false
EXISTING_TAG_COMMIT=""

# 检查本地 tag
if git rev-parse "$TAG" >/dev/null 2>&1; then
  LOCAL_CONFLICT=true
  EXISTING_TAG_COMMIT="$(git rev-parse "$TAG")"
  warn "本地已存在 tag: ${TAG} (指向 ${EXISTING_TAG_COMMIT:0:8})"
fi

# 检查远程 tag
REMOTE_TAG_INFO="$(git ls-remote --tags origin "$TAG" 2>/dev/null || true)"
if [ -n "$REMOTE_TAG_INFO" ]; then
  REMOTE_CONFLICT=true
  REMOTE_TAG_COMMIT="$(echo "$REMOTE_TAG_INFO" | awk '{print $1}')"
  warn "远程已存在 tag: ${TAG} (指向 ${REMOTE_TAG_COMMIT:0:8})"
fi

# 冲突处理
if $LOCAL_CONFLICT || $REMOTE_CONFLICT; then
  echo ""
  echo -e "${YELLOW}╔══════════════════════════════════════════╗${NC}"
  echo -e "${YELLOW}║  ⚠ tag 冲突                             ║${NC}"
  echo -e "${YELLOW}╚══════════════════════════════════════════╝${NC}"
  echo ""
  if $LOCAL_CONFLICT; then
    echo "  本地 tag ${TAG} → ${EXISTING_TAG_COMMIT:0:8}"
  fi
  if $REMOTE_CONFLICT; then
    echo "  远程 tag ${TAG} → ${REMOTE_TAG_COMMIT:0:8}"
  fi
  echo "  当前 HEAD  → ${CURRENT_COMMIT:0:8}"
  echo ""
  read -r -p "是否覆盖 tag ${TAG} 并指向当前 HEAD？(y/N): " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    info "已取消"
    exit 0
  fi
  ok "确认覆盖 tag"
fi

# --- 4. 预处理旧 tag ---
echo ""

# 删除本地旧 tag（如果存在），避免后续计算 changelog 范围时命中待覆盖 tag
if $LOCAL_CONFLICT; then
  info "删除本地旧 tag: ${TAG}..."
  git tag -d "$TAG"
fi

# --- 5. 生成 changelog 文档 ---
CHANGELOG_DIR="docs/changelog"
CHANGELOG_FILE="${CHANGELOG_DIR}/${TAG}.md"

# 查找上一个 tag 作为 changelog 范围
PREV_TAG="$(git describe --tags --abbrev=0 HEAD 2>/dev/null || true)"

info "生成版本日志: ${CHANGELOG_FILE}"

# 获取 git log
if [ -n "$PREV_TAG" ]; then
  LOG_RANGE="${PREV_TAG}..HEAD"
  info "变更范围: ${PREV_TAG} → ${TAG}"
else
  LOG_RANGE="HEAD"
  info "首次发布，无上一版本可比较"
fi

# 获取提交列表（去重，按 conventional commit 分类）
COMMITS_RAW="$(git log "${LOG_RANGE}" --no-merges --format='%s' 2>/dev/null || true)"

# 生成 changelog markdown 内容
cat > "$CHANGELOG_FILE" <<CHANGELOG_EOF
# ${TAG} 版本发布

- **日期**: $(date -d "$COMMIT_DATE" +%Y-%m-%d 2>/dev/null || echo "$COMMIT_DATE")
- **commit**: ${CURRENT_COMMIT}
- **VS Code 上游**: $(node -p "require('./upstream.lock.json').vscode.tag")
- **VSCodium release**: $(node -p "require('./upstream.lock.json').vscodium.release")

## 变更摘要

CHANGELOG_EOF

# 统计各类提交
FEAT_COUNT=0
FIX_COUNT=0
BUILD_COUNT=0
CHORE_COUNT=0
DOCS_COUNT=0
REFACTOR_COUNT=0

FEAT_ITEMS=""
FIX_ITEMS=""
BUILD_ITEMS=""
CHORE_ITEMS=""
DOCS_ITEMS=""
REFACTOR_ITEMS=""

while IFS= read -r line; do
  [ -z "$line" ] && continue
  # 提取 conventional commit 类型并格式化
  if [[ "$line" =~ ^(feat|feature) ]]; then
    ((FEAT_COUNT++)) || true
    FEAT_ITEMS="${FEAT_ITEMS}- ${line}
"
  elif [[ "$line" =~ ^fix ]]; then
    ((FIX_COUNT++)) || true
    FIX_ITEMS="${FIX_ITEMS}- ${line}
"
  elif [[ "$line" =~ ^build ]]; then
    ((BUILD_COUNT++)) || true
    BUILD_ITEMS="${BUILD_ITEMS}- ${line}
"
  elif [[ "$line" =~ ^chore ]]; then
    ((CHORE_COUNT++)) || true
    CHORE_ITEMS="${CHORE_ITEMS}- ${line}
"
  elif [[ "$line" =~ ^docs ]]; then
    ((DOCS_COUNT++)) || true
    DOCS_ITEMS="${DOCS_ITEMS}- ${line}
"
  elif [[ "$line" =~ ^refactor ]]; then
    ((REFACTOR_COUNT++)) || true
    REFACTOR_ITEMS="${REFACTOR_ITEMS}- ${line}
"
  else
    # 未分类的放入 chore
    ((CHORE_COUNT++)) || true
    CHORE_ITEMS="${CHORE_ITEMS}- ${line}
"
  fi
done <<< "$COMMITS_RAW"

# 写入分类的变更
write_section() {
  local title="$1"
  local items="$2"
  if [ -n "$items" ]; then
    echo "### ${title}" >> "$CHANGELOG_FILE"
    echo "" >> "$CHANGELOG_FILE"
    echo "$items" >> "$CHANGELOG_FILE"
  fi
}

write_section "✨ 新功能 (feat)" "$FEAT_ITEMS"
write_section "🐛 缺陷修复 (fix)" "$FIX_ITEMS"
write_section "🔨 构建与依赖 (build)" "$BUILD_ITEMS"
write_section "📝 文档 (docs)" "$DOCS_ITEMS"
write_section "♻️ 重构 (refactor)" "$REFACTOR_ITEMS"
write_section "🔧 杂项 (chore)" "$CHORE_ITEMS"

# 添加统计摘要
{
  echo ""
  echo "## 统计"
  echo ""
  echo "| 类型 | 数量 |"
  echo "| --- | --- |"
  echo "| ✨ feat | ${FEAT_COUNT} |"
  echo "| 🐛 fix | ${FIX_COUNT} |"
  echo "| 🔨 build | ${BUILD_COUNT} |"
  echo "| 📝 docs | ${DOCS_COUNT} |"
  echo "| ♻️ refactor | ${REFACTOR_COUNT} |"
  echo "| 🔧 chore | ${CHORE_COUNT} |"
} >> "$CHANGELOG_FILE"

ok "版本日志已生成: ${CHANGELOG_FILE}"

# --- 6. 更新 changelog 索引 ---
CHANGELOG_INDEX="${CHANGELOG_DIR}/index.md"

info "更新 changelog 索引..."

# 在索引表末尾插入新行
INDEX_ENTRY="| $(date -d "$COMMIT_DATE" +%Y-%m-%d 2>/dev/null || echo "$COMMIT_DATE") | $(node -p "require('./upstream.lock.json').vscode.tag") | $(node -p "require('./upstream.lock.json').vscodium.release") | — | [${TAG}](./${TAG}.md) |"

# 在 "记录索引" 表格末尾插入，避免命中后续模板代码块中的表格
CHANGELOG_INDEX="$CHANGELOG_INDEX" INDEX_ENTRY="$INDEX_ENTRY" node - <<'NODE'
const fs = require('fs');
const indexPath = process.env.CHANGELOG_INDEX;
const entry = process.env.INDEX_ENTRY;
const lines = fs.readFileSync(indexPath, 'utf8').split(/\r?\n/);

let insertAt = -1;
let inFence = false;
for (let i = 0; i < lines.length; i++) {
  const line = lines[i];
  if (line.startsWith('```')) {
    inFence = !inFence;
    continue;
  }
  if (inFence || !line.startsWith('|')) {
    continue;
  }

  insertAt = i + 1;
  while (insertAt < lines.length && lines[insertAt].startsWith('|')) {
    insertAt++;
  }
  break;
}

if (insertAt === -1) {
  console.warn('  未找到 changelog 记录索引表格，请手动更新 index.md');
  process.exit(0);
}

if (lines.includes(entry)) {
  console.log('  changelog 记录索引已包含该版本，跳过');
  process.exit(0);
}

lines.splice(insertAt, 0, entry);
fs.writeFileSync(indexPath, lines.join('\n'), 'utf8');
console.log(`  changelog 记录索引已更新: ${entry}`);
NODE

# 使用 node 更新 vitepress 侧边栏配置
CHANGELOG_DATE="$(date -d "$COMMIT_DATE" +%Y-%m-%d 2>/dev/null || echo "$COMMIT_DATE")"
VITEPRESS_CONFIG="docs/.vitepress/config.mts"

TAG="$TAG" CHANGELOG_DATE="$CHANGELOG_DATE" VITEPRESS_CONFIG="$VITEPRESS_CONFIG" \
node - <<'NODE'
const fs = require('fs');
const tag = process.env.TAG;
const date = process.env.CHANGELOG_DATE;
const configPath = process.env.VITEPRESS_CONFIG;

let content = fs.readFileSync(configPath, 'utf8');

// 检查是否已存在该 tag 的链接
if (content.includes(`'/changelog/${tag}'`)) {
  console.log('  vitepress 侧边栏已包含该版本的链接，跳过');
  process.exit(0);
}

const sidebarLink = `{ text: '${tag} (${date})', link: '/changelog/${tag}' }`;

// 在标记注释行后插入新的侧边栏链接
const markerPattern = /^(\s*\/\/ .*RELEASE-CHANGELOG-ITEMS.*)$/m;
if (markerPattern.test(content)) {
  content = content.replace(markerPattern, `$1\n            ${sidebarLink},`);
  fs.writeFileSync(configPath, content, 'utf8');
  console.log(`  vitepress 侧边栏已更新: ${sidebarLink}`);
} else {
  console.warn('  未找到侧边栏标记注释，请手动更新 vitepress config');
}
NODE

ok "changelog 索引已更新"

# --- 7. 提交 changelog ---
echo ""
info "提交 changelog..."

git add "$CHANGELOG_FILE" "$CHANGELOG_INDEX" "$VITEPRESS_CONFIG"
if git diff --cached --quiet; then
  warn "changelog 无新增变更，跳过提交"
else
  git commit -m "docs(changelog): 添加 ${TAG} 版本发布日志"
fi

# --- 8. 创建/更新 tag ---
CURRENT_COMMIT="$(git rev-parse HEAD)"
COMMIT_DATE="$(git log -1 --format=%cI)"

info "创建 tag: ${TAG} → ${CURRENT_COMMIT:0:8}..."

# 创建带注释的 tag
git tag -a "$TAG" -m "Release ${TAG}

- VS Code upstream: $(node -p "require('./upstream.lock.json').vscode.tag")
- VSCodium release: $(node -p "require('./upstream.lock.json').vscodium.release")
- Build commit: ${CURRENT_COMMIT}
- Build date: ${COMMIT_DATE}
"

ok "tag ${TAG} 已创建"

# --- 9. 推送 ---
echo ""
echo -e "${BOLD}准备推送...${NC}"
echo "  分支: ${CURRENT_BRANCH}"
echo "  tag:  ${TAG}"
echo ""

read -r -p "是否推送到远程仓库？(Y/n): " PUSH_CONFIRM
if [[ "$PUSH_CONFIRM" =~ ^[Nn]$ ]]; then
  info "已跳过推送。你可以稍后手动推送："
  echo "  git push origin ${CURRENT_BRANCH}"
  echo "  git push origin ${TAG}"
  exit 0
fi

# 推送分支
info "推送分支 ${CURRENT_BRANCH}..."
git push origin "$CURRENT_BRANCH"

# 推送 tag（强制覆盖远程旧 tag，如果确认过）
PUSH_FLAGS=""
if $REMOTE_CONFLICT; then
  PUSH_FLAGS="--force"
  info "强制推送 tag ${TAG}..."
else
  info "推送 tag ${TAG}..."
fi
git push origin "$TAG" $PUSH_FLAGS

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ 发布完成！                          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo "  Tag:     ${TAG}"
echo "  Commit:  ${CURRENT_COMMIT:0:8}"
echo "  Changelog: ${CHANGELOG_FILE}"
echo ""
echo "  GitHub Actions 将自动触发构建，"
echo "  构建完成后会在 Release 页面自动附上 changelog。"
echo "  查看 Actions: https://github.com/171h/vscode-magic/actions"
echo ""
