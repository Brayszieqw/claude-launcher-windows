param([Parameter(Mandatory=$true)][string]$StateRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'claude-switch.ps1') -StateRoot $StateRoot
[void](New-Item -ItemType Directory -Path $StateRoot -Force)
$lock=$null; $probe=$null
function Save-GuardState {
    Write-JsonAtomic (Join-Path $StateRoot 'guard-state.json') $script:guardState
}
function Set-GuardNotice([string]$Phase,[string]$Reason,[string]$Kind) {
    if ($script:guardState.Phase -ne $Phase -or $script:guardState.Reason -ne $Reason -or $script:guardState.AlertKind -ne $Kind) {
        $script:guardState.Phase=$Phase; $script:guardState.Reason=$Reason; $script:guardState.AlertKind=$Kind
        Save-GuardState
    }
}
try {
    $lock=[IO.File]::Open((Join-Path $StateRoot 'guard.lock'),'OpenOrCreate','ReadWrite','None')
    $script:guardState=[pscustomobject]@{Phase='首次检查';Reason='';AlertKind='';Revision=[guid]::NewGuid().ToString('N');CheckedAt='';RequestId=''}
    Save-GuardState
    $self=Get-Process -Id $PID
    Write-JsonAtomic (Join-Path $StateRoot 'guard.json') @{Pid=$PID;StartTicks=$self.StartTime.ToUniversalTime().Ticks.ToString();Version=3}
    $nextProbe=[DateTime]::UtcNow; $lastTick=$nextProbe; $requestId=''; $probeStarted=$null
    $lastEgress=@{}
    $configPath=Join-Path $env:APPDATA 'com.follow\clash\config.yaml'
    $configStamp=[IO.File]::GetLastWriteTimeUtc($configPath).Ticks
    while ($true) {
        $now=[DateTime]::UtcNow
        $stamp=[IO.File]::GetLastWriteTimeUtc($configPath).Ticks
        if (($now-$lastTick).TotalSeconds -gt 15 -or $stamp -ne $configStamp) {
            if ($probe) {Stop-Job $probe; Remove-Job $probe; $probe=$null}
            $script:guardState.Revision=[guid]::NewGuid().ToString('N')
            $configStamp=$stamp; $nextProbe=$now
            Set-GuardNotice '重新检查' '睡眠恢复或配置变化，正在重新核验。' $script:guardState.AlertKind
        }
        $health=Get-ProtectionHealth (Get-Settings $StateRoot)
        if (-not $health.Healthy) {
            Set-GuardNotice '警报' '代理内核、TUN 或本地代理端口暂不可用。请检查网络；Claude 和 Claude Code 继续运行。' 'Proxy'
        } elseif ($script:guardState.AlertKind -eq 'Proxy') {
            $nextProbe=$now
            Set-GuardNotice '重新检查' '代理已恢复，正在重新核验出口。' 'Proxy'
        }
        if ($probe -and (($now-$probeStarted).TotalSeconds -gt 75 -or $probe.State -in @('Completed','Failed','Stopped'))) {
            $network=[pscustomobject]@{State='unknown';Detail='后台核验超时或未完成。'}
            if ($probe.State -eq 'Completed') {
                try {$network=Receive-Job $probe -ErrorAction Stop} catch {$network=[pscustomobject]@{State='unknown';Detail='后台核验失败，未取得有效结果。'}}
            } else {Stop-Job $probe}
            Remove-Job $probe; $probe=$null
            if (-not $health.Healthy) {
                Set-GuardNotice '警报' '代理内核、TUN 或本地代理端口暂不可用。请检查网络；Claude 和 Claude Code 继续运行。' 'Proxy'
            } elseif ($network.State -eq 'fail') {
                Set-GuardNotice '警报' $network.Detail 'Network'
            } elseif ($network.State -ne 'ok') {
                Set-GuardNotice '检测受限' ('暂时无法确认当前网络；超时或服务错误不等于已确认泄露。'+$network.Detail) 'Unknown'
            } else {
                $changed=@(foreach ($item in $network.Observations) {
                    $key=$item.Provider+'|'+$item.Route+'|'+$item.Family
                    if ($lastEgress.ContainsKey($key) -and $lastEgress[$key] -ne $item.Hash) {$key}
                })
                $lastEgress=@{}
                foreach ($item in $network.Observations) {$lastEgress[$item.Provider+'|'+$item.Route+'|'+$item.Family]=$item.Hash}
                if ($changed.Count) {
                    Set-GuardNotice '警报' '检测到出口 IP 发生变化；当前仍为星链且本轮出口一致。继续观察，后续核验稳定后停止提醒。' 'IPChanged'
                } else {Set-GuardNotice '守护中' '' ''}
            }
            $script:guardState.CheckedAt=[DateTime]::UtcNow.ToString('o')
            if ($requestId) {$script:guardState.RequestId=$requestId}
            Save-GuardState; $requestId=''
            $nextProbe=[DateTime]::UtcNow.AddSeconds($(if ($network.State -eq 'ok') {60} else {15}))
        }
        $requestPath=Join-Path $StateRoot 'guard-check.json'
        if (Test-Path -LiteralPath $requestPath) {
            $request=Read-GuardJson $requestPath
            if ($request.Id -ne $script:guardState.RequestId -and $request.Id -ne $requestId) {
                $requestId=[string]$request.Id
                if ($probe) {Stop-Job $probe; Remove-Job $probe; $probe=$null}
                $age=([DateTime]::UtcNow-[DateTime]::Parse($request.RequestedAt).ToUniversalTime()).TotalSeconds
                if ($age -lt 0 -or $age -gt 40 -or $request.Revision -ne $script:guardState.Revision) {
                    $script:guardState.RequestId=$requestId
                    Set-GuardNotice '检测受限' '检查请求已过期或本机状态变化，请重新检查。' 'Unknown'
                    Save-GuardState; $requestId=''
                } else {
                    $script:guardState.Phase='重新检查'; Save-GuardState; $nextProbe=$now
                }
            }
        }
        if (-not $probe -and $now -ge $nextProbe) {
            $probeStarted=$now
            $probe=Start-Job -ArgumentList $PSScriptRoot,$StateRoot -ScriptBlock {
                param($Package,$Root)
                . (Join-Path $Package 'claude-switch.ps1') -StateRoot $Root
                Get-GuardEvidence $Root
            }
        }
        $lastTick=[DateTime]::UtcNow
        Start-Sleep -Seconds 2
    }
} catch {
    $failure=$_.Exception.Message
    if ($lock) {
        Set-GuardNotice '检测受限' '网络检测发生错误，助手将重新启动监测。Claude 和 Claude Code 继续运行。' 'Unknown'
        ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+' '+$failure) | Out-File -LiteralPath (Join-Path $StateRoot 'guard-error.log') -Append -Encoding utf8
    }
    exit 1
} finally {
    if ($probe) {Stop-Job $probe; Remove-Job $probe}
    if ($lock) {$lock.Dispose()}
}
