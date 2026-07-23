#!/bin/bash
# ============================================================
# post-review.sh — 代码审查后处理脚本
# 在代码审查命令(/code-review)执行完成后自动运行，用于：
#   1. 收集并归档审查结果
#   2. 分类统计问题（阻塞/建议/表扬）
#   3. 检查高优先级修复项是否已处理
#   4. 针对本项目的专项验证
#   5. 阻塞项拦截（可用于 CI 流程）
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

PASS=0
FAIL=0
WARN=0

log_pass()  { echo -e "${GREEN}[PASS]${NC} $*"; ((++PASS)); }
log_fail()  { echo -e "${RED}[FAIL]${NC} $*"; ((++FAIL)); }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; ((++WARN)); }
log_info()  { echo -e "${CYAN}[INFO]${NC} $*"; }

# ---------- 配置 ----------
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REVIEW_LOG_DIR="$PROJECT_ROOT/.claude/review-logs"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
REVIEW_LOG="$REVIEW_LOG_DIR/review-${TIMESTAMP}-${BRANCH}.md"
TODO_FILE="$REVIEW_LOG_DIR/TODO-${BRANCH}.md"

# 变量初始化（满足 set -u 要求）
BLOCKING_ITEMS=0
SUGGESTION_ITEMS=0
PRAISE_COUNT=0
CHANGED_KOTLIN=""
CHANGED_AIDL=""
CHANGED_MANIFEST=""
CHANGED_BUILD=""
CHANGED_MODULES=""
CHANGED_FILES=""

mkdir -p "$REVIEW_LOG_DIR"

# ---------- 读取审查输入 ----------
# 优先从 stdin 读取（管道传入），其次从命令行参数指定的文件读取
REVIEW_INPUT=""
if [ ! -t 0 ]; then
    REVIEW_INPUT=$(cat)
elif [ -n "${1:-}" ] && [ -f "$1" ]; then
    REVIEW_INPUT=$(cat "$1")
fi

echo ""
echo "=========================================="
echo "  Post-Review 后处理开始"
echo "=========================================="
log_info "分支: $BRANCH"
log_info "时间: $TIMESTAMP"
log_info "项目: BinderWorkAI (Android AIDL)"

# ======================
# 1. 审查结果分类统计
# ======================
echo ""
log_info "1/8 审查结果分类统计..."

if [ -n "$REVIEW_INPUT" ]; then
    BLOCKING_ITEMS=$(echo "$REVIEW_INPUT" | sed -n '/### 必须修改/,/### 建议修改/p' | sed '1d;$d' | grep -cE '^\s*-\s+\[' 2>/dev/null) || BLOCKING_ITEMS=0
    SUGGESTION_ITEMS=$(echo "$REVIEW_INPUT" | sed -n '/### 建议修改/,/### 表扬/p' | sed '1d;$d' | grep -cE '^\s*-\s+\[' 2>/dev/null) || SUGGESTION_ITEMS=0
    PRAISE_COUNT=$(echo "$REVIEW_INPUT" | grep -cE '### 表扬|Praise' 2>/dev/null) || PRAISE_COUNT=0

    log_pass "审查输入已读取 ($(echo "$REVIEW_INPUT" | wc -c | tr -d '\n\r[:space:]') 字符)"
    log_info "  阻塞项: $BLOCKING_ITEMS | 建议项: $SUGGESTION_ITEMS | 表扬: $PRAISE_COUNT"
else
    log_info "无审查输入（stdin 为空），跳过统计"
fi

# ======================
# 2. 变更文件专项风险扫描
# ======================
echo ""
log_info "2/8 变更文件风险扫描..."

# 获取本次涉及的所有变更文件
CHANGED_FILES=$(git diff --name-only HEAD 2>/dev/null || git diff --name-only --cached 2>/dev/null || true)

if [ -n "$CHANGED_FILES" ]; then
    CHANGED_KOTLIN=$(echo "$CHANGED_FILES" | grep '\.kt$' || true)
    CHANGED_AIDL=$(echo "$CHANGED_FILES" | grep '\.aidl$' || true)
    CHANGED_MANIFEST=$(echo "$CHANGED_FILES" | grep 'AndroidManifest\.xml$' || true)
    CHANGED_BUILD=$(echo "$CHANGED_FILES" | grep 'build\.gradle\.kts$' || true)
    CHANGED_MODULES=$(echo "$CHANGED_FILES" | grep -oE '^module_[^/]+' | sort -u || true)

    # 2a. 硬编码密钥/Token 检查
    log_info "  2a. 硬编码密钥检查..."
    SECRET_FOUND=false
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        if grep -nE '(api[_-]?key|token|secret|password|private_key|access_key)\s*=\s*"[^"]{8,}"' "$file" 2>/dev/null; then
            SECRET_FOUND=true
        fi
    done <<< "$CHANGED_FILES"

    if [ "$SECRET_FOUND" = true ]; then
        log_fail "检测到疑似硬编码密钥/Token，请立即移除并改用环境变量或密钥管理服务"
    else
        log_pass "未发现硬编码密钥"
    fi

    # 2b. AIDL oneway 语义检查
    if [ -n "$CHANGED_AIDL" ]; then
        log_info "  2b. AIDL oneway 语义检查..."
        ONEWAY_COUNT=0
        while IFS= read -r aidl_file; do
            [ -z "$aidl_file" ] && continue
            ONEWAY_METHODS=$(grep -c '^\s*oneway\s' "$aidl_file" 2>/dev/null || echo 0)
            if [ "$ONEWAY_METHODS" -gt 0 ]; then
                ONEWAY_COUNT=$((ONEWAY_COUNT + ONEWAY_METHODS))
                log_info "    ${aidl_file}: ${ONEWAY_METHODS} 个 oneway 方法"
            fi
        done <<< "$CHANGED_AIDL"

        if [ "$ONEWAY_COUNT" -gt 0 ]; then
            log_warn "共 ${ONEWAY_COUNT} 个 oneway 方法，确认客户端无返回值依赖"
        else
            log_pass "无新增 oneway 方法"
        fi
    fi

    # 2c. Kotlin 空安全 / 异常处理检查
    if [ -n "$CHANGED_KOTLIN" ]; then
        log_info "  2c. Kotlin 空安全与异常处理检查..."
        BANG_COUNT=0
        BARE_CATCH=0
        while IFS= read -r kt_file; do
            [ -z "$kt_file" ] && continue
            bangs=$(grep -c '!!' "$kt_file" 2>/dev/null || echo 0)
            bare_catches=$(grep -cE 'catch\s*\(\s*\)' "$kt_file" 2>/dev/null || echo 0)
            BANG_COUNT=$((BANG_COUNT + bangs))
            BARE_CATCH=$((BARE_CATCH + bare_catches))
        done <<< "$CHANGED_KOTLIN"

        if [ "$BANG_COUNT" -gt 0 ]; then
            log_warn "发现 ${BANG_COUNT} 处强制非空断言(!!)，建议使用 ?.let{} 或 requireNotNull"
        fi
        if [ "$BARE_CATCH" -gt 0 ]; then
            log_fail "发现 ${BARE_CATCH} 处空 catch 块，必须处理异常或记录日志"
        else
            log_pass "空安全检查通过"
        fi
    fi
else
    log_info "无变更文件，跳过风险扫描"
fi

# ======================
# 3. Manifest 与包可见性检查
# ======================
echo ""
log_info "3/8 Manifest 与包可见性检查..."

if [ -n "$CHANGED_MANIFEST" ]; then
    while IFS= read -r manifest; do
        [ -z "$manifest" ] && continue
        # Android 11+ 包可见性
        if [[ "$manifest" == *"module_client"* ]]; then
            if grep -q '<queries>' "$manifest" 2>/dev/null; then
                log_pass "${manifest}: 已声明 <queries>（Android 11+ 包可见性）"
            else
                log_fail "${manifest}: module_client 缺少 <queries> 声明，Android 11+ 无法解析服务"
            fi
        fi
        # exported 属性
        EXPORTED_SERVICES=$(grep -c 'android:exported="true"' "$manifest" 2>/dev/null || echo 0)
        if [ "$EXPORTED_SERVICES" -gt 0 ]; then
            log_warn "${manifest}: ${EXPORTED_SERVICES} 个 Service exported=true，请确认这是有意为之"
        fi
    done <<< "$CHANGED_MANIFEST"
else
    log_pass "无 Manifest 变更，跳过"
fi

# ======================
# 4. AIDL 接口向后兼容检查
# ======================
echo ""
log_info "4/8 AIDL 接口向后兼容检查..."

if [ -n "$CHANGED_AIDL" ]; then
    while IFS= read -r aidl_file; do
        [ -z "$aidl_file" ] && continue
        # 检查 git diff 中是否移除了已有方法
        REMOVED_METHODS=$(git diff HEAD -- "$aidl_file" 2>/dev/null | grep -E '^\-\s+(oneway\s+)?\w+\s+\w+\(' || true)
        if [ -n "$REMOVED_METHODS" ]; then
            log_fail "${aidl_file}: 检测到方法被移除，这会导致 AIDL 接口不兼容"
            echo "  移除的方法:"
            echo "$REMOVED_METHODS" | sed 's/^/    /'
        else
            log_pass "${aidl_file}: 无方法移除，接口兼容"
        fi

        # 检查新增的 Parcelable 是否有对应 Kotlin 类
        NEW_PARCELABLES=$(git diff HEAD -- "$aidl_file" 2>/dev/null | grep -E '^\+\s*parcelable\s' || true)
        if [ -n "$NEW_PARCELABLES" ]; then
            log_warn "新增 Parcelable 声明，请确认已有对应的 Kotlin Parcelable 实现类"
        fi
    done <<< "$CHANGED_AIDL"
else
    log_pass "无 AIDL 变更，跳过"
fi

# ======================
# 5. 模块构建验证
# ======================
echo ""
log_info "5/8 模块构建验证..."

if [ -n "$CHANGED_MODULES" ]; then
    if [ -n "$CHANGED_AIDL" ]; then
        log_info "  检测到 AIDL 变更，执行 clean + build..."
        if ./gradlew clean :module_aidl:build --quiet 2>&1 | tail -3; then
            log_pass "AIDL 模块 clean build 通过"
        else
            log_fail "AIDL 模块构建失败，请先修复编译错误"
        fi
    fi

    BUILD_FAILED=false
    while IFS= read -r mod; do
        [ -z "$mod" ] && continue
        log_info "  构建检查: :${mod}:assembleDebug ..."
        if ./gradlew ":${mod}:assembleDebug" --quiet 2>&1 | tail -3; then
            log_pass ":${mod} 构建通过"
        else
            log_fail ":${mod} 构建失败"
            BUILD_FAILED=true
        fi
    done <<< "$CHANGED_MODULES"

    if [ "$BUILD_FAILED" = true ]; then
        FAIL=$((FAIL + 1))
    fi
else
    log_pass "无模块变更，跳过构建检查"
fi

# ======================
# 6. 单元测试回归
# ======================
echo ""
log_info "6/8 单元测试回归..."

if [ -n "$CHANGED_MODULES" ]; then
    TEST_FAILED=false
    while IFS= read -r mod; do
        [ -z "$mod" ] && continue
        log_info "  运行测试: :${mod}:testDebugUnitTest ..."
        if ./gradlew ":${mod}:testDebugUnitTest" --quiet 2>&1 | tail -5; then
            log_pass ":${mod} 单元测试通过"
        else
            log_fail ":${mod} 单元测试失败"
            TEST_FAILED=true
        fi
    done <<< "$CHANGED_MODULES"
else
    log_pass "无模块变更，跳过测试"
fi

# ======================
# 7. 生成审查报告与待办
# ======================
echo ""
log_info "7/8 生成审查报告与待办..."

{
    echo "# 代码审查报告 — ${TIMESTAMP}"
    echo ""
    echo "| 项目 | 详情 |"
    echo "|------|------|"
    echo "| 分支 | \`${BRANCH}\` |"
    echo "| 时间 | ${TIMESTAMP} |"
    echo "| 项目 | BinderWorkAI (Android AIDL) |"
    echo ""
    echo "## 审查摘要"
    echo ""
    echo "| 类别 | 数量 |"
    echo "|------|------|"
    echo "| 必须修改 (Blocking) | ${BLOCKING_ITEMS:-0} |"
    echo "| 建议修改 (Suggestion) | ${SUGGESTION_ITEMS:-0} |"
    echo "| 表扬 (Praise) | ${PRAISE_COUNT:-0} |"
    echo ""
    echo "## 变更模块"
    echo ""
    if [ -n "${CHANGED_MODULES:-}" ]; then
        echo "$CHANGED_MODULES" | sed 's/^/- /'
    else
        echo "无"
    fi
    echo ""
    echo "---"
    echo ""
    if [ -n "$REVIEW_INPUT" ]; then
        echo "$REVIEW_INPUT"
    else
        echo "> *(审查内容通过 /code-review 命令输出)*"
    fi
    echo ""
    echo "---"
    echo "*此报告由 post-review.sh hook 自动生成*"
} > "$REVIEW_LOG"
log_pass "审查报告: $REVIEW_LOG"

# 生成待办文件（仅当存在问题项时）
if [ "${BLOCKING_ITEMS:-0}" -gt 0 ] || [ "${SUGGESTION_ITEMS:-0}" -gt 0 ]; then
    # 提取 Blocking 段落正文（去掉标题行和下一段标题行）
    BLOCKING_BODY=$(echo "$REVIEW_INPUT" | sed -n '/### 必须修改/,/### 建议修改/p' | sed '1d;$d' 2>/dev/null || echo "")
    SUGGESTION_BODY=$(echo "$REVIEW_INPUT" | sed -n '/### 建议修改/,/### 表扬/p' | sed '1d;$d' 2>/dev/null || echo "")

    {
        echo "# 审查待办 — 分支 \`${BRANCH}\`"
        echo ""
        echo "> 最近更新: ${TIMESTAMP}"
        echo "> 关联报告: \`$(basename "$REVIEW_LOG")\`"
        echo ""
        echo "## 🔴 必须修改 (Blocking) — ${BLOCKING_ITEMS} 项"
        echo ""
        if [ -n "$BLOCKING_BODY" ]; then
            echo "$BLOCKING_BODY"
        else
            echo "无"
        fi
        echo ""
        echo "## 🟡 建议修改 (Suggestion) — ${SUGGESTION_ITEMS} 项"
        echo ""
        if [ -n "$SUGGESTION_BODY" ]; then
            echo "$SUGGESTION_BODY"
        else
            echo "无"
        fi
        echo ""
        echo "---"
        echo "处理完毕后请删除此文件或标记完成。"
    } > "$TODO_FILE"
    log_pass "待办文件: $TODO_FILE"
else
    log_info "无阻塞/建议项，不生成待办文件"
fi

# ======================
# 8. 前后审查对比
# ======================
echo ""
log_info "8/8 审查趋势对比..."

PREV_REVIEW=$(ls -t "$REVIEW_LOG_DIR"/review-*.md 2>/dev/null | head -2 | tail -1 || true)
if [ -n "$PREV_REVIEW" ] && [ "$PREV_REVIEW" != "$REVIEW_LOG" ]; then
    log_info "上次审查: $(basename "$PREV_REVIEW")"

    # 提取双方摘要行进行对比
    PREV_BLOCK=$(grep -oP '必须修改.*?\|\s*\K\d+' "$PREV_REVIEW" 2>/dev/null || echo "?")
    PREV_SUGG=$(grep -oP '建议修改.*?\|\s*\K\d+' "$PREV_REVIEW" 2>/dev/null || echo "?")
    CURR_BLOCK="${BLOCKING_ITEMS:-0}"
    CURR_SUGG="${SUGGESTION_ITEMS:-0}"

    log_info "  阻塞项: ${PREV_BLOCK} → ${CURR_BLOCK} | 建议项: ${PREV_SUGG} → ${CURR_SUGG}"

    if [ "$CURR_BLOCK" -lt "$PREV_BLOCK" ] 2>/dev/null; then
        log_pass "阻塞项减少，质量趋势向好"
    elif [ "$CURR_BLOCK" -gt "$PREV_BLOCK" ] 2>/dev/null; then
        log_warn "阻塞项增加，请关注代码质量趋势"
    fi
else
    log_info "无历史审查记录，跳过对比"
fi

# ======================
# 结果汇总
# ======================
echo ""
echo "=========================================="
echo "  Post-Review 后处理结果: ${PASS} 通过, ${WARN} 警告, ${FAIL} 失败"
echo "=========================================="

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ⚠️  存在 ${FAIL} 个阻塞问题，请修复后再合并/提交  ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════╝${NC}"
    echo ""
    exit 1
elif [ "$WARN" -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}存在 ${WARN} 个警告项，建议在合并前处理${NC}"
    echo ""
    exit 0
else
    echo ""
    echo -e "${GREEN}全部检查通过，代码审查后处理完成 ✓${NC}"
    echo ""
    exit 0
fi
