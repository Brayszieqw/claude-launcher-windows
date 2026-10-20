# Claude 启动助手 · Windows

用于 Windows + FlClash + Claude Desktop 的启动助手，提供环境检查、会话守护、账号快照和夕照拥抱动画。

**[下载完整安装包](https://github.com/Brayszieqw/claude-launcher-windows/releases/latest)**

## 使用方法

1. 下载 ZIP，完整解压到固定文件夹。
2. 打开 FlClash 并启用 TUN，默认代理端口为 `7890`。
3. 双击 `ClaudeLauncher.exe`。
4. 点击「拥抱一下」或「重新检测」，检查通过后点击「启动 Claude」。

运行环境：Windows 10 / 11 x64、已安装的 Claude Desktop。设备探测使用 Edge，内嵌 DNS 页面使用 WebView2 Runtime。

当前版本按 **Starlink AS14593** 核验启动出口。其他运营商可使用诊断功能，但不会通过当前启动检查。

请保留完整解压目录。需要桌面快捷方式时，在目录中运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

助手数据存放在 `%LOCALAPPDATA%\ClaudeSwitcherWindows`。账号切换为可选功能；快照含登录状态，请自行保管。

## 致谢与许可

项目基础来自 [claude-switcher](https://github.com/YOURSJEYO/claude-switcher)；网络与字体检测参考 [MyIP](https://github.com/jason5ng32/MyIP)、[FuckClaude](https://github.com/LinXiaoTao/FuckClaude)，检查分类参考 [claude-env-check](https://github.com/situker/claude-env-check)。内嵌网页使用 Microsoft WebView2。

动画自行制作，制作方法参考 [codex-startup-animation](https://github.com/mytjxs/codex-startup-animation)。

采用 [MIT 许可证](LICENSE)，第三方许可原文随安装包保留。在线检测服务按各自条款使用；IP-API 免费 DNS 接口限非商业用途。本项目与 Anthropic 无隶属关系。
