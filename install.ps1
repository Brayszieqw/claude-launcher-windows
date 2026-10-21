# Optional: create a shortcut to this portable folder. No administrator rights are required.
param([string]$DesktopDirectory = [Environment]::GetFolderPath('Desktop'))
$ErrorActionPreference = 'Stop'
$application = Join-Path $PSScriptRoot 'ClaudeLauncher.exe'
if (-not (Test-Path -LiteralPath $application)) { throw '请先完整解压程序目录。' }
$shortcutPath = Join-Path $DesktopDirectory 'Claude 启动助手.lnk'
if (Test-Path -LiteralPath $shortcutPath) {
    Copy-Item -LiteralPath $shortcutPath -Destination ($shortcutPath + '.backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')) -ErrorAction Stop
}
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $application
$shortcut.IconLocation = (Join-Path $PSScriptRoot 'launcher.ico') + ',0'
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.Description = 'FlClash 与 Claude 桌面版启动检查'
$shortcut.Save()
[void][Reflection.Assembly]::LoadFrom($application)
[TaskbarIdentity]::ConfigureShortcut($shortcutPath)
Write-Output ('已创建快捷方式：' + $shortcutPath)
