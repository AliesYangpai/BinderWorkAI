# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build

```bash
# Sync + assemble all modules
./gradlew assemble

# Build a specific module
./gradlew :module_aidl:assemble
./gradlew :module_server:assembleDebug
./gradlew :module_client:assembleDebug

# Run unit tests (module-level)
./gradlew :module_aidl:test
```

Gradle 9.0, AGP 8.5.0, Kotlin 2.3.0. Configuration cache is enabled (`gradle.properties`). Version catalog at `gradle/libs.versions.toml`.

## Architecture

Three-module Android project demonstrating **AIDL-based IPC via Binder** between two apps.

```
module_aidl (Android Library, package: org.alie.aidl)
    ├── IUserInfoAidlInterface.aidl   — AIDL interface (add, getScore)
    ├── IUserInfo.aidl                — parcelable declaration
    └── IUserInfo.kt                  — @Parcelize data class

module_server (Android App, package: org.alie.server)
    └── RemoteWorkService.kt          — Service that implements Stub, responds to bind action

module_client (Android App, package: org.alie.client)
    └── MainActivity.kt               — Binds to server via implicit intent, calls proxy methods
```

**IPC flow**: Client sends implicit Intent with `action = "org.alie.server.bindserver"` and `setPackage("org.alie.server")` → binds to `RemoteWorkService` → receives `IUserInfoAidlInterface.Stub.asInterface(iBinder)` proxy → calls AIDL methods across processes.

Both apps depend on `module_aidl` via `implementation(project(":module_aidl"))`.

## Key constraints

### `@Parcelize` requires both Kotlin plugins

Any module using `@Parcelize` (including `module_aidl`) must declare **both** plugins in `build.gradle.kts`:

```kotlin
plugins {
    alias(libs.plugins.android.library)   // or android-application
    alias(libs.plugins.kotlin.android)    // Kotlin compiler — required for .kt and @Parcelize
    alias(libs.plugins.kotlin.parcelize)  // Parcelize compiler plugin
}
```

Missing `kotlin-android` → `kotlinx.parcelize` package not on classpath → `Unresolved reference 'parcelize'`.

The version catalog already defines both Kotlin plugins; they just need to be applied.

### AIDL interface implementation must be complete

When adding a method to the `.aidl` interface, every `Stub` implementation must override it. Currently `RemoteWorkService.kt` implements `add()` but **does not override `getScore()`**, which will cause a compile error once `module_aidl` builds successfully.

### `@Parcelize` field types must be AIDL-compatible

`Short` maps to AIDL's `int` (AIDL has no 16-bit integer type). For cross-process parcelables, prefer `Int` for integer fields to avoid surprises.

### Service binding uses package visibility

Android 11+ requires `<queries>` in the client manifest to discover the server package. Already configured in `module_client/src/main/AndroidManifest.xml`:

```xml
<queries>
    <package android:name="org.alie.server"/>
</queries>
```
