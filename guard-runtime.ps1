function Get-ClaudeDomains {
    # Official Desktop / Code network requirements; wildcard hosts are added from the Windows DNS cache.
    $fixed=@('claude.ai','claude.com','api.anthropic.com','anthropic.com','a-api.anthropic.com','a-cdn.anthropic.com','s-cdn.anthropic.com','assets-proxy.anthropic.com','a.claude.ai','assets.claude.ai','downloads.claude.ai','platform.claude.com','mcp-proxy.anthropic.com','bridge.claudeusercontent.com','code.claude.com')
    $discovered=@(Get-DnsClientCache -ErrorAction Stop | ForEach-Object Entry | Where-Object {Test-ClaudeDomain $_})
    @($fixed+$discovered | ForEach-Object {$_.ToLowerInvariant().TrimEnd('.')} | Sort-Object -Unique)
}

function Test-ClaudeDomain([string]$Name) {
    $Name -match '(?i)^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*(?:anthropic\.com|claude\.ai|claude\.com|claude\.app|claudeusercontent\.com|claudemcpcontent\.com)\.?$'
}

function Get-ClaudeDomainPolicy([string]$Text,[string]$HostName) {
    $inside=$false
    foreach ($line in ($Text -split '\r?\n')) {
        if ($line -match '^rules:\s*$') {$inside=$true; continue}
        if (-not $inside -or $line -match '^\s*(?:#.*)?$') {continue}
        if ($line -match '^[^\s-]') {break}
        if ($line -notmatch '^\s*-\s*(.+?)\s*$') {return ''}
        $rule=$Matches[1]
        if ($rule -match "^'([^']*)'$" -or $rule -match '^"([^"\\]*)"$') {$rule=$Matches[1]}
        elseif ($rule -match '["''#{}[\]\\]') {return ''}
        $parts=$rule.Split(',')
        if ($parts.Count -ne 3) {return ''}
        $value=$parts[1].Trim().ToLowerInvariant(); $target=$parts[2].Trim()
        $matched=switch ($parts[0]) {
            'DOMAIN' {$HostName -ieq $value}
            'DOMAIN-SUFFIX' {$HostName -ieq $value -or $HostName.EndsWith('.'+$value,[StringComparison]::OrdinalIgnoreCase)}
            'DOMAIN-KEYWORD' {$HostName.IndexOf($value,[StringComparison]::OrdinalIgnoreCase) -ge 0}
            # An earlier provider, process or IP rule may override the later domain rule.
            default {return ''}
        }
        if ($matched) {
            if ($target -in @('DIRECT','REJECT','REJECT-DROP','PASS','GLOBAL') -or -not $target) {return ''}
            return $target
        }
    }
    ''
}

function Get-GuardDnsCheck {
    try {
        $snapshot=Get-FlClashSnapshot
        $hijack=@(Read-FlClashGeneratedField $snapshot.Generated 'tun' 'dns-hijack')
        $udp=@($hijack | Where-Object {$_ -in @('any:53','udp://any:53','0.0.0.0:53','udp://0.0.0.0:53')}).Count -gt 0
        $tcp=@($hijack | Where-Object {$_ -in @('tcp://any:53','tcp://0.0.0.0:53')}).Count -gt 0
        if (-not $udp -or -not $tcp) {return New-Check '守护 DNS' 'fail' '生成配置未同时接管 UDP / TCP 53，存在 DNS 防护缺口。' $true}
        $direct=@(Read-FlClashGeneratedField $snapshot.Generated 'dns' 'direct-nameserver')
        if (@($direct | Where-Object {$_ -and $_ -notin @('[]','null','~')}).Count) {
            return New-Check '守护 DNS' 'fail' '存在独立直连 DNS 上游，无法证明它遵循受保护的解析路径。' $true
        }
        New-Check '守护 DNS' 'ok' '已核验 UDP / TCP DNS 接管且没有独立直连解析上游；此项是配置证据，不是全部应用 DNS 流量证明。'
    } catch {
        New-Check '守护 DNS' 'unknown' 'DNS 配置读取或解析失败，当前无法核验。' $true
    }
}

function Read-GuardJson([string]$Path) {
    # Readers allow an atomic replacement while retaining their own complete file snapshot.
    $stream=[IO.File]::Open($Path,'Open','Read',([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $reader=New-Object IO.StreamReader($stream,[Text.Encoding]::UTF8,$true)
    try {$reader.ReadToEnd() | ConvertFrom-Json} finally {$reader.Dispose()}
}

function Read-GuardState($Root) {
    $path=Join-Path $Root 'guard-state.json'
    if (-not (Test-Path -LiteralPath $path)) {return [pscustomobject]@{Phase='未启动';Reason='';AlertKind='';Revision='';CheckedAt=''}}
    Read-GuardJson $path
}

function Get-GuardEvidence($Root) {
    $settings=Get-Settings $Root
    $health=Get-ProtectionHealth $settings
    if (-not $health.Healthy) {return [pscustomobject]@{State='unknown';Detail='代理暂不可用，请查看实时监测提示。'}}
    $rows=@((Get-FlClashCheck).Checks)+@(Get-GuardDnsCheck)
    $bad=@($rows | Where-Object Blocking)
    if ($bad.Count) {
        return [pscustomobject]@{State=$(if (@($bad | Where-Object State -eq 'fail').Count) {'fail'} else {'unknown'});Detail=($bad.Detail -join ' ');Checks=$rows}
    }
    Get-LaunchNetworkEvidence $settings
}

function Request-GuardCheck($Root) {
    if (-not (Get-GuardStatus $Root)) {throw '监测未运行，请先打开助手。'}
    $id=[guid]::NewGuid().ToString('N')
    $state=Read-GuardState $Root
    Write-JsonAtomic (Join-Path $Root 'guard-check.json') @{Id=$id;Revision=$state.Revision;RequestedAt=[DateTime]::UtcNow.ToString('o')}
    $deadline=[DateTime]::UtcNow.AddSeconds(85)
    do {
        Start-Sleep -Milliseconds 200
        $state=Read-GuardState $Root
        if ($state.RequestId -eq $id -and $state.Phase -ne '重新检查') {
            return [pscustomobject]@{Message=('重新检查完成。'+$state.Reason);Phase=$state.Phase}
        }
    } while ([DateTime]::UtcNow -lt $deadline)
    throw '监测没有在期限内完成检查，请稍后重试。Claude 仍可继续使用。'
}

function Set-GuardAutostart {
    $folder=[Environment]::GetFolderPath('Startup')
    $path=Join-Path $folder 'Claude 启动助手守护.lnk'
    $shell=New-Object -ComObject WScript.Shell
    $shortcut=$shell.CreateShortcut($path)
    $exe=Join-Path $PSScriptRoot 'ClaudeLauncher.exe'
    if ($shortcut.TargetPath -eq $exe -and $shortcut.Arguments -eq '--tray') {return}
    if (Test-Path -LiteralPath $path) {Copy-Item -LiteralPath $path -Destination ($path+'.backup-'+(Get-Date -Format yyyyMMdd-HHmmss-fff))}
    $shortcut.TargetPath=$exe; $shortcut.Arguments='--tray'; $shortcut.WorkingDirectory=$PSScriptRoot
    $shortcut.Description='登录 Windows 后启动 Claude 全时段守护'
    $shortcut.IconLocation=(Join-Path $PSScriptRoot 'launcher.ico')+',0'
    $shortcut.Save()
}
