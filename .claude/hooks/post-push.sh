#!/bin/bash
# ============================================================
# post-push.sh — git push 后自动创建 GitHub PR
# 在 git push 完成后自动运行，用于：
#   1. 跳过默认分支（main/master）的 push
#   2. 检测是否已有同名 PR，避免重复创建
#   3. 自动创建 PR 并输出链接
# ============================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
log_skip() { echo -e "${YELLOW}[SKIP]${NC} $*"; }

# ---------- 获取当前分支 ----------
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")

# ---------- 默认分支跳过 ----------
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
    log_skip "当前分支为 '$BRANCH'，不创建 PR"
    exit 0
fi

# ---------- 检查是否已有同名 PR ----------
EXISTING_PR=$(gh pr list --head "$BRANCH" --state open --json number --jq '.[0].number' 2>/dev/null || echo "")

if [ -n "$EXISTING_PR" ]; then
    PR_URL=$(gh pr view "$EXISTING_PR" --json url --jq '.url' 2>/dev/null || echo "")
    log_info "分支 '$BRANCH' 已有打开的 PR: $PR_URL"
    exit 0
fi

# ---------- 提取提交信息 ----------
COMMIT_TITLE=$(git log -1 --pretty=%B | head -1)
COMMIT_BODY=$(git log -1 --pretty=%B | tail -n +2)

# ---------- 构建 PR 描述 ----------
PR_BODY="## 变更说明

$COMMIT_BODY

### 变更文件

\`\`\`
$(git diff --stat origin/main...HEAD 2>/dev/null || git diff --stat origin/master...HEAD 2>/dev/null || echo "无法获取 diff")
\`\`\`

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)"

# ---------- 创建 PR ----------
log_info "正在为分支 '$BRANCH' 创建 PR..."

# 检测默认分支
DEFAULT_BRANCH="main"
if git show-ref --verify --quiet refs/remotes/origin/master; then
    DEFAULT_BRANCH="master"
fi

PR_URL=$(gh pr create \
    --title "$COMMIT_TITLE" \
    --body "$PR_BODY" \
    --base "$DEFAULT_BRANCH" \
    --head "$BRANCH" \
    2>&1)

if [ $? -eq 0 ]; then
    log_ok "PR 创建成功！"
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Pull Request 已创建${NC}"
    echo -e "${GREEN}  $PR_URL${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
else
    log_info "PR 创建失败: $PR_URL"
    exit 1
fi
