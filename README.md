# Claude 启动助手 · Windows

让启动 Claude Desktop、检查网络环境、管理本地账号快照，都在一个窗口里完成。

这是面向 **Windows + FlClash + Claude Desktop** 的个人开源助手，使用 PowerShell、WPF 和 C# 实现。界面采用「夕照拥抱」主题，点击「拥抱一下」会播放动画并检查环境，也可独立点击「启动 Claude」。

**[下载 1.1.0 源码包](https://github.com/Brayszieqw/claude-launcher-windows/releases/tag/source-v1.1.0-20261021) · [下载旧版 1.0.0 便携包](https://github.com/Brayszieqw/claude-launcher-windows/releases/tag/v1.0.0) · [使用方法](#开始使用) · [开源来源与致谢](#开源来源与致谢) · [MIT 许可证](LICENSE)**

> 当前源码版本为 **1.1.0**（2026-10-21 源码发布）。网络监测按 **Starlink AS14593** 核验出口，IP 变化、出口差异和 DNS 配置异常均只作提醒；不会自动结束、重启或锁定 Claude / Claude Code。

本仓库包含程序源码、构建脚本、测试和必要的第三方依赖。背景、人物、动画、图标原图及界面截图单独保留，不在源码仓库或源码 ZIP 中；无这些资源仍可构建和运行基础界面。

## 可以做什么

| 功能 | 说明 |
| --- | --- |
| 启动前检查 | 检查代理内核、TUN、监听端口、FlClash 配置及 15 个官方固定域名和 DNS 缓存中发现的 Claude 子域名，每个目标分别检查显式代理和系统 / TUN 路径。 |
| 全时段守护 | 登录自启和托盘常驻，网络异常时弹出独立提醒窗；每分钟重复，恢复后停止。后台不控制 Claude 进程。 |
| 网络诊断 | 查看 IPv4、IPv6、UDP / STUN、WebRTC、DNS 解析器和网络归属；支持内嵌 IPCheck 深度 DNS。 |
| 设备特征 | 用独立 Edge 配置采样浏览器特征，保存基准并比较变化。 |
| 本地账号管理 | 新增、重命名账号标签，按需保存快照、切换和恢复。日常单账号使用无需切换。 |
| 诊断记录 | 查看历史结果与差异，导出 JSON 或 Markdown。 |
| 环境设置 | 提供 Windows 时区、区域格式、语言顺序，以及 Chrome 语言、字体和 IPPure 入口。 |
| 夕照拥抱 | 自制角色与场景动画，10 秒、60 fps；播放结束不会自动启动 Claude。 |

## 运行环境

- Windows 10 / 11 **x64**，Windows PowerShell 5.1、.NET Framework 4.x、WPF 和系统自带的 `curl.exe`。
- 已安装 Claude Desktop。优先识别 Microsoft Store 版，也兼容代码中列出的常见独立安装路径。
- 已安装并运行 [FlClash](https://github.com/chen08209/FlClash)，开启 TUN。配置检查以 FlClash 0.9.1 的结构验证过。
- 默认本机 HTTP 代理端口为 `7890`。
- 设备特征与 WebRTC 探测需要 Microsoft Edge；内嵌 IPCheck 需要 [WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/)。

日常运行无需 Python、Node.js 或 FFmpeg。一般检测与启动无需管理员权限；手动修改 Windows 设置时，以系统实际权限为准。

## 开始使用

### 从当前源码开始

1. 下载上方 **1.1.0 源码 ZIP** 并完整解压，或克隆本仓库。
2. 在源码目录打开 **Windows PowerShell 5.1**，执行下方构建命令。
3. 打开 FlClash，确认 TUN 已启用，本机代理端口与助手设置一致。
4. 双击构建生成的 ClaudeLauncher.exe；保留同目录脚本、lib、launcher 和 probe。
5. 在「重新检测」或「拥抱一下」查看结果；源码包未附动画，检测功能照常运行。
6. 点击「启动 Claude」即可打开；网络异常只提醒，不作为启动锁。

旧版 1.0.0 便携包仍可从历史 Release 下载，但不包含本次 1.1.0 的持续提醒改动。需要当前行为，请构建本仓库源码。

`Start.cmd` 也是启动入口。请保留整个解压目录，单独复制 EXE 无法运行。

如果需要桌面快捷方式，在解压目录打开 Windows PowerShell，运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

安装脚本只创建快捷方式；已有同名快捷方式会先备份。程序目录移动后，重新运行一次即可。

### 使用其他本地代理端口

设置文件为：

```text
%LOCALAPPDATA%\ClaudeSwitcherWindows\settings.json
```

如果文件不存在，可以创建：

```json
{
  "ProxyPort": 7890
}
```

将数字改为 FlClash 实际使用的 HTTP / Mixed 端口。已有文件请先备份，只修改 `ProxyPort`，保留其他字段。

### 网络与设备检查

- **基础检查**：显示本机与网络状态，HTTPS 阶段独立最多 60 秒，通过提前结束；含准备阶段的整体期限为 75 秒。异常或超时不锁定启动。
- **开始深度检测**：比较 HTTPS、IPv6、UDP / STUN 与独立 Edge WebRTC 路径。
- **检测网络画像**：查看出口、ASN、DNS 解析器、第三方评分与服务状态；多个服务依次超时时会比较慢。
- **IPCheck 深度 DNS**：在内嵌窗口访问原站，首次可能需要自行登录；登录、额度和结果由 IPCheck 提供。
- **设备特征**：查看采样结果，需要比较变化时再点击「采集并记住基准」。

网页检测结果只作诊断展示。DNS 地址数量、第三方评分和 IP 变化应结合路径判断；未验证会直接显示出来。

### 可选的账号切换

「主账号」是当前本地会话的标签。新增账号、重命名和选择卡片只修改助手记录。

主动点击「切换到选中账号」并确认后，助手会检查环境和磁盘空间，关闭 Claude Desktop，校验并保存当前数据，再载入目标快照。新账号没有快照时，需要自行登录。切换后回到概览检查，再启动 Claude。

切换中断时，使用「恢复上次切换前的数据」。快照和切换前的备份会保留，需要足够磁盘空间；它们含登录状态，不要上传到 GitHub。此功能一次使用一个账号，不管理 Claude Code 的账号。

## 全时段守护与数据位置

首次打开助手会建立当前用户的登录启动快捷方式，并启动监测。Windows 登录后先收起到托盘；关闭主窗口也会收起到托盘，提示仍会继续。双击托盘图标或重新双击 EXE 可以恢复窗口。「退出界面（停止弹窗）」明确退出提示界面，后台检测继续，重新打开助手后恢复弹窗。

后台每轮本地检查后等待 2 秒。网络核验正常后等待 60 秒再测，异常或证据不完整时等待 15 秒再测。HTTPS 阶段最多 60 秒，证据齐全就提前结束。检测进程不枚举、结束、挂起、重启或激活 Claude / Claude Code。

### 收到警报时

1. 提示窗显示具体原因；正在使用的 Claude 和编程会话继续运行，主页面不会自动切换。
2. 尚未恢复时，每 1 分钟再次提示并发出系统提示音。只有一个提示窗，不叠加多个窗口，也不主动抢键盘焦点。
3. 关闭提示窗或选择「稍后提醒（1 分钟）」只延后提醒，不视为异常已解除。
4. 点击「查看详情」，或从「网络检测」第四项「实时监测」查看原因。可点「立即重新检查」，也可等待自动核验。
5. 网络恢复正常后自动停止提醒。IP 发生变化但仍为星链、同轮出口一致时会明确注明；后续一轮保持稳定后停止该变化提醒。

超时、限流、无效响应和配置无法读取显示「检测受限」，不宣称已经发生 DNS 泄露。提示频率与后台测量频率分别计算。

### 域名覆盖与检测边界

固定目标为 `claude.ai`、`claude.com`、`api.anthropic.com`、`anthropic.com`、`a-api.anthropic.com`、`a-cdn.anthropic.com`、`s-cdn.anthropic.com`、`assets-proxy.anthropic.com`、`a.claude.ai`、`assets.claude.ai`、`downloads.claude.ai`、`platform.claude.com`、`mcp-proxy.anthropic.com`、`bridge.claudeusercontent.com`、`code.claude.com`。

动态发现包括 `anthropic.com`、`claude.ai`、`claude.com`、`claude.app`、`claudeusercontent.com`、`claudemcpcontent.com` 及其子域名。每轮从 Windows DNS 缓存读取真实出现的名称，并使用完整域名边界匹配。网页和 API 的六条路径必须实测通过；资源域名若明确返回 404，仅在能够按顺序解析本机分流规则、确认与 API 指向同一策略时采用路由证据，并以提醒项显示。该结果不等于独立测得资源请求的公网 IP；否则显示未验证并提醒；不限制新启动和现有会话。早于域名规则的未知规则、直连规则或规则集不能跳过。

清单依据 [Claude Desktop 网络要求](https://code.claude.com/docs/en/desktop) 和 [Claude Code 网络配置](https://code.claude.com/docs/en/network-config)。自定义 MCP、第三方模型网关、GitHub / npm、第三方遥测和资源 CDN 可以使用任意域名；本版本没有把这些共享第三方域名纳入星链出口判定，也不能发现应用自行使用 DoH 且未进入系统 DNS 缓存的名称。不能把这份清单理解为穷尽未来的一切网络请求。

DNS 守护核验 FlClash 的 DNS 启用、严格路由、UDP / TCP 53 接管，以及是否存在独立直连 DNS 上游。它是配置层检查，不能证明所有应用的加密 DNS 都没有旁路；实际解析器观察仍在网络诊断和浏览器 DNS 检测中。监测不操作本机、WSL 或虚拟机中的应用进程。

守护采用轮询，没有安装防火墙规则，检测间隔内可能已有流量发出。助手不会自动修改 FlClash、代理、DNS 或账号登录文件。

助手状态默认保存在 `%LOCALAPPDATA%\ClaudeSwitcherWindows`：

| 路径 | 内容 |
| --- | --- |
| `settings.json` | 本机代理端口。 |
| `account-state.json`、`accounts/` | 本地账号标签、快照与校验记录。 |
| `pending-switch.json` | 切换事务与恢复信息。 |
| `diagnostics/` | 历史诊断与导出依据。 |
| `fingerprint-baseline.json` | 用户主动保存的设备特征摘要。 |
| `address-key.txt` | 本机地址摘要密钥。 |
| `guard.*`、`guard-observations.jsonl` | 守护状态和日志。 |
| `ipcheck-webview/` | IPCheck 内嵌浏览器的登录与网页存储。 |
| `environment-settings/` | 手动修改 Windows 设置前的备份。 |

切换前的 Claude 数据还会保留在原数据目录旁的 `Claude.switcher-backup-*` 目录中。检测功能本身不修改系统网络设置；「环境设置」里确认应用的操作会改变对应 Windows 选项。

## 从源码构建

```powershell
git clone https://github.com/Brayszieqw/claude-launcher-windows.git
cd claude-launcher-windows
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
.\ClaudeLauncher.exe
```

请使用 **Windows PowerShell 5.1** 运行构建脚本。脚本调用 Windows 自带的 .NET Framework 编译器，生成图标和 `ClaudeLauncher.exe`；已有 EXE 和图标会先备份。缺少人物图标原图时使用 Windows 通用应用图标。WebView2 SDK 文件和原始许可已包含，无需额外还原 NuGet 包。

| 文件 / 目录 | 作用 |
| --- | --- |
| `SwitcherUI.ps1` | WPF 界面、页面交互与动画播放。 |
| `claude-switch.ps1` | 应用识别、启动检查、账号快照与恢复。 |
| `claude-bodyguard.ps1`、`guard-runtime.ps1` | 常驻监测、域名覆盖、IP 变化提醒和手动复查。 |
| `network-probes.ps1` | HTTPS、ASN、STUN、WebRTC 等探测。 |
| `flclash-checks.ps1` | FlClash 配置检查和浏览器入口。 |
| `environment-insights.ps1` | 网络画像、设备特征与环境设置。 |
| `diagnostic-reports.ps1` | 诊断存储、比较和导出。 |
| `launcher/` | C# 启动器、任务栏标识与 IPCheck 窗口。 |
| `probe/` | 浏览器探针、IPCheck 主题和只读配置查询。 |
| `assets/`（自行提供，可选） | 不随源码上传的角色图标、夕照场景和拥抱动画。 |
| `lib/WebView2/` | WebView2 SDK 1.0.4258.31 及原始许可证。 |
| `tests/` | 离线、回环服务与界面检查。 |
| `tools/build-hug-motion.py` | 动画制作工具，日常运行和 EXE 构建不调用。 |

重制动画时才需要 Python、OpenCV、NumPy 和 FFmpeg。制作脚本接受原始 `1586 × 992 / 30 fps / 300 帧` 视频并输出 60 fps 文件；已制作的 60 fps 成片不能作为该脚本的原始输入；本源码包不附原始素材或成片。

### 可选的美术资源

基础功能不依赖美术资源。若有自己的素材，可按以下路径加入本地目录：

- `assets/launcher-character.png`：应用图标原图，加入后重新运行构建。
- `assets/hug/background.png`：背景。
- `assets/hug/pose-01.png`、`assets/hug/pose-15.png`：起始与结束姿势。
- `assets/hug/hug-motion.mp4`：10 秒、60 fps 的 H.264 动画。

这些路径已加入 `.gitignore`。没有媒体资源时不播放角色动画，不影响网络检测与启动。

### 验证

在仓库根目录运行：

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Offline.Tests.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\FlClash.Tests.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Insights.Tests.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Starlink.Tests.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Guard.Tests.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Guard-Smoke.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Guard-Readiness.Smoke.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Window-Smoke.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\RoundBudget.Tests.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\UI-Smoke.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\SourcePackage.Smoke.ps1
```

先构建，再运行上述检查。它们使用临时状态、模拟数据或回环服务。`HugPlayback.Smoke.ps1` 和 `EmbeddedDns.Smoke.ps1` 的原有视觉断言需自行提供美术资源；媒体制作测试另需 Python 依赖。发布验证结果见 [VALIDATION.md](VALIDATION.md)；它们不代表外部服务或账号状态。

## 常见问题

**启动按钮为什么不能点？**

检测、账号操作或拥抱动画进行期间，部分按钮会暂时禁用，结束后恢复。当前 1.1.0 不因网络异常锁定启动；旧版 1.0.0 便携包仍使用旧规则。

**网络能用，为什么还显示未验证？**

检测服务可能超时、限流或返回无法解析的内容。这表示尚未取得证据，不等于网络已坏；正在运行的 Claude 不会仅因此被结束。检测结果与是否启动相互独立，手动复查完成后会自动刷新基础检查。

**动画不能播放怎么办？**

确认完整解压、`assets/hug/hug-motion.mp4` 存在，系统支持 H.264 播放。系统关闭动画效果、媒体打不开或播放停滞时，会显示最后一帧并恢复操作。

**升级怎么做？**

保留旧程序目录作为备份，将新版解压到新目录，再重新创建快捷方式。状态目录独立保存，通常无需复制进程序目录。

**怎么反馈问题？**

在 [Issues](https://github.com/Brayszieqw/claude-launcher-windows/issues) 写明系统、版本、操作和报错；分享报告前检查其中的本机信息。不要附上账号快照、密钥或整个状态目录。

## 开源来源与致谢

感谢这些项目提供的源码和思路：

| 项目 | 本项目使用或参考的部分 | 许可证 |
| --- | --- | --- |
| [YOURSJEYO/claude-switcher](https://github.com/YOURSJEYO/claude-switcher/tree/d56cad06ae35e31b86dde96e7c8699f02378ef21) | Windows 启动检查、会话守护、账号快照的初始基础，随后适配 FlClash、商店版 Claude 和当前界面。 | MIT |
| [jason5ng32/MyIP](https://github.com/jason5ng32/MyIP/tree/5502169374ccbb9ac7c3d70ac703ecbba3fa0813) | DNS 探测协议与返回结构、网络信息展示及字体测量方法。 | MIT |
| [LinXiaoTao/FuckClaude](https://github.com/LinXiaoTao/FuckClaude/tree/e4aadac01d7a1456e98db71d4da34fe27b3bee52) | 字体宽度探测方法。 | MIT |
| [situker/claude-env-check](https://github.com/situker/claude-env-check/tree/f3ad0cf2622fc1d49f2b61ba563233ca29510613) | 网络路径、代理配置与 TLS 检查的分类思路。 | MIT |
| [Microsoft WebView2](https://www.nuget.org/packages/Microsoft.Web.WebView2/1.0.4258.31) | 内嵌 IPCheck 网页窗口，随包提供 Core、WPF 和 x64 Loader。 | SDK 原始许可证随包保留 |

动画由本项目自行制作，制作方法参考 [mytjxs/codex-startup-animation](https://github.com/mytjxs/codex-startup-animation)；动作参考 [Bilibili 视频](https://www.bilibili.com/video/BV19dJ66RE6P/)。制作过程中使用了图像生成、[RIFE / ncnn](https://github.com/nihui/rife-ncnn-vulkan)、OpenCV、NumPy 和 FFmpeg。

同时感谢 FlClash，以及 IPCheck、IPPure、ipify、ipinfo、ipwho.is 等提供的工具和服务。

## 开源协议

本项目采用 **[MIT License](LICENSE)**，允许使用、修改、分发和商业使用；分发时请保留版权及许可声明。上游代码的完整声明收录在 [THIRD-PARTY-NOTICES.txt](THIRD-PARTY-NOTICES.txt)，WebView2 原始许可证与声明位于 [lib/WebView2](lib/WebView2)。

在线服务另有使用条款。例如 [IP-API 免费 DNS 接口](https://ip-api.com/docs/dns)不允许商业使用，商业部署时需要替换该接口或另行取得服务授权。

这是个人社区项目，与 Anthropic 没有隶属或官方合作关系。Claude 等名称和商标归各自权利人所有。
