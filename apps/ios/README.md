# Neurun iOS 开发与交付

## 第一次打开项目

工程使用 Swift 6、SwiftUI 和 iPhone 目标，最低系统暂定 iOS 17。Xcode 版本由仓库根目录的 `.xcode-version` 固定，当前为 26.6。CI 在 GitHub 的 `macos-26-intel` runner 上运行 iOS 26.5 的 iPhone 17 模拟器，验证和发行作业使用同版 Xcode。

1. 从 [Apple Developer Downloads](https://developer.apple.com/download/all/?q=Xcode%2026.6) 下载完整 Xcode。Apple Silicon 选 Apple silicon 包。解压后将应用命名为 `Xcode_26.6.app` 并放到 `/Applications`。
2. 打开该版本 Xcode，完成许可和首次组件安装。在 **Xcode → Settings → Components** 安装 iOS 26.5 Simulator Runtime。
3. 在仓库根目录运行 `make ios-doctor`，确认 Xcode 版本、`Neurun` 共享 Scheme、iOS SDK 和可用的 iPhone 17 模拟器。Xcode 位于其他路径时可在当前终端指定 `DEVELOPER_DIR`，例如 `export DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer`。

没有第三方依赖或工程生成步骤。Xcode 的项目文件和共享 Scheme 直接纳入版本控制。

## 开发、断点与构建

用 `make ios-open` 打开工程，在对应的 Xcode 中选择 **Neurun → iPhone 17 (iOS 26.5)**。在 `ContentView.swift` 的 `body` 内设置断点，按 **⌘R** 启动，命中后继续执行并确认显示 `Hello, world!`。按 **⌘U** 运行启动测试，失败截图和日志在 Test Report 中查看。

| 仓库根目录命令 | 预期结果 |
| --- | --- |
| `make ios-build` | Debug 模拟器构建通过 |
| `make ios-test` | XCUITest 启动应用并检查首屏文本 |
| `make ios-archive` | 生成含 `Neurun.app` 的无签名 Release `.xcarchive` |
| `IOS_DESTINATION='platform=iOS Simulator,id=<UDID>' make ios-test` | 使用指定的本地模拟器 |

每次执行会打印对应产物目录。默认保存在 `.build/ios/`，测试和归档同时生成 `.xcresult`，可在 Xcode 中打开。模拟器构建、测试和无签名归档均无需 Apple 开发者证书。

真机调试时，在 Xcode 登录开发团队账号，复制 `Config/Local.xcconfig.example` 为同目录的 `Local.xcconfig`，填入 Team ID 和团队下唯一的开发 Bundle ID。连接 iPhone，开启设备的 Developer Mode，在 Xcode 选择该设备并按 **⌘R**。本地使用 Xcode 自动开发签名，发布 Bundle ID 由 GitHub Environment 提供。

## PR 与合并

PR 和推送到 `main` 时，iOS 工程、工具链、脚本或对应 workflow 的变化会触发 **iOS CI**。检查使用和本地相同的 `ios-test`、`ios-archive` 命令，无需发布密钥。检查日志和 `.xcresult` 保留 14 天。也可从 Actions 手动运行 CI。纯其他模块变更会跳过该工作流，使用分支保护时需考虑 GitHub 对路径过滤与必需检查的行为。

## 第一次接入 TestFlight

在 Apple Developer 注册正式 Bundle ID，创建 App Store Connect iOS 应用记录。为该 Bundle ID 生成 **App Store Connect** provisioning profile，选择与发行 P12 匹配的 **Apple Distribution** 证书。上传使用具备构建上传权限的 App Store Connect Team API Key。

在 GitHub 仓库 **Settings → Environments** 创建 `testflight`。Deployment branches 仅允许默认分支，并按团队要求配置审批。只有签名发布 job 使用该 Environment。

| 类型 | 名称 | 内容 |
| --- | --- | --- |
| Variable | `IOS_RELEASE_BUNDLE_ID` | 正式 Bundle ID |
| Variable | `IOS_TEAM_ID` | Apple Developer Team ID |
| Secret | `IOS_CERTIFICATE_BASE64` | 带私钥的 Apple Distribution `.p12` 的 Base64 |
| Secret | `IOS_CERTIFICATE_PASSWORD` | P12 导出密码 |
| Secret | `IOS_PROFILE_BASE64` | App Store Connect `.mobileprovision` 的 Base64 |
| Secret | `ASC_KEY_ID` | App Store Connect Team API Key ID |
| Secret | `ASC_ISSUER_ID` | App Store Connect API Issuer ID |
| Secret | `ASC_KEY_BASE64` | Team API Key `.p8` 的 Base64 |

在本机可用 `base64 -i /path/to/file | pbcopy` 将文件编码后粘贴到对应 Secret。签名作业使用临时钥匙串和 provisioning profile，结束时清理。普通 CI、仓库文件和构建产物都无需包含这些凭据。

## 签名、上传与上线

1. 在 `Config/App.xcconfig` 维护 `MARKETING_VERSION`。发布流水线依据 GitHub workflow 运行号和尝试次数生成递增的构建号。使用已有 App Store Connect 应用时，先核对当前版本的最高构建号。
2. 在默认分支打开 **Actions → iOS TestFlight → Run workflow**。保持 `upload` 未选中可先验证签名、归档和 IPA 导出。此步骤只需发行证书与 profile。
3. 选中 `upload` 再运行，工作流对所选提交先跑模拟器测试与无签名归档，通过后签名导出，再把 IPA 上传到 App Store Connect。运行摘要及 90 天留存的产物记录提交、版本、构建号和 Xcode 版本，并包含 dSYM。
4. 在 App Store Connect 的 **TestFlight** 中找到同一构建号，等 Apple 处理完成后加入内部测试组。用真机安装并确认首屏。签名导出成功、上传被接受和 TestFlight 可安装是三个独立状态。
5. 正式上线时，在 App Store Connect 选择已经在 TestFlight 验证的同一构建，完成商店资料、合规声明和审核，再按需要分批发布更新。流水线的上传动作只把构建交给 Apple 处理。

失败时先查看对应 job 的原始 Xcode 输出。签名问题按团队、Bundle ID、证书指纹和 profile 到期时间排查。上传超时先到 App Store Connect 核对原构建是否已收到，再决定是否重跑。重跑会分配新的构建号，GitHub 会取消超出同一发布并发组排队容量的旧等待项。

参考 [Apple 上传构建](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)、[Xcode 系统要求](https://developer.apple.com/xcode/system-requirements)、[GitHub macOS 26 Intel runner 软件清单](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md)。
