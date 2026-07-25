#!/bin/bash
# ============================================================
# auto-merge.sh — 30 分钟超时后自动合并 PR
# 由 post-push.sh 通过 nohup 后台进程调度执行
# 参数: $1 = PR_URL, $2 = BRANCH
# ============================================================

set -euo pipefail

PR_URL="$1"
BRANCH="$2"
EMAIL="380821745@qq.com"
DEFAULT_BRANCH="main"

log_info() { echo "[auto-merge] $*"; }

# ---------- 合并后的本地清理 ----------
cleanup_local_branch() {
    local branch="$1"
    log_info "开始本地清理..."

    # 先拉取远端最新，确保获取到合并结果
    git fetch BinderWorkAI "$DEFAULT_BRANCH" 2>/dev/null || git fetch origin "$DEFAULT_BRANCH" 2>/dev/null || true

    # 如果当前就在 feature 分支上，先切到 main
    local current_branch
    current_branch=$(git branch --show-current 2>/dev/null || echo "")
    if [ "$current_branch" = "$branch" ]; then
        log_info "当前在分支 '$branch'，切换到 '$DEFAULT_BRANCH'..."
        git checkout "$DEFAULT_BRANCH" 2>/dev/null || git checkout -b "$DEFAULT_BRANCH" 2>/dev/null || {
            log_info "无法切换到 $DEFAULT_BRANCH，跳过本地分支删除"
            return 1
        }
    fi

    # 删除本地 feature 分支（如果存在）
    if git show-ref --verify --quiet refs/heads/"$branch"; then
        git branch -d "$branch" 2>/dev/null && log_info "本地分支 '$branch' 已删除" || {
            log_info "本地分支 '$branch' 删除失败，尝试强制删除..."
            git branch -D "$branch" 2>/dev/null && log_info "本地分支 '$branch' 已强制删除" || log_info "无法删除本地分支 '$branch'，请手动处理"
        }
    else
        log_info "本地分支 '$branch' 不存在，无需删除"
    fi

    # 更新 main
    log_info "拉取 '$DEFAULT_BRANCH' 最新代码..."
    git pull BinderWorkAI "$DEFAULT_BRANCH" 2>/dev/null || git pull origin "$DEFAULT_BRANCH" 2>/dev/null || {
        log_info "拉取失败，请手动 git pull"
    }

    log_info "本地已切换到 '$DEFAULT_BRANCH' 并更新到最新"
}

log_info "====== 自动合并检查开始 ======"
log_info "PR: $PR_URL"
log_info "分支: $BRANCH"
log_info "时间: $(date '+%Y-%m-%d %H:%M:%S')"

# ---------- 提取 PR 编号 ----------
PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$' || echo "")
if [ -z "$PR_NUMBER" ]; then
    log_info "无法从 URL 提取 PR 编号: $PR_URL"
    exit 1
fi

# ---------- 检查 PR 状态 ----------
PR_STATE=$(gh pr view "$PR_NUMBER" --json state --jq '.state' 2>/dev/null || echo "unknown")
log_info "PR #$PR_NUMBER 当前状态: $PR_STATE"

if [ "$PR_STATE" != "OPEN" ]; then
    log_info "PR 已不是 OPEN 状态（当前: $PR_STATE），跳过自动合并"
    exit 0
fi

# ---------- 检查是否已有 review ----------
REVIEWS=$(gh pr view "$PR_NUMBER" --json reviews --jq '.reviews | length' 2>/dev/null || echo "0")
if [ "$REVIEWS" -gt "0" ]; then
    log_info "PR 已有 $REVIEWS 条 review，说明有人工审核，跳过自动合并"
    echo "PR #$PR_NUMBER 已有 $REVIEWS 条 review，跳过自动合并，请手动处理。" | \
        msmtp -a qq "$EMAIL"
    exit 0
fi

# ---------- 执行自动合并 ----------
log_info "30 分钟已过且无人工审核，执行自动合并..."
MERGE_RESULT=$(gh pr merge "$PR_NUMBER" --merge --delete-branch 2>&1)
MERGE_EXIT=$?

if [ $MERGE_EXIT -eq 0 ]; then
    # 合并成功 → 清理本地分支 + 切回 main + 拉取最新
    cleanup_local_branch "$BRANCH"

    # 发送通知邮件
    {
        echo "Subject: [BinderWorkAI] PR 已自动合并 ✅"
        echo ""
        echo "以下 PR 在 30 分钟内无人工审核，已自动合并："
        echo ""
        echo "  PR: $PR_URL"
        echo "  分支: $BRANCH"
        echo "  合并策略: --merge"
        echo "  合并时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        echo "本地分支 '$BRANCH' 已删除，当前已切换到 '$DEFAULT_BRANCH'"
        echo ""
        echo "---"
        echo "🤖 由 BinderWorkAI 自动合并"
    } | msmtp -a qq "$EMAIL"
    log_info "PR #$PR_NUMBER 自动合并成功，本地已清理，邮件已发送"
else
    # 合并失败，发送告警邮件
    {
        echo "Subject: [BinderWorkAI] PR 自动合并失败 ❌"
        echo ""
        echo "以下 PR 自动合并失败，请手动处理："
        echo ""
        echo "  PR: $PR_URL"
        echo "  分支: $BRANCH"
        echo "  失败原因: $MERGE_RESULT"
        echo ""
        echo "---"
        echo "🤖 由 BinderWorkAI 自动合并"
    } | msmtp -a qq "$EMAIL"
    log_info "PR #$PR_NUMBER 自动合并失败: $MERGE_RESULT"
    exit 1
fi
