param(
    [string]$Package = (Split-Path -Parent $PSScriptRoot),
    [string]$WorkRoot = (Join-Path $env:TEMP ('ClaudeLauncherTests-'+[guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference='Stop'
if (Get-Process -Name ClaudeLauncher -ErrorAction SilentlyContinue) { throw '请先关闭 Claude 启动助手：测试副本与它共用单实例锁。' }
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
$results=New-Object System.Collections.Generic.List[object]
function Assert($Condition,$Message) { if (-not $Condition) { throw $Message } }
function Test-Case($Name,[scriptblock]$Body) {
    try { & $Body; $results.Add([pscustomobject]@{Name=$Name;Status='PASS';Detail=''}) }
    catch { $results.Add([pscustomobject]@{Name=$Name;Status='FAIL';Detail=$_.Exception.Message}) }
}
function Invoke-Launcher([string]$Name,[string]$Script) {
    # A copy of the real EXE runs a stand-in SwitcherUI.ps1; its state folder is redirected through LOCALAPPDATA.
    $folder=Join-Path $WorkRoot $Name
    [void](New-Item -ItemType Directory -Path $folder -Force)
    Copy-Item -LiteralPath (Join-Path $Package 'ClaudeLauncher.exe') -Destination $folder
    [IO.File]::WriteAllText((Join-Path $folder 'SwitcherUI.ps1'),$Script,(New-Object Text.UTF8Encoding($true)))
    $info=New-Object Diagnostics.ProcessStartInfo (Join-Path $folder 'ClaudeLauncher.exe')
    $info.UseShellExecute=$false
    $info.EnvironmentVariables['LOCALAPPDATA']=Join-Path $folder 'appdata'
    $process=[Diagnostics.Process]::Start($info)
    try {
        $box=''
        $exited=$process.WaitForExit(15000)
        if (-not $exited) {
            # Still running means a message box is up: read its text, then close it.
            $owner=New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ProcessIdProperty),$process.Id
            $window=[Windows.Automation.AutomationElement]::RootElement.FindFirst([Windows.Automation.TreeScope]::Children,$owner)
            if ($window) {
                # The message is exposed as Text on some systems and as Pane on others; read every named part but the button.
                $parts=@($window.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition) | ForEach-Object { $_.Current.Name.Trim() } | Where-Object { $_ -and $_ -notin @('确定','OK') })
                $box=($parts -join ' ').Trim()
            }
        }
        $log=Join-Path $folder 'appdata\ClaudeSwitcherWindows\launcher-errors.log'
        [pscustomobject]@{Exited=$exited;ExitCode=$(if ($exited) {$process.ExitCode});Box=$box;Log=$(if (Test-Path -LiteralPath $log) {[IO.File]::ReadAllText($log)} else {''})}
    } finally {
        if (-not $process.HasExited) { $process.Kill(); [void]$process.WaitForExit(5000) }
        $process.Dispose()
    }
}
$missing="Get-Item -LiteralPath 'C:\claude-launcher-test-missing'"
foreach ($case in @(
    @('Caught cmdlet error shows no box','caught',"try { $missing -ErrorAction Stop } catch {}"),
    @('Silenced cmdlet error shows no box','silenced',"$missing -ErrorAction SilentlyContinue | Out-Null"),
    @('Cmdlet error caught in an event handler shows no box','handler','$handler=[EventHandler]{ try { ''{bad'' | ConvertFrom-Json } catch {} }; $handler.Invoke($null,[EventArgs]::Empty)')
)) {
    Test-Case $case[0] {
        $run=Invoke-Launcher $case[1] $case[2]
        Assert ($run.Exited -and $run.ExitCode -eq 0) ('Launcher showed a box or failed: "'+$run.Box+'"')
        Assert (-not $run.Log) 'A handled error was logged as a failure'
    }
}
Test-Case 'A failure that stops the window explains itself' {
    $run=Invoke-Launcher 'thrown' "throw 'fixture: window could not open'"
    Assert (-not $run.Exited -and $run.Box -match 'fixture: window could not open') ('Error box was missing or blank: "'+$run.Box+'"')
}
Test-Case 'Reported errors go to the launcher log, not a box after the window closed' {
    $run=Invoke-Launcher 'reported' "Write-Error 'fixture: reported while the window was open'"
    Assert ($run.Exited -and $run.ExitCode -eq 0) ('Launcher showed a box after closing: "'+$run.Box+'"')
    Assert ($run.Log -match 'fixture: reported while the window was open') 'The reported error was not logged'
}
$results | ConvertTo-Json -Depth 5
if (@($results | Where-Object Status -eq 'FAIL').Count) { exit 1 }
