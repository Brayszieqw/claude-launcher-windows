param([string]$WorkRoot=(Join-Path $env:TEMP ('ClaudeTaskbar-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$WorkRoot=[IO.Path]::GetFullPath($WorkRoot)
$package=Split-Path -Parent $PSScriptRoot
$expectedId='Local.ClaudeStartupAssistant'
[void](New-Item -ItemType Directory -Path $WorkRoot -Force)
Add-Type -Path (Join-Path $PSScriptRoot 'TaskbarProbe.cs')
$results=New-Object System.Collections.Generic.List[object]
function Record($Name,$Passed,$Detail) {$results.Add([pscustomobject]@{Name=$Name;Status=$(if($Passed){'PASS'}else{'FAIL'});Detail=$Detail})}
$text=[IO.File]::ReadAllText((Join-Path $package 'SwitcherUI.ps1'))
$text=$text -replace '(?m)^\[void\]\$window\.ShowDialog\(\)\s*$',''
$text=$text -replace '(?ms)^\$window\.Add_ContentRendered\(\{.*?^\}\)\r?\n',''
$text=$text.Replace('$PSScriptRoot',("'"+$package.Replace("'","''")+"'"))
. ([scriptblock]::Create($text)) -StateRoot (Join-Path $WorkRoot 'state')
try {
    $window.ShowActivated=$false;$window.ShowInTaskbar=$false;$window.Show()
    $handle=(New-Object Windows.Interop.WindowInteropHelper $window).Handle
    $actual=@{Id=[TaskbarProbe]::ReadWindow($handle,5);Command=[TaskbarProbe]::ReadWindow($handle,2);Icon=[TaskbarProbe]::ReadWindow($handle,3);Name=[TaskbarProbe]::ReadWindow($handle,4)}
    $passed=$actual.Id -eq $expectedId -and $actual.Command -eq ('"'+(Join-Path $package 'ClaudeLauncher.exe')+'"') -and $actual.Icon -eq ((Join-Path $package 'launcher.ico')+',0') -and $actual.Name -eq 'Claude 启动助手'
    Record 'Window identity, launch command and pinned icon' $passed ($actual | ConvertTo-Json -Compress)
    $script:operation='fixture busy'
    $window.Close()
    Record 'Cancelled close preserves the window identity' ($window.IsVisible -and [TaskbarProbe]::ReadWindow($handle,5) -eq $expectedId) ''
    $script:operation=$null
    $script:propertiesCleared=$false
    $window.Add_Closing({$script:propertiesCleared=(@(2,3,4,5 | Where-Object {[TaskbarProbe]::ReadWindow($handle,$_) -ne ''}).Count -eq 0)})
    $window.Close()
    Record 'Window property storage released before close' $script:propertiesCleared ''
} finally {$hugTimer.Stop();$timer.Stop();$guardTimer.Stop();$sceneTimer.Stop();$hugMotion.Close();if($window.IsVisible){$window.Close()}}
$desktop=Join-Path $WorkRoot 'desktop'
[void](New-Item -ItemType Directory -Path $desktop)
[void](& (Join-Path $package 'install.ps1') -DesktopDirectory $desktop)
$folder=(New-Object -ComObject Shell.Application).Namespace($desktop)
$appId=$folder.ParseName('Claude 启动助手.lnk').ExtendedProperty('System.AppUserModel.ID')
Record 'Installer shortcut has the same application identity' ($appId -eq $expectedId) $appId
if(Get-Process ClaudeLauncher -ErrorAction SilentlyContinue){throw 'Close the assistant before the isolated EXE identity test.'}
$fixture=Join-Path $WorkRoot 'exe'
[void](New-Item -ItemType Directory -Path $fixture)
Copy-Item -LiteralPath (Join-Path $package 'ClaudeLauncher.exe') -Destination $fixture
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'TaskbarProbe.cs') -Destination $fixture
$stub='Add-Type -Path (Join-Path $PSScriptRoot ''TaskbarProbe.cs''); [TaskbarProbe]::ReadProcess() | Set-Content -LiteralPath (Join-Path $PSScriptRoot ''identity.txt'') -Encoding utf8'
[IO.File]::WriteAllText((Join-Path $fixture 'SwitcherUI.ps1'),$stub,[Text.UTF8Encoding]::new($true))
$start=New-Object Diagnostics.ProcessStartInfo (Join-Path $fixture 'ClaudeLauncher.exe')
$start.UseShellExecute=$false;$start.EnvironmentVariables['LOCALAPPDATA']=Join-Path $fixture 'appdata'
$process=[Diagnostics.Process]::Start($start)
try {
    if(-not $process.WaitForExit(15000)){throw 'Isolated launcher did not exit'}
    $appId=([IO.File]::ReadAllText((Join-Path $fixture 'identity.txt'))).Trim()
    Record 'Real EXE establishes process identity before loading UI' ($process.ExitCode -eq 0 -and $appId -eq $expectedId) $appId
} finally {if(-not $process.HasExited){$process.Kill()};$process.Dispose()}
$results | ConvertTo-Json -Depth 3
if(@($results | Where-Object Status -eq FAIL).Count){exit 1}
