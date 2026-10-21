param([string]$WorkRoot=(Join-Path $env:TEMP ('ClaudeGuardReadiness-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$package=Split-Path -Parent $PSScriptRoot
[void](New-Item -ItemType Directory -Path $WorkRoot -Force)
. (Join-Path $package 'claude-switch.ps1') -StateRoot $WorkRoot
$results=New-Object System.Collections.Generic.List[object]
function Assert($Condition,$Message) {if (-not $Condition) {throw $Message}}
function Case($Name,[scriptblock]$Body) {
    try {& $Body;$results.Add([pscustomobject]@{Name=$Name;Status='PASS';Detail=''})}
    catch {$results.Add([pscustomobject]@{Name=$Name;Status='FAIL';Detail=$_.Exception.Message})}
}
Case 'A legacy lock and incomplete network evidence cannot prevent launch readiness' {
    function Get-ClaudeInstall {[pscustomobject]@{Kind='fixture';Exe='fixture'}}
    function Get-ProtectionHealth {[pscustomobject]@{Healthy=$true;Core=$true;Tun=$true;Proxy=$true;Adapter='fixture'}}
    function Get-FlClashCheck {[pscustomobject]@{Checks=@()}}
    function Get-GuardDnsCheck {New-Check '守护 DNS' ok fixture}
    function Get-LocalConfigurationChecks {@()}
    function Get-IPv6LocalCheck {New-Check IPv6 info fixture}
    function Read-GuardState {[pscustomobject]@{Locked=$true}}
    function Get-LaunchNetworkEvidence {[pscustomobject]@{State='unknown';Detail='fixture HTTPS incomplete';Checks=@();Observations=@()}}
    $check=Get-EnvironmentCheck $WorkRoot
    Assert ($check.Ready -and ($check.Checks | Where-Object Name -eq '代理 HTTPS 出口').State -eq 'unknown') 'An unknown probe locked launch or was mislabeled as a pass'
}
$fixture=Join-Path $WorkRoot 'backend-fixture.ps1'
$fixtureText=@'
param([string]$Command,[string]$StateRoot)
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$mode=Get-Content -LiteralPath (Join-Path $StateRoot 'mode.txt')
Add-Content -LiteralPath (Join-Path $StateRoot 'actions.txt') -Value $Command
if ($Command -eq 'guard-check') {
    if ($mode -eq 'request-failed') {'{"Error":"fixture request failed"}';exit 1}
    '{"Message":"fixture manual recheck complete"}'
} elseif ($Command -eq 'check') {
    Start-Sleep -Milliseconds 1200
    $checks=@('Claude 桌面版','代理内核','TUN 网卡','本地代理端口','代理 HTTPS 出口' | ForEach-Object {
        $fail=$mode -eq 'check-failed' -and $_ -eq '代理 HTTPS 出口'
        [pscustomobject]@{Name=$_;State=$(if ($fail) {'unknown'} else {'ok'});Detail='fixture';Blocking=$fail}
    })
    [pscustomobject]@{Ready=$true;Checks=$checks;CheckedAt='fresh manual fixture'} | ConvertTo-Json -Depth 5
} else {throw 'Unexpected fixture action'}
'@
[IO.File]::WriteAllText($fixture,$fixtureText,(New-Object Text.UTF8Encoding($true)))
$text=[IO.File]::ReadAllText((Join-Path $package 'SwitcherUI.ps1'))
$text=$text -replace '(?m)^\[void\]\$window\.ShowDialog\(\)\s*$',''
$text=$text.Replace("`$core=Join-Path `$PSScriptRoot 'claude-switch.ps1'",("`$core='"+$fixture.Replace("'","''")+"'"))
$text=$text.Replace('$PSScriptRoot',("'"+$package.Replace("'","''")+"'"))
. ([scriptblock]::Create($text)) -StateRoot $WorkRoot
$script:noticeState=[pscustomobject]@{Phase='守护中';Reason='';AlertKind='';Revision='fixture';CheckedAt=[DateTime]::UtcNow.ToString('o')}
function Get-GuardSummary {'全时段守护 · '+$script:noticeState.Phase}
function Read-GuardState {$script:noticeState}
try {
    Case 'The same unresolved warning repeats every minute and recovery stops it' {
        $script:alerts=New-Object System.Collections.Generic.List[string]
        function Show-GuardAlert($Reason) {$script:alerts.Add($Reason)}
        $script:noticeState.Phase='警报';$script:noticeState.Reason='fixture network warning';$script:noticeState.AlertKind='Network'
        $script:nextGuardAlert=[DateTime]::MinValue
        Update-GuardDisplay
        Update-GuardDisplay
        Assert ($script:alerts.Count -eq 1 -and ($script:nextGuardAlert-[DateTime]::UtcNow).TotalSeconds -gt 58) 'Warning repeated before the one-minute interval'
        $script:nextGuardAlert=[DateTime]::UtcNow.AddSeconds(-1)
        Update-GuardDisplay
        Assert ($script:alerts.Count -eq 2) 'An unchanged unresolved warning did not repeat'
        $script:noticeState.Phase='守护中';$script:noticeState.Reason='';$script:noticeState.AlertKind=''
        Update-GuardDisplay
        Assert ($script:alerts.Count -eq 2 -and $script:nextGuardAlert -eq [DateTime]::MinValue) 'Recovery kept reminding or did not reset the reminder'
        $script:noticeState.Phase='检测受限';$script:noticeState.Reason='fixture unavailable';$script:noticeState.AlertKind='Unknown'
        Update-GuardDisplay
        Assert ($script:alerts.Count -eq 3 -and $window.FindName('BtnStart').IsEnabled) 'A later warning was suppressed or locked launch'
        $script:noticeState.Phase='守护中';$script:noticeState.Reason='';$script:noticeState.AlertKind=''
        Update-GuardDisplay
    }
    foreach ($mode in @('pass','check-failed','request-failed')) {
        Case ('Manual recheck refreshes results and never creates a network launch lock: '+$mode) {
            [IO.File]::WriteAllText((Join-Path $WorkRoot 'mode.txt'),$mode)
            [IO.File]::WriteAllText((Join-Path $WorkRoot 'actions.txt'),'')
            Update-GuardDisplay
            Invoke-GuardCheck
            $deadline=[DateTime]::UtcNow.AddSeconds(12)
            $sawCheck=$false
            while ($script:operation -and [DateTime]::UtcNow -lt $deadline) {
                $frame=New-Object Windows.Threading.DispatcherFrame
                [void]$window.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background,[Action]{$frame.Continue=$false})
                [Windows.Threading.Dispatcher]::PushFrame($frame)
                if ($script:operation -and $script:operation.Action -eq 'check') {
                    $sawCheck=$true
                    Assert ($script:busy -and -not $window.FindName('BtnCheck').IsEnabled) 'Chained check was not kept busy'
                }
                Start-Sleep -Milliseconds 20
            }
            Assert (-not $script:operation -and $window.FindName('BtnStart').IsEnabled) 'Manual check did not finish or locked launch'
            $actions=@(Get-Content -LiteralPath (Join-Path $WorkRoot 'actions.txt'))
            if ($mode -eq 'request-failed') {
                Assert (($actions -join ',') -eq 'guard-check' -and $window.FindName('Hint').Text -match 'fixture request failed') 'Request failure was hidden or continued'
            } else {
                Assert ($sawCheck -and ($actions -join ',') -eq 'guard-check,check') 'Recheck did not refresh the basic result'
                Assert ($window.FindName('BasicStamp').Text -eq 'fresh manual fixture') 'The old timestamp survived'
                if ($mode -eq 'check-failed') {Assert ($window.FindName('StatusText').Text -match '仅作提醒') 'Incomplete evidence appeared as a pass'}
            }
        }
    }
    $results | ConvertTo-Json -Depth 4
    if (@($results | Where-Object Status -eq 'FAIL').Count) {exit 1}
} finally {
    if ($script:operation -and -not $script:operation.Process.HasExited) {$script:operation.Process.Kill()}
    $script:operation=$null
    $timer.Stop();$guardTimer.Stop();$sceneTimer.Stop();$hugTimer.Stop();$window.Close()
}
