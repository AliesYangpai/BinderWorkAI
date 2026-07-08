---
name: my_review
description: Review staged changes for security + style
---

请执行以下流程：
1. `git diff --cached` 抓 staged 的 changes
2. 找：hard-coded secrets、SQL injection、type errors
3. 对应 CLAUDE.md 内的 style 规则检查
4. 输出：PASS / 或 list of 具体要改的点