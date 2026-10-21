function Save-DiagnosticReport($Root,$Result,[ValidateSet('Basic','Deep','Network','Fingerprint','FlClash')]$Kind) {
    # Persist only the display contract; app paths, account snapshots and raw provider bodies stay out.
    $checkedAt=if ($Result.CheckedAt) {[string]$Result.CheckedAt} else {Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'}
    $report=[pscustomobject]@{Schema=1;Version='0.9.0';Kind=$Kind;CheckedAt=$checkedAt;Checks=@($Result.Checks);Observations=@($Result.Observations);Message=$Result.Message}
    if (-not $report.Message) { $report.Message='本地诊断记录；不代表账号状态。' }
    $directory=Join-Path $Root 'diagnostics'
    $path=Join-Path $directory ($Kind+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)+'.json')
    Write-JsonAtomic $path $report
    $Result | Add-Member -NotePropertyName ReportPath -NotePropertyValue $path
    $Result
}

function Get-GuardSummary($Root) {
    $statePath=Join-Path $Root 'guard-state.json'
    if (Test-Path -LiteralPath $statePath) {
        try {
            $state=Read-GuardJson $statePath
            $record=Read-GuardJson (Join-Path $Root 'guard.json')
            $process=Get-Process -Id $record.Pid -ErrorAction SilentlyContinue
            if (-not $process -or $process.StartTime.ToUniversalTime().Ticks.ToString() -ne $record.StartTicks) {
                return '全时段守护未运行；正在尝试重新启动。'
            }
            if (-not $state.CheckedAt) {return '全时段守护 · '+$state.Phase+'，首次完整核验尚未完成。'}
            $time=[DateTime]::Parse($state.CheckedAt).ToUniversalTime()
            $age=([DateTime]::UtcNow-$time).TotalSeconds
            if ($age -lt 0 -or $age -gt 180) {return '全时段守护最近结果已过期，当前归属未验证。'}
            return '全时段守护 · '+$state.Phase+'。'+$state.Reason+' 最近核验：'+$time.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss')
        } catch {return '全时段守护状态不可读，不能确认当前保护。'}
    }
    $recordPath=Join-Path $Root 'guard.json'
    if (-not (Test-Path -LiteralPath $recordPath)) { return '会话守护未启动；通过检查并打开 Claude 后自动启动。' }
    try {
        $record=Read-GuardJson $recordPath
        $process=Get-Process -Id $record.Pid -ErrorAction SilentlyContinue
        if (-not $process -or $process.StartTime.ToUniversalTime().Ticks.ToString() -ne $record.StartTicks) { return '会话守护未运行；再次打开 Claude 时会重新检查并启动。' }
        $path=Join-Path $Root 'guard-observations.jsonl'
        if (-not (Test-Path -LiteralPath $path)) { return '会话守护运行中；首次后台出口核验尚未完成。' }
        $observation=Get-Content -LiteralPath $path -Tail 1 -Encoding UTF8 | ConvertFrom-Json
        if ($observation.Pid -ne $record.Pid -or $observation.StartTicks -ne $record.StartTicks) { return '会话守护运行中；本次会话尚无出口核验结果。' }
        $time=[DateTime]::Parse($observation.CheckedAt).ToUniversalTime()
        $age=([DateTime]::UtcNow-$time).TotalSeconds
        if ($age -lt 0 -or $age -gt 180) { return '会话守护运行中；最近出口结果已过期，当前归属未验证。' }
        $label=switch ($observation.State) {'ok' {'已核验星链'} 'fail' {'发现非星链'} default {'出口未验证'}}
        '守护 '+$time.ToLocalTime().ToString('HH:mm:ss')+' · '+$label+'。'+$observation.Detail
    } catch { return '会话守护状态暂不可读，不能确认最新核验结果。' }
}

function Get-DiagnosticReports($Root) {
    $directory=Join-Path $Root 'diagnostics'
    if (-not (Test-Path -LiteralPath $directory)) { return @() }
    @(Get-ChildItem -LiteralPath $directory -File -Filter '*.json' | Sort-Object Name -Descending | ForEach-Object {
        $file=$_
        try {
            $report=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            if ($report.Schema -ne 1 -or $report.Kind -notin @('Basic','Deep','Network','Fingerprint','FlClash') -or -not $report.CheckedAt -or -not $report.Checks) { throw '记录结构不支持' }
            [pscustomobject]@{Path=$file.FullName;Kind=$report.Kind;CheckedAt=$report.CheckedAt;Report=$report;Error=''}
        } catch {
            # Surface corrupt records without losing the remaining history.
            [pscustomobject]@{Path=$file.FullName;Kind='Error';CheckedAt=$file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss.fff');Report=$null;Error='记录无法读取：'+$file.Name}
        }
    } | Sort-Object CheckedAt -Descending)
}

function Compare-DiagnosticReports($Current,$Previous) {
    if (-not $Previous -or $Current.Kind -ne $Previous.Kind) { return '暂无同类历史记录。' }
    $changes=New-Object System.Collections.Generic.List[string]
    foreach ($row in @($Current.Checks)) {
        $old=@($Previous.Checks | Where-Object Name -eq $row.Name)
        if (-not $old.Count) { $changes.Add($row.Name+'：新增项目') }
        elseif ($old[0].State -ne $row.State) { $changes.Add($row.Name+'：'+$old[0].State+' → '+$row.State) }
    }
    foreach ($item in @($Current.Observations | Where-Object {$_ -and $_.Type -in @('Egress','Fingerprint')})) {
        $old=@($Previous.Observations | Where-Object {$_.Type -eq $item.Type -and $_.Provider -eq $item.Provider -and $_.Route -eq $item.Route -and $_.Family -eq $item.Family -and $_.Key -eq $item.Key})
        if ($old.Count -and $item.Hash -and $old[0].Hash -and $old[0].Hash -ne $item.Hash) {
            $name=if ($item.Type -eq 'Fingerprint') {$item.Key} else {$item.Provider+' '+$item.Route+' '+$item.Family}
            $changes.Add($name+'：摘要变化')
        }
    }
    if ($Current.Kind -eq 'Network') {
        foreach ($route in @('System','Proxy')) {
            $now=@($Current.Observations | Where-Object { $_.Type -eq 'DNS' -and $_.Route -eq $route } | ForEach-Object Hash | Sort-Object -Unique)
            $old=@($Previous.Observations | Where-Object { $_.Type -eq 'DNS' -and $_.Route -eq $route } | ForEach-Object Hash | Sort-Object -Unique)
            if (($now -join ',') -ne ($old -join ',')) { $changes.Add('DNS '+$route+'：解析器集合变化（可能包含未完成的探测）') }
        }
    }
    '对比 '+$Previous.CheckedAt+"`n"+$(if ($changes.Count) {$changes -join "`n"} else {'已记录项目的状态与可比较摘要未变化。'})+"`n变化不直接等于泄漏或账号风险；升级检测算法也会产生差异。"
}

function ConvertTo-DiagnosticMarkdown($Report) {
    $lines=New-Object System.Collections.Generic.List[string]
    $lines.Add('# Claude 启动助手 · 诊断记录')
    $lines.Add(''); $lines.Add('版本 '+$Report.Version+' · '+$Report.Kind+' · '+$Report.CheckedAt)
    $lines.Add(''); $lines.Add('IP 已转换为摘要。记录仅代表本次探测，不包含 Claude 登录数据；仍含设备与网络归属信息。')
    foreach ($row in @($Report.Checks)) {
        $lines.Add(''); $lines.Add('## '+$row.Name+' ['+$row.State+']')
        $lines.Add(''); $lines.Add([string]$row.Detail)
        if ($row.Source) {$lines.Add('');$lines.Add('来源：'+$row.Source)}
        if ($row.Evidence) {$lines.Add('');$lines.Add('测量细节：'+$row.Evidence)}
        if ($row.Advice) {$lines.Add('');$lines.Add('解释：'+$row.Advice)}
    }
    $lines -join "`r`n"
}

function Export-DiagnosticReport($Report,[string]$Path) {
    $extension=[IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extension -notin @('.json','.md')) { throw '导出格式只支持 .json 或 .md。' }
    if (Test-Path -LiteralPath $Path) { Copy-Item -LiteralPath $Path -Destination ($Path+'.backup-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'-'+[guid]::NewGuid().ToString('N')) -ErrorAction Stop }
    $content=if ($extension -eq '.json') {$Report | ConvertTo-Json -Depth 12} else {ConvertTo-DiagnosticMarkdown $Report}
    [IO.File]::WriteAllText($Path,$content,(New-Object Text.UTF8Encoding($true)))
}
