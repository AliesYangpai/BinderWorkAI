---
name: pr-notifier
description: >
  管理 PR 自动通知和定时合并流水线。当用户提到推送代码、创建 PR、邮件通知、
  自动合并、PR 审核流程、定时合并、或者需要修改自动合并策略时使用此 skill。
  当用户询问"这个 PR 会不会自动合并"或"30 分钟后会怎样"时也要用。
---

# PR 通知与自动合并流水线

本 skill 管理 BinderWorkAI 项目的 PR 生命周期自动化。分为两个阶段：

1. **即时通知** — push 代码 → 自动创建 PR → 发送邮件
2. **定时合并** — 后台等待 30 分钟 → 检查是否有人工审核 → 无人审核则自动 merge

## 流水线架构

```
git push
  ↓ (hook: PostToolUse → Bash → post-push.sh)
自动创建 PR (gh pr create)
  ↓
发送邮件通知 (msmtp → QQ邮箱 380821745@qq.com)
  ↓
启动后台定时器 (nohup sleep 1800s → auto-merge.sh)
  ↓
等待 30 分钟...
  ↓
检查 PR review 状态
  ├── 有 review → 跳过自动合并，发邮件通知手动处理
  └── 无 review → gh pr merge --merge --delete-branch
                     ├── 成功 → 发邮件通知合并完成
                     └── 失败 → 发邮件告警
```

## 关键文件

| 文件 | 作用 |
|------|------|
| `.claude/hooks/post-push.sh` | push 后入口：创建 PR、发邮件、启动定时器 |
| `.claude/hooks/auto-merge.sh` | 30 分钟后执行：检查 review 并决定是否合并 |
| `~/.msmtprc` | SMTP 配置（QQ 邮箱，密码从 Keychain 读取） |
| `.claude/settings.json` | Hook 注册：`PostToolUse` → `Bash` 触发 post-push.sh |

## 配置参数

修改 `post-push.sh` 中的变量可调整行为：

- **EMAIL** (`380821745@qq.com`) — 通知邮件的接收邮箱
- **DELAY_SECONDS** (`1800`) — 等待自动合并的秒数（30 分钟）
- **合并策略** — `auto-merge.sh` 中 `gh pr merge` 的 `--merge` 标志，可改为 `--squash` 或 `--rebase`

## 手动测试

### 测试邮件发送
```bash
echo "测试内容" | msmtp 380821745@qq.com
```

### 手动触发 auto-merge（指定 PR 编号）
```bash
bash .claude/hooks/auto-merge.sh "https://github.com/AliesYangpai/BinderWorkAI/pull/12" "feature_xxx"
```

### 查看后台定时器
```bash
ps aux | grep 'sleep 1800' | grep -v grep
```

### 取消某个定时器
```bash
kill <PID>
```

## SMTP 故障排除

如邮件未发送，检查：
1. Keychain 授权码是否正确：`security find-generic-password -a 380821745 -s qq-smtp -w`
2. msmtp 日志：`tail -50 ~/.msmtp.log`
3. QQ 邮箱是否开启了 SMTP 服务（需去 QQ 邮箱设置中确认）

## 自动合并的安全机制

自动合并在以下情况**不会**执行：
- PR 已有关闭/合并状态（不是 OPEN）
- PR 已有至少 1 条 human review
- `gh` CLI 未登录或权限不足

这确保了自动合并不会绕过人工审核——它只在你真的忘了的时候救场。
