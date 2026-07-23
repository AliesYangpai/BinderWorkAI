# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 角色与行为
- 你是一个拥有 10 年 Android 开发经验的专家，主攻应用层 App 开发。
- 编码前，先通读项目结构、模块依赖关系和业务逻辑。
- 分步骤分析问题，结论要有据可依。不知道就说不知道。

## 分支与提交规范
- 工作前，先更新本地默认分支并拉取最新代码，再基于当前分支创建新分支：`feature_xxx`
- 编码完成后需要验证，验证通过后提交并推送。
- 提交信息模板：`Claude完成了xxx任务，分别为。。。`
- 每条提交信息末尾加上：`Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- 合并完成后，自动删除当前分支（远端和本地）并切换到默认分支

## 构建与测试命令
```bash
# 构建整个项目
./gradlew build

# 按模块构建
./gradlew :module_client:assembleDebug
./gradlew :module_server:assembleDebug
./gradlew :module_aidl:assembleDebug

# 运行单元测试（JVM，无需设备）
./gradlew test
./gradlew :module_aidl:test

# 运行仪器化测试（需要连接设备或模拟器）
./gradlew connectedAndroidTest

# 清理构建产物
./gradlew clean
```

## 项目架构

这是一个 **Android AIDL IPC 演示项目**，包含三个模块，演示两个 Android 应用之间通过 AIDL（Android 接口定义语言）进行跨进程通信。

### 模块依赖关系
```
module_client (android-app) ──依赖──▶ module_aidl (android-library)
module_server (android-app) ──依赖──▶ module_aidl (android-library)
```

### 模块说明

**`module_aidl`**（library, `org.alie.aidl`）
- 共享契约层，两个应用都依赖此库。
- 包含 3 个 AIDL 文件，定义 IPC 通信接口：
  - `IUserInfoAidlInterface.aidl` — 核心 RPC 方法：`add()`、`getScore()`、`getNewScore()`、`getUserInfoList()`、`workToGetUserInfoList()`、`requestUsers()`（单向）、`requestUsersflow()`（单向）、`cancelRequestUsersflow()`（单向）
  - `IUserInfo.aidl` — `IUserInfo` 数据类的 Parcelable 声明
  - `ICommonCallback.aidl` — 回调接口（`onSuccess`、`onFail`），用于服务端到客户端的异步/流式回复
- `IUserInfo.kt` — Kotlin `@Parcelable` 数据类（`name: String, age: Int, introduction: String`）

**`module_server`**（app, `org.alie.server`）
- 承载 `RemoteWorkService`，一个导出的 `Service`（intent-filter：`org.alie.server.bindserver`）。
- `RemoteWorkService.onBind()` 返回 `IUserInfoAidlInterface.Stub` 的实现。
- Stub 在服务端线程池中处理所有 AIDL 方法调用。
- 使用 `CoroutineScope(IO + SupervisorJob)` 管理异步任务；`ConcurrentHashMap` 跟踪可取消的回调任务。

**`module_client`**（app, `org.alie.client`）
- `MainActivity` 通过指向 `org.alie.server` 的显式 `Intent` 绑定服务端的 `RemoteWorkService`。
- 在 `onServiceConnected` 中通过 `Stub.asInterface(iBinder)` 获取 `IUserInfoAidlInterface` 代理。
- 通过按钮（btn1–btn12）演示多种 IPC 模式：
  - **btn1**：绑定远程服务
  - **btn2**：`add(a, b)` — 基本类型的同步 RPC 调用
  - **btn3**：`getScore(IUserInfo)` — 向服务端传递 Parcelable 对象
  - **btn4**：`getNewScore(List<IUserInfo>)` — 传递 Parcelable 列表
  - **btn5**：`getUserInfoList()` — 从服务端接收 Parcelable 列表
  - **btn6**：`workToGetUserInfoList(callback)` — 同步回调模式
  - **btn7**：`requestUsers(user, callback)` — 单向异步回调
  - **btn8**：`requestUsersflow` / `cancelRequestUsersflow` — 回调转换为 Kotlin `callbackFlow {}`，展示基于 Flow 的生命周期安全异步 IPC，支持缓冲与取消
  - **btn9–btn12**：占位按钮（仅打日志）
- 使用 `viewBinding` 访问布局（`ActivityMainBinding`）。

### IPC 通信流程
1. 服务端启动 `RemoteWorkService`（由 `BIND_AUTO_CREATE` 触发）。
2. 客户端调用 `bindService()` → 在 `onServiceConnected` 中收到 `IBinder`。
3. 客户端获取 `IUserInfoAidlInterface` 代理，像调用本地方法一样调用远程方法。
4. AIDL 运行时通过 Binder IPC 边界编组传输参数。
5. 服务端 Stub 执行方法，返回结果（或通过 `ICommonCallback` 回调客户端）。

## 关键技术参数
- **AGP**：9.2.1（Android Gradle Plugin）
- **Kotlin**：通过 version catalog 管理，代码风格 = `official`
- **compileSdk**：36（API 级别 Baklava），**minSdk**：26，**targetSdk**：36
- **Java 目标版本**：11
- **构建系统**：Gradle，version catalog 位于 `gradle/libs.versions.toml`
- **Gradle 配置**：已开启 Configuration Cache；并行模式已注释；JVM 堆内存 2048m
- AIDL 支持需按模块显式开启：`buildFeatures { aidl = true }`
- 客户端需在 AndroidManifest 中声明 `<queries>` 才能在 Android 11+ 上发现服务端包

## 代码风格规范

### Kotlin
- 遵循 Kotlin 官方编码规范（`codeStyle = official`）。
- 优先使用 `?.let {}`、`requireNotNull()` 或 `?:` Elvis 操作符处理可空类型，**避免使用 `!!` 强制非空断言**，除非在测试代码或已绝对确定非空的上下文。
- 函数参数和返回值尽量使用不可变类型（`List` 而非 `MutableList`），除非调用方确实需要可变性。
- 使用 `when` 表达式代替冗长的 `if-else` 链。

### 异常处理
- **catch 块不得为空**。捕获异常后至少使用 `android.util.Log.e()` 记录日志，包含异常对象作为第二个参数。
- 使用 `runCatching { ... }` 或 `try/catch` 包裹可能抛出异常的 Binder 调用（如 `RemoteException`、`DeadObjectException`）。

### 日志
- 使用 `android.util.Log`，tag 格式为 `类名::class.java.toString()`，如下所示：
  ```kotlin
  object {
      private val TAG = RemoteWorkService::class.java.toString()
  }
  ```

### 协程
- **服务端后台任务**：使用 `CoroutineScope(Dispatchers.IO + SupervisorJob())`，在 Service 销毁时调用 `scope.cancel()` 清理。
- **客户端 UI 层**：使用 `lifecycleScope` 或 `viewModelScope` 管理协程生命周期。
- 回调转 Flow：使用 `callbackFlow<T> { ... }` + `awaitClose { }` 模式，在 `awaitClose` 中调用取消方法清理服务端资源。

### AIDL
- 无需返回值的方法使用 `oneway` 修饰，避免阻塞调用线程。
- 同步方法直接返回结果，不使用 `oneway`。
- 接口方法参数中如有回调接口（如 `ICommonCallback`），回调接口中的方法也应是 `oneway`。
- 修改 AIDL 文件后执行 `./gradlew clean :module_aidl:build` 强制重新生成 Stub 代码。

## `.claude/` 配置目录说明

本项目 `.claude/` 目录下的配置文件按职责划分：

| 文件 | 类型 | 作用 |
|------|------|------|
| `settings.json` | **Hook 配置** | 注册 Claude Code 层面的自动化 hook（如 git commit 后触发 post-review） |
| `settings.local.json` | **本地配置** | 开发者本地的权限和个人偏好设置，不提交到仓库 |
| `hooks/pre-commit.sh` | **Shell 脚本（Hook 实现）** | Git 提交前自动检查：敏感文件拦截、AIDL/Parcelable 配对、Kotlin 编译、调试代码残留、单元测试 |
| `hooks/post-review.sh` | **Shell 脚本（Hook 实现）** | 代码审查后处理：硬编码密钥扫描、AIDL oneway 语义检查、空安全分析、构建验证、审查报告归档与趋势对比 |
| `commands/*.md` | **斜杠命令（Command）** | 定义可通过 `/` 调用的自定义命令（如 `/code-review`），包含审查维度和输出格式模板 |
| `skills/project-specific/SKILL.md` | **项目技能（Skill）** | 本项目专属的开发引导：AIDL 新增四步法、协程封装模式、按钮添加规范、构建验证流程 |
| `review-logs/` | **日志目录** | 存放 post-review 自动生成的审查报告（`review-*.md`）和待办清单（`TODO-*.md`） |

> **Hook vs Skill vs Command vs CLAUDE.md 的区别**：
> - **Hook** — 由 Claude Code runtime 或 Git 在特定事件时**自动触发**执行脚本，无需用户手动调用
> - **Skill** — 由用户通过 `/skill-name` 或 Claude 自动识别场景后**按需加载**，提供领域知识和工作流引导
> - **Command** — 用户通过 `/command-name` **手动调用**的斜杠命令，本质是预定义的提示词模板
> - **CLAUDE.md** — 每次对话**自动注入**上下文的项目指令文件，是 Claude 了解项目的第一手资料
