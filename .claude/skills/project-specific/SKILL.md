---
name: binderwork-ai-guide
description: BinderWorkAI 项目开发引导 — AIDL 接口新增、协程封装、模块创建等场景的约定步骤，确保代码风格与项目一致。
---

# BinderWorkAI 项目开发引导

当用户在本项目中进行以下操作时，遵循本 skill 的约定。

## 1. 新增 AIDL 接口

当用户需要新增跨进程通信接口（AIDL method）或新增 Parcelable 类型时，按以下步骤进行：

1. **定义 AIDL**：在 `module_aidl/src/main/aidl/org/alie/aidl/` 下创建或修改 `.aidl` 文件，声明接口方法或 parcelable 类型。
2. **Parcelable 实现**：若新增了 parcelable 声明，必须在 `module_aidl/src/main/java/org/alie/aidl/` 下创建同名的 Kotlin 数据类，实现 `android.os.Parcelable` 接口（参考 `IUserInfo.kt`）。
3. **服务端 Stub 实现**：在 `module_server/src/main/java/org/alie/server/RemoteWorkService.kt` 的 `onBind()` 返回的 `IUserInfoAidlInterface.Stub()` 匿名实现中，添加新方法的逻辑。
4. **客户端调用**：在 `module_client/src/main/java/org/alie/client/MainActivity.kt` 中添加对应的按钮和调用演示。
5. **构建验证**：修改 AIDL 后必须执行 `./gradlew clean :module_aidl:build` 刷新 AIDL 生成代码，再执行 `./gradlew :module_aidl:test` 确保通过。

## 2. 协程封装 oneway 回调

当需要将 AIDL 的 `oneway` 异步回调方法封装为 Kotlin Flow 时，参考 `btn8`（`requestUsersflow`）的模式：

- 使用 `callbackFlow<T> { ... }` 构建器。
- 在 `callbackFlow` lambda 内，创建 `ICommonCallback.Stub()` 匿名对象，在 `onSuccess` 中调用 `trySend(data)`，在 `onFail` 中调用 `close(cause)`。
- 调用 AIDL 的 oneway 方法，传入 callback 对象。
- 在 `awaitClose { }` 块中调用对应的 `cancelXxx` 方法清理服务端资源。
- 收集 Flow 时使用 `flowOn(Dispatchers.IO)` 确保在后台线程执行。

## 3. 新增按钮功能

- 按钮 ID 按序递增（btn9 → btn10 → ...），在布局 XML 中定义，在 `MainActivity.kt` 中通过 `ActivityMainBinding` 访问。
- 每个按钮的功能实现遵循现有模式：`binding.btnX.setOnClickListener { ... }`。
- 使用 `android.util.Log` 输出日志，tag 格式为 `MainActivity::class.java.toString()` 或直接使用类名常量。

## 4. 代码风格约定

- **Kotlin**：遵循 Kotlin 官方编码规范，优先使用 `?.let{}` 或 `requireNotNull` 代替 `!!` 强制非空断言。
- **异常处理**：catch 块不得为空，至少记录日志。
- **协程**：服务端使用 `CoroutineScope(Dispatchers.IO + SupervisorJob())` 管理后台任务。
- **AIDL 方法修饰**：无需返回值的异步调用使用 `oneway` 修饰，需要同步返回结果的方法不加 `oneway`。

## 5. 构建与测试

- 修改 AIDL 文件后：`./gradlew clean :module_aidl:build`。
- 验证单个模块测试：`./gradlew :module_<name>:test`。
- 部署验证：先安装 `module_server`，再安装 `module_client`。
