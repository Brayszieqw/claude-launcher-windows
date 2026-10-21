param([string]$WorkRoot=(Join-Path $env:TEMP ('ClaudeDeadlineUi-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$package=Split-Path -Parent $PSScriptRoot
[void](New-Item -ItemType Directory -Path $WorkRoot -Force)
$fixture=Join-Path $WorkRoot 'backend-fixture.ps1'
[IO.File]::WriteAllText($fixture,'Start-Sleep -Seconds 90')
$text=[IO.File]::ReadAllText((Join-Path $package 'SwitcherUI.ps1'))
$text=$text -replace '(?m)^\[void\]\$window\.ShowDialog\(\)\s*$',''
$text=$text.Replace("`$core=Join-Path `$PSScriptRoot 'claude-switch.ps1'",("`$core='"+$fixture.Replace("'","''")+"'"))
$text=$text.Replace('$PSScriptRoot',("'"+$package.Replace("'","''")+"'"))
. ([scriptblock]::Create($text)) -StateRoot (Join-Path $WorkRoot 'state')
function Assert($Condition,$Message) {if (-not $Condition) {throw $Message}}
function Wait-Check {
    $watch=$script:operation.Watch
    while ($script:operation -and $watch.ElapsedMilliseconds -lt 78000) {
        $frame=New-Object Windows.Threading.DispatcherFrame
        [void]$window.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background,[Action]{$frame.Continue=$false})
        [Windows.Threading.Dispatcher]::PushFrame($frame)
        Start-Sleep -Milliseconds 10
    }
    Assert (-not $script:operation) 'UI remained busy after the deadline'
    $watch.ElapsedMilliseconds
}
try {
    $rows=@('Claude 桌面版','代理内核','TUN 网卡','本地代理端口','代理 HTTPS 出口' | ForEach-Object {[pscustomobject]@{Name=$_;State='ok';Detail='fixture';Blocking=$false}})
    $passed=[pscustomobject]@{Ready=$true;Checks=$rows;CheckedAt='fixture'}
    Show-Check $passed
    Start-Action 'check' '' {param($r) Show-Check $r}
    $workerId=$script:operation.Process.Id
    $timeoutMs=Wait-Check
    Assert ($timeoutMs -ge 75000 -and $timeoutMs -lt 77000) ('UI did not allow HTTPS plus local preparation: '+$timeoutMs+' ms')
    Assert ($window.FindName('BtnStart').IsEnabled -and -not $script:busy) 'Timeout locked launch or kept controls busy'
    Assert ($window.FindName('StatusText').Text -match '已停止.*75 秒') 'Timeout status was missing'
    Assert (@($window.FindName('Tiles').ItemsSource | Where-Object Label -eq '未验证').Count -eq 5) 'Timeout kept stale passing tiles'
    Assert (-not (Get-Process -Id $workerId -ErrorAction SilentlyContinue)) 'Timed-out check worker was left running'
    $json=$passed | ConvertTo-Json -Depth 5 -Compress
    [IO.File]::WriteAllText($fixture,("[Console]::OutputEncoding=New-Object Text.UTF8Encoding(`$false)`r`n'"+$json.Replace("'","''")+"'"),(New-Object Text.UTF8Encoding($true)))
    Start-Action 'check' '' {param($r) Show-Check $r}
    $passMs=Wait-Check
    Assert ($passMs -lt 5000 -and $window.FindName('BtnStart').IsEnabled) 'A complete pass did not return early and unlock'
    [pscustomobject]@{Status='PASS';TimeoutMilliseconds=$timeoutMs;EarlyPassMilliseconds=$passMs;TimeoutWorkerStopped=$true;StalePassCleared=$true;AllFivePassed=$true} | ConvertTo-Json
} finally {$timer.Stop();$sceneTimer.Stop();$hugTimer.Stop();$window.Close()}
