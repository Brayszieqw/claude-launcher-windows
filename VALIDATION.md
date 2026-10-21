# 源码发布验证

2026-10-21，Windows x64，Windows PowerShell 5.1。

这份源码对应 1.1.0 的持续提醒模式：异常每分钟提醒，恢复后停止，不自动结束或重启 Claude / Claude Code。核心脚本与发布准备时核对的本机安装一致。

源码发布额外处理了两处资源依赖：缺少人物图标时由构建脚本生成 Windows 通用应用图标；缺少背景目录时，内嵌 IPCheck 跳过本地图片映射。运行中的本机安装没有因本次打包而改动。

## 本次实际执行

命令格式：`powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\<脚本>`。

| Command | Output | Result |
| --- | --- | --- |
| 原构建脚本，不附美术资源 | 提示缺少人物图标，无法构建 | FAIL，发布前基线 |
| `build.ps1` | 生成 1.1.0.0 的 ClaudeLauncher.exe 和通用图标 | PASS |
| `tests\SourcePackage.Smoke.ps1` | 无美术资源可初始化 WPF 界面；缺少动画时控件可用；IPCheck C# 编译通过；未写入运行状态 | PASS |
| `tests\Offline.Tests.ps1` | 修改前及修改后均为 32 / 32 | PASS |
| `tests\Guard.Tests.ps1` | 修改前及修改后均为 7 / 7 | PASS |

`HugPlayback.Smoke.ps1` 与 `EmbeddedDns.Smoke.ps1` 的视觉断言需要另外提供美术资源，本次没有运行。没有测试真实账号切换、长期守护、重新登录 Windows 或 macOS；本次是 Windows 源码发布。

## 包含与排除

包含程序脚本、C# 启动器和网页窗口、探针、构建与安装脚本、测试、动画制作代码、MIT 许可证及第三方声明。WebView2 SDK DLL 保留原始许可；SQLite 文件为测试夹具，内容为 fixture 示例。

不包含背景、人物图片、动画视频、截图、生成的 EXE / ICO、Git 工作目录、本机诊断记录、账号快照、登录数据、密钥或构建备份。源码 ZIP 由本次提交生成；它需要自行构建，不是预编译安装包。
