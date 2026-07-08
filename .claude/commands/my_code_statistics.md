---
name: my_code_statistics
description: 统计本次代码提交行数及项目总代码行数
---

请执行以下统计流程：

## 一、本次提交代码行数统计
1. 执行 `git log --oneline -1` 查看最近一次提交
2. 执行 `git diff --stat HEAD~1..HEAD` 统计最近一次提交的增删行数
3. 输出格式：
   ```
   📝 最近提交：[commit hash] [commit message]
   文件变更数：X 个文件
   新增行数：+X 行
   删除行数：-X 行
   净增行数：+X 行
   ```

## 二、项目总代码行数统计
1. 统计规则：统计以下文件类型的行数，排除 `*/build/*`、`*/.idea/*`、`*/.gradle/*`、`*/.claude/*` 目录
   - Kotlin (`.kt`)
   - Java (`.java`)
   - XML (`.xml`)
   - Gradle/KTS (`.gradle`, `.gradle.kts`)
   - AIDL (`.aidl`)
   - ProGuard (`.pro`)
   - Markdown (`.md`)
2. 使用 `find . \( -path '*/build/*' -o -path '*/.idea/*' -o -path '*/.gradle/*' -o -path '*/.claude/*' \) -prune -o -name "*.$pat" -type f -print` 组合命令按文件类型分别统计
3. 输出各类型代码行数及总行数，格式如下：
   ```
   📊 项目总代码行数统计（排除 build/.idea/.gradle/.claude 目录）

   | 文件类型 | 文件数 | 总行数 |
   |---------|-------|-------|
   | Kotlin  | X     | X     |
   | Java    | X     | X     |
   | XML     | X     | X     |
   | Gradle  | X     | X     |
   | AIDL    | X     | X     |
   | ProGuard| X     | X     |
   | Markdown| X     | X     |
   | **总计**| **X** | **X** |
   ```

## 三、统计结果
将上述两部分结果合在一起输出即可。
