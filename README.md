# Neurun

Neurun iOS 目前是一个显示 `Hello, world!` 的 SwiftUI 应用。本阶段用同一个 Xcode 工程串起本地调试、模拟器回归、Release 归档和 TestFlight 交付。

| 入口 | 用途 |
| --- | --- |
| [apps/ios](apps/ios) | iPhone 应用、XCUITest 和共享 Scheme |
| [ci/ios](ci/ios) | 本地与 CI 共用的 Xcode 命令，以及发行签名脚本 |
| [iOS CI](.github/workflows/ios-ci.yml) | PR 和 `main` 的模拟器冒烟测试及 Release 归档 |
| [iOS TestFlight](.github/workflows/ios-testflight.yml) | 从默认分支验证、签名导出及上传 |

开发与发布见 [iOS 工程手册](apps/ios/README.md)。
