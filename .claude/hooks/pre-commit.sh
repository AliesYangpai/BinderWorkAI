#!/bin/bash
# ============================================================
# pre-commit.sh — Git 提交前自动检查脚本
# ============================================================
# 运行时机:
#   由 .git/hooks/pre-commit 触发，在 git commit 执行前自动运行。
#   只检查当前 git add 暂存区中的变更文件，无暂存文件时直接跳过。
#
# 检查项:
#   敏感文件检查                                              [阻塞]
#     拦截以下文件被误提交到版本库:
#       - local.properties  (含本地 SDK 路径等敏感信息)
#       - .keystore / .jks  (签名密钥文件)
#       - 路径或文件名含 secret / credentials 的文件
#     违规时打印具体文件路径和移除指令。
#
# 使用方式:
#   自动:    git commit 时由 Git Hook 自动调用
#   手动:    bash .claude/hooks/pre-commit.sh
#   跳过:    git commit --no-verify
#
# 退出码:
#   0 — 检查通过（或跳过），允许提交
#   1 — 检查未通过，提交被阻止
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_pass()  { echo -e "${GREEN}[PASS]${NC} $*"; }
log_fail()  { echo -e "${RED}[FAIL]${NC} $*"; }
log_info()  { echo -e "[INFO] $*"; }

# ---------- 获取变更文件列表 ----------
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)
STAGED_ALL=$(git diff --cached --name-only 2>/dev/null || true)

if [ -z "$STAGED_FILES" ]; then
    log_info "没有暂存的文件，跳过检查"
    exit 0
fi

echo ""
echo "=========================================="
echo "  Pre-commit 检查开始"
echo "=========================================="
echo ""

# ======================
# 敏感文件检查
# ======================
log_info "敏感文件检查..."

if echo "$STAGED_ALL" | grep -qE '(local\.properties|\.keystore|\.jks|secret|credentials)' 2>/dev/null; then
    DANGER_FILES=$(echo "$STAGED_ALL" | grep -E '(local\.properties|\.keystore|\.jks|secret|credentials)')
    log_fail "检测到敏感文件被暂存: $DANGER_FILES"
    echo "  请从暂存区移除: git reset HEAD <file>"
    echo ""
    echo "=========================================="
    echo "  Pre-commit 检查结果: 1 失败"
    echo "=========================================="
    echo -e "${RED}提交被阻止，请修复以上失败项后重试${NC}"
    exit 1
else
    log_pass "未发现敏感文件"
    echo ""
    echo "=========================================="
    echo "  Pre-commit 检查结果: 通过"
    echo "=========================================="
    echo -e "${GREEN}检查通过，允许提交${NC}"
    exit 0
fi
