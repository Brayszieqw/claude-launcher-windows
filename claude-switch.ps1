param(
    [ValidateSet('check','flclash-check','deep-check','network-insights','fingerprint-check','fingerprint-save','start','status','baseline','switch','restore','guard-status','guard-start','guard-check','account-add','account-rename','environment-read','timezone-set','format-set','language-first')]
    [string]$Command = 'status',
    [string]$Account = '',
    [string]$NameEncoded = '',
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'ClaudeSwitcherWindows')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'network-probes.ps1')
. (Join-Path $PSScriptRoot 'environment-insights.ps1')
. (Join-Path $PSScriptRoot 'flclash-checks.ps1')
. (Join-Path $PSScriptRoot 'diagnostic-reports.ps1')
. (Join-Path $PSScriptRoot 'guard-runtime.ps1')

function Get-Settings($Root) {
    $path = Join-Path $Root 'settings.json'
    if (Test-Path -LiteralPath $path) { return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json }
    [pscustomobject]@{ ProxyPort = 7890; EgressHash = ''; Country = '' }
}

function Write-JsonAtomic($Path, $Value) {
    $parent = Split-Path -Parent $Path
    [void](New-Item -ItemType Directory -Path $parent -Force)
    $temporary = Join-Path $parent ([guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($true)))
    if (Test-Path -LiteralPath $Path) {
        $backup = $Path + '.backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N')
        [IO.File]::Replace($temporary, $Path, $backup)
    } else { [IO.File]::Move($temporary, $Path) }
}

function Get-TextHash([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)) | ForEach-Object { $_.ToString('x2') }) }
    finally { $sha.Dispose() }
}

function Get-ClaudeInstall {
    $package = Get-AppxPackage -Name 'Claude' -ErrorAction Stop | Sort-Object Version -Descending | Select-Object -First 1
    if ($package) {
        $exe = Join-Path $package.InstallLocation 'app\Claude.exe'
        $manifest = Get-AppxPackageManifest -Package $package.PackageFullName
        $application = @($manifest.Package.Applications.Application) | Where-Object { $_.Executable -match '(^|\\)Claude\.exe$' } | Select-Object -First 1
        if (-not $application -or -not (Test-Path -LiteralPath $exe)) { throw '商店版 Claude 的启动信息不完整。请先修复 Claude 安装。' }
        return [pscustomobject]@{
            Kind = 'Microsoft Store'; Exe = $exe
            AppId = $package.PackageFamilyName + '!' + $application.Id
            Data = Join-Path $env:LOCALAPPDATA ("Packages\" + $package.PackageFamilyName + '\LocalCache\Roaming\Claude')
        }
    }
    foreach ($candidate in @("$env:LOCALAPPDATA\AnthropicClaude\Claude.exe", "$env:LOCALAPPDATA\Programs\Claude\Claude.exe")) {
        if (Test-Path -LiteralPath $candidate) {
            return [pscustomobject]@{ Kind = '独立安装版'; Exe = $candidate; AppId = ''; Data = (Join-Path $env:APPDATA 'Claude') }
        }
    }
    throw '未找到 Claude 桌面版。'
}

function Get-DesktopProcesses($App) {
    @(Get-Process -Name 'Claude' -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path -eq $App.Exe })
}

function Get-ProtectionHealth($Settings) {
    $cores = @(Get-Process -Name 'FlClashCore','verge-mihomo' -ErrorAction SilentlyContinue)
    $adapters = @(Get-NetAdapter -IncludeHidden -ErrorAction Stop | Where-Object {
        $_.Status -eq 'Up' -and ($_.InterfaceDescription -match '^Meta Tunnel$|Mihomo' -or $_.Name -match '^(FlClash|Mihomo|Clash)')
    })
    $routedAdapters = @($adapters | Where-Object {
        $prefixes = @(Get-NetRoute -AddressFamily IPv4 -InterfaceIndex $_.ifIndex -ErrorAction Stop | ForEach-Object DestinationPrefix)
        '0.0.0.0/0' -in $prefixes -or ('0.0.0.0/1' -in $prefixes -and '128.0.0.0/1' -in $prefixes)
    })
    $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $Settings.ProxyPort -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalAddress -in @('127.0.0.1','0.0.0.0','::','::1') -and $_.OwningProcess -in @($cores.Id) })
    [pscustomobject]@{
        Core = ($cores.Count -gt 0); Tun = ($routedAdapters.Count -gt 0); Proxy = ($listeners.Count -gt 0)
        Healthy = ($cores.Count -gt 0 -and $routedAdapters.Count -gt 0 -and $listeners.Count -gt 0)
        Adapter = (($routedAdapters.Name -join ', ') + '，有 IPv4 默认 / 分割路由')
    }
}

function New-Check($Name, $State, $Detail, [bool]$Blocking = $false) {
    [pscustomobject]@{ Name=$Name; State=$State; Detail=$Detail; Blocking=$Blocking }
}

function Get-EnvironmentCheck($Root, [string]$AccountId = '') {
    $settings = Get-Settings $Root
    $state = Get-AccountState $Root
    if (-not $AccountId) { $AccountId = $state.Current }
    [void](Get-AccountProfile $state $AccountId)
    $rows = New-Object System.Collections.Generic.List[object]
    $app = $null
    try { $app = Get-ClaudeInstall; $rows.Add((New-Check 'Claude 桌面版' 'ok' $app.Kind)) }
    catch { $rows.Add((New-Check 'Claude 桌面版' 'fail' $_.Exception.Message $true)) }
    $health = Get-ProtectionHealth $settings
    $rows.Add((New-Check '代理内核' $(if ($health.Core) {'ok'} else {'fail'}) $(if ($health.Core) {'FlClash / Clash 内核正在运行'} else {'未检测到 FlClashCore 或 verge-mihomo'}) (-not $health.Core)))
    $rows.Add((New-Check 'TUN 网卡' $(if ($health.Tun) {'ok'} else {'fail'}) $(if ($health.Tun) {$health.Adapter} else {'未检测到已启用且有 IPv4 默认 / 分割路由的代理网卡'}) (-not $health.Tun)))
    $rows.Add((New-Check '本地代理端口' $(if ($health.Proxy) {'ok'} else {'fail'}) ("127.0.0.1:" + $settings.ProxyPort + '，验证监听进程归属') (-not $health.Proxy)))
    foreach ($row in (Get-FlClashCheck).Checks) {$rows.Add($row)}
    if ($health.Healthy) {$rows.Add((Get-GuardDnsCheck))}
    foreach ($row in @(Get-LocalConfigurationChecks $settings)) { $rows.Add($row) }
    $rows.Add((Get-IPv6LocalCheck))
    $network = $null
    if ($health.Healthy -and -not @($rows | Where-Object Blocking).Count) {
        $network = Get-LaunchNetworkEvidence $settings
        $rows.Add((New-Check '代理 HTTPS 出口' $network.State $network.Detail ($network.State -ne 'ok')))
        foreach ($row in $network.Checks) { $rows.Add($row) }
    } else { $rows.Add((New-Check '代理 HTTPS 出口' 'unknown' '本地启动条件未通过，未发送外部请求。请先处理代理 / FlClash 配置问题。' $true)) }
    $rows.Add((New-Check '星链出口策略' 'info' '预期 Starlink AS14593；不同轮次的 IP 变化也会提醒，同轮实测出口差异单独提示。不提供出口回显的资源域名单独显示分流规则证据。'))
    $rows.Add((New-Check '防护范围' 'info' '核验匿名 HTTPS 探测的实际出口；不等同于 Claude 登录或模型请求。监测仅作提醒，不控制 Claude 进程；IPv6、UDP、WebRTC 仍需分别检测。'))
    [pscustomobject]@{ Ready=($null -ne $app); Checks=$rows.ToArray(); App=$app; Observations=@($network.Observations); CheckedAt=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }
}

function Assert-NoPendingSwitch($Root) {
    $journalPath = Join-Path $Root 'pending-switch.json'
    if (Test-Path -LiteralPath $journalPath) {
        $journal = Get-Content -LiteralPath $journalPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $journal.Completed) { throw '检测到未完成的账号切换，请先使用账号管理中的恢复功能。' }
    }
}

function Assert-LaunchReady($Root, [string]$AccountId = '') {
    Assert-NoPendingSwitch $Root
    $check = Get-EnvironmentCheck $Root $AccountId
    if (-not $check.Ready) { throw ('无法启动：' + (($check.Checks | Where-Object Blocking | ForEach-Object Detail) -join '；')) }
    $check
}

function Save-Baseline($Root) {
    $lock = Enter-Operation $Root
    try {
        Assert-NoPendingSwitch $Root
        $settings = Get-Settings $Root
        $health = Get-ProtectionHealth $settings
        if (-not $health.Healthy) { throw '代理基础检查未通过，不能记录出口基准。' }
        $network = Get-LaunchNetworkEvidence $settings
        if ($network.State -ne 'ok') { throw $network.Detail }
        $egress = $network.Observations[0]
        $state = Get-AccountState $Root; $profile = Get-AccountProfile $state $state.Current
        $profile.EgressHash = $egress.Hash; $profile.Country = $egress.Country
        Write-JsonAtomic (Join-Path $Root 'account-state.json') $state
        [pscustomobject]@{ Message=('已为「' + $profile.Name + '」记录本次星链核验。仅保存 IP 摘要；后续按 AS14593 核验并提醒，不锁定此 IP。'); Status=(Get-AppStatus $Root) }
    } finally { $lock.Dispose() }
}

function Get-GuardStatus($Root) {
    $path = Join-Path $Root 'guard.json'
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    $record = Read-GuardJson $path
    $process = Get-Process -Id $record.Pid -ErrorAction SilentlyContinue
    if (-not $process) { return $false }
    # The guard runs as this user, so its start time is readable; a reused PID owned by a SYSTEM or elevated process reads as empty.
    $started = $process.StartTime
    if ($null -eq $started) { return $false }
    $started.ToUniversalTime().Ticks.ToString() -eq $record.StartTicks
}

function Start-Guard($Root) {
    if (Get-GuardStatus $Root) { return }
    $guard = Join-Path $PSScriptRoot 'claude-bodyguard.ps1'
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $guard + '" -StateRoot "' + $Root + '"'
    $process = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $arguments -WindowStyle Hidden -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Get-GuardStatus $Root) { return }
        if ($process.HasExited) { throw '守护进程未能启动，请查看本地守护日志。' }
        Start-Sleep -Milliseconds 100
    }
    throw '监测进程没有在 10 秒内就绪。'
}

function Start-Desktop($App) {
    if ($App.AppId) { Start-Process -FilePath 'explorer.exe' -ArgumentList ('shell:AppsFolder\' + $App.AppId) }
    else { Start-Process -FilePath $App.Exe }
}

function Start-ProtectedClaude($Root) {
    $lock = Enter-Operation $Root
    try {
        Assert-NoPendingSwitch $Root
        $app=Get-ClaudeInstall
        $notice=''
        try {Start-Guard $Root} catch {$notice='监测暂未启动：'+$_.Exception.Message}
        Start-Desktop $app
        [pscustomobject]@{ Message=('已发送 Claude 启动请求。网络异常只作警报提醒，不结束或重启 Claude / Claude Code。'+$notice) }
    } finally { $lock.Dispose() }
}

function Assert-ChildPath($Path, $Parent) {
    $resolved = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $boundary = [IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)) { throw '路径不在预期的数据目录内，操作已停止。' }
    $resolved
}

function Get-TreeManifest($Path) {
    $root = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $pending = New-Object System.Collections.Generic.Stack[string]
    $pending.Push($root)
    $items = New-Object System.Collections.Generic.List[object]
    while ($pending.Count) {
        $directory = $pending.Pop()
        if ((Get-Item -LiteralPath $directory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '数据目录包含链接，已停止复制，避免越出数据目录。' }
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '数据目录包含链接，已停止复制，避免越出数据目录。' }
            $items.Add($item)
            if ($item.PSIsContainer) { $pending.Push($item.FullName) }
        }
    }
    @($items | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($root.Length + 1)
        if ($_.PSIsContainer) { "D|$relative" }
        else { "F|$relative|$($_.Length)|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256 -ErrorAction Stop).Hash)" }
    })
}

function Get-TreeBytes($Path) {
    # Sizes only, without hashing: quick enough to check free space before Claude is closed.
    [long]$total = 0
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $total }
    $pending = New-Object System.Collections.Generic.Stack[string]
    $pending.Push([IO.Path]::GetFullPath($Path))
    while ($pending.Count) {
        foreach ($item in @(Get-ChildItem -LiteralPath $pending.Pop() -Force -ErrorAction Stop)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($item.PSIsContainer) { $pending.Push($item.FullName) } else { $total += $item.Length }
        }
    }
    $total
}

function Get-ManifestBytes($Manifest) {
    [long]$total = 0
    foreach ($line in @($Manifest)) { if ($line -like 'F|*') { $total += [long]($line.Split('|')[-2]) } }
    $total
}

function Assert-FreeSpace([object[]]$Needs) {
    # Copies that land on the same drive add up, and 1 GB stays free afterwards for Windows and Claude.
    $bytes = @{}
    foreach ($need in $Needs) {
        $drive = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($need.Path)).ToUpperInvariant()
        $bytes[$drive] = [long]$bytes[$drive] + [long]$need.Bytes
    }
    foreach ($drive in @($bytes.Keys)) {
        try { $free = (New-Object IO.DriveInfo $drive).AvailableFreeSpace } catch { continue }
        if ($free -lt $bytes[$drive] + 1GB) {
            throw ('{0} 盘剩余 {1:N1} GB，本次复制需要 {2:N1} GB，另需保留 1 GB；未开始复制，原数据保持原样。请先清理磁盘空间后重试。' -f $drive.TrimEnd('\').TrimEnd(':'), ($free / 1GB), ($bytes[$drive] / 1GB))
        }
    }
}

function Copy-VerifiedTree($Source, $Destination) {
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw '源数据目录不存在。' }
    if (Test-Path -LiteralPath $Destination) { throw '复制目标必须是全新的目录。' }
    $before = @(Get-TreeManifest $Source)
    Assert-FreeSpace @(@{ Path=$Destination; Bytes=(Get-ManifestBytes $before) })
    [void](New-Item -ItemType Directory -Path $Destination -Force)
    try {
        & "$env:SystemRoot\System32\robocopy.exe" $Source $Destination /E /COPY:DAT /DCOPY:DAT /R:0 /W:0 /XJ /NFL /NDL /NJH /NJS /NP | Out-Null
        $copyExit = $LASTEXITCODE
        if ($copyExit -ge 8) { throw "复制失败（robocopy $copyExit）；原目录和旧备份均保留。" }
        $after = @(Get-TreeManifest $Source)
        $copied = @(Get-TreeManifest $Destination)
        if (($before -join [char]10) -cne ($after -join [char]10) -or ($before -join [char]10) -cne ($copied -join [char]10)) {
            throw '文件校验不一致，未使用这份副本；原目录和旧备份均保留。'
        }
    } catch {
        # A failed or unverified copy is never kept, so it cannot fill the disk or pass for a snapshot later.
        $message = $_.Exception.Message
        Remove-Item -LiteralPath $Destination -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $Destination) { $message += ' 不完整的副本未能自动删除，可手动删除：' + $Destination }
        throw $message
    }
    $copied
}

function Stop-DesktopForSwitch($App) {
    $all = @(Get-Process -Name 'Claude' -ErrorAction SilentlyContinue)
    if (@($all | Where-Object { -not $_.Path -or $_.Path -ne $App.Exe }).Count) {
        throw '检测到 Claude Code 或无法确认身份的同名进程。请先结束相关会话，再切换账号；本工具不会关闭 Claude Code。'
    }
    foreach ($process in @(Get-DesktopProcesses $App)) { [void]$process.CloseMainWindow() }
    $deadline = [DateTime]::UtcNow.AddSeconds(12)
    do {
        if (@(Get-DesktopProcesses $App).Count -eq 0) { return }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Claude 桌面版尚未完全退出。请从托盘退出后重试；数据尚未替换。'
}

function Get-AccountState($Root) {
    $path = Join-Path $Root 'account-state.json'
    if (Test-Path -LiteralPath $path) {
        $state = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($state.Version -eq 2) {
            $ids = @($state.Profiles | ForEach-Object Id)
            if (-not $ids.Count -or @($ids | Select-Object -Unique).Count -ne $ids.Count -or
                @($ids | Where-Object { $_ -cnotmatch '^(primary|A|B|p-[a-f0-9]{32})$' }).Count -or $state.Current -cnotin $ids) {
                throw '账号目录记录无效，请保留现有文件并检查 account-state.json 的备份。'
            }
            return $state
        }
        if ($state.Version) { throw '不支持此账号目录版本，请使用对应版本的软件。' }
        $profiles = @((New-AccountProfile 'A' '主账号'), (New-AccountProfile 'B' '备用账号'))
        $profiles[0].Snapshot = [string]$state.A; $profiles[1].Snapshot = [string]$state.B
        $state = [pscustomobject]@{ Version=2; Current=$(if ($state.Current -eq 'B') {'B'} else {'A'}); Profiles=$profiles }
    } else {
        $state = [pscustomobject]@{ Version=2; Current='primary'; Profiles=@(New-AccountProfile 'primary' '主账号') }
    }
    # Older releases stored one global baseline. Carry it to the active profile only, in memory until a write is requested.
    $settings = Get-Settings $Root
    $profile = Get-AccountProfile $state $state.Current
    $profile.EgressHash = [string]$settings.EgressHash; $profile.Country = [string]$settings.Country
    $state
}

function New-AccountProfile([string]$Id, [string]$Name) {
    [pscustomobject]@{ Id=$Id; Name=$Name; Snapshot=''; EgressHash=''; Country='' }
}

function Get-AccountProfile($State, [string]$Id) {
    $found = @($State.Profiles | Where-Object { $_.Id -ceq $Id })
    if ($found.Count -ne 1) { throw '未找到选中的账号，请刷新账号列表后重试。' }
    $found[0]
}

function Get-ValidAccountName([string]$Name, $State, [string]$ExcludeId = '') {
    $name = $Name.Trim()
    if ($name.Length -lt 1 -or $name.Length -gt 32 -or $name -match '[\p{Cc}]') { throw '账号名称须为 1–32 个字符，不能包含换行或控制字符。' }
    if (@($State.Profiles | Where-Object { $_.Id -ne $ExcludeId -and $_.Name -eq $name }).Count) { throw '已有同名账号，请换一个名称。' }
    $name
}

function Add-Account($Root, [string]$Name) {
    $lock = Enter-Operation $Root
    try {
        Assert-NoPendingSwitch $Root
        $state = Get-AccountState $Root
        $name = Get-ValidAccountName $Name $state
        $profile = New-AccountProfile ('p-' + [guid]::NewGuid().ToString('N')) $name
        $state.Profiles = @($state.Profiles) + $profile
        Write-JsonAtomic (Join-Path $Root 'account-state.json') $state
        [pscustomobject]@{ Message=('已添加「'+$name+'」。当前 Claude 会话保持原样；首次切换后请自行登录。'); Status=(Get-AppStatus $Root); Selected=$profile.Id }
    } finally { $lock.Dispose() }
}

function Rename-Account($Root, [string]$Id, [string]$Name) {
    $lock = Enter-Operation $Root
    try {
        Assert-NoPendingSwitch $Root
        $state = Get-AccountState $Root; $profile = Get-AccountProfile $state $Id
        $profile.Name = Get-ValidAccountName $Name $state $Id
        Write-JsonAtomic (Join-Path $Root 'account-state.json') $state
        [pscustomobject]@{ Message='名称已更新；账号标识、会话快照和出口基准保持不变。'; Status=(Get-AppStatus $Root); Selected=$Id }
    } finally { $lock.Dispose() }
}

function Save-Snapshot($Root, $Data, [ValidatePattern('^(primary|A|B|p-[a-f0-9]{32})$')]$Name) {
    $stamp = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N')
    $snapshot = Join-Path $Root ("accounts\" + $Name + '\' + $stamp)
    $manifest = @(Copy-VerifiedTree $Data (Join-Path $snapshot 'data'))
    Write-JsonAtomic (Join-Path $snapshot 'manifest.json') ([pscustomobject]@{ Created=(Get-Date).ToUniversalTime().ToString('o'); Files=$manifest })
    $snapshot
}

function Assert-Snapshot($Root, $Snapshot) {
    [void](Assert-ChildPath $Snapshot (Join-Path $Root 'accounts'))
    $record = Get-Content -LiteralPath (Join-Path $Snapshot 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $actual = @(Get-TreeManifest (Join-Path $Snapshot 'data'))
    if (($actual -join [char]10) -cne (@($record.Files) -join [char]10)) { throw '目标快照校验失败，原数据未替换。' }
}

function Enter-Operation($Root) {
    [void](New-Item -ItemType Directory -Path $Root -Force)
    try { [IO.File]::Open((Join-Path $Root 'operation.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
    catch [IO.IOException] { throw '另一项操作正在进行，请等待完成。' }
}

function Move-DataDirectory($Source, $Destination, $Parent) {
    [void](Assert-ChildPath $Source $Parent); [void](Assert-ChildPath $Destination $Parent)
    if (Test-Path -LiteralPath $Destination) { throw '目标目录已存在，拒绝覆盖。' }
    Move-Item -LiteralPath $Source -Destination $Destination -ErrorAction Stop
}

function Replace-DataDirectory($Data, $Stage, $Backup) {
    $parent = Split-Path -Parent $Data
    [void](Assert-ChildPath $Data $parent); [void](Assert-ChildPath $Stage $parent); [void](Assert-ChildPath $Backup $parent)
    $hadData = Test-Path -LiteralPath $Data
    if ($hadData) { Move-DataDirectory $Data $Backup $parent }
    try { Move-DataDirectory $Stage $Data $parent }
    catch {
        if ($hadData -and -not (Test-Path -LiteralPath $Data)) { Move-DataDirectory $Backup $Data $parent }
        throw
    }
}

function Switch-Account($Root, [string]$Target) {
    $lock = Enter-Operation $Root
    try {
        $state = Get-AccountState $Root
        $targetProfile = Get-AccountProfile $state $Target
        $check = Assert-LaunchReady $Root $Target
        $app = $check.App
        if ($state.Current -eq $Target) { return [pscustomobject]@{ Message=('当前已是「' + $targetProfile.Name + '」，未替换数据。请回到概览，拥抱一下通过检查后再启动 Claude。'); Status=(Get-AppStatus $Root) } }
        # Check room for both copies before Claude is closed: this account's snapshot, then the target's data beside the live folder.
        $needs = @()
        if (Test-Path -LiteralPath $app.Data) { $needs += @{ Path=(Join-Path $Root 'accounts'); Bytes=(Get-TreeBytes $app.Data) } }
        if ($targetProfile.Snapshot) { $needs += @{ Path=(Split-Path -Parent $app.Data); Bytes=(Get-TreeBytes (Join-Path $targetProfile.Snapshot 'data')) } }
        Assert-FreeSpace $needs
        Stop-DesktopForSwitch $app
        $hasData = Test-Path -LiteralPath $app.Data
        if ($hasData) {
            $from = $state.Current
            $snapshot = Save-Snapshot $Root $app.Data $from
            (Get-AccountProfile $state $from).Snapshot = $snapshot
            Write-JsonAtomic (Join-Path $Root 'account-state.json') $state
        }
        $parent = Split-Path -Parent $app.Data
        $stamp = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N')
        $stage = Join-Path $parent ('Claude.switcher-stage-' + $stamp)
        $backup = Join-Path $parent ('Claude.switcher-backup-' + $stamp)
        if ($targetProfile.Snapshot) {
            Assert-Snapshot $Root $targetProfile.Snapshot
            [void](Copy-VerifiedTree (Join-Path $targetProfile.Snapshot 'data') $stage)
        } else { [void](New-Item -ItemType Directory -Path $stage -Force) }
        $previous = $state.Current
        Write-JsonAtomic (Join-Path $Root 'pending-switch.json') ([pscustomobject]@{ Data=$app.Data; Stage=$stage; Backup=$backup; HadData=$hasData; From=$previous; To=$Target })
        try { Replace-DataDirectory $app.Data $stage $backup }
        catch {
            if (((Test-Path -LiteralPath $app.Data) -or -not $hasData) -and -not (Test-Path -LiteralPath $backup)) {
                Write-JsonAtomic (Join-Path $Root 'pending-switch.json') ([pscustomobject]@{ Completed=$true; RolledBack=$true; From=$previous; To=$Target })
            }
            throw
        }
        $state.Current=$Target
        Write-JsonAtomic (Join-Path $Root 'account-state.json') $state
        Write-JsonAtomic (Join-Path $Root 'pending-switch.json') ([pscustomobject]@{ Completed=$true; Backup=$backup; HadData=$hasData; From=$previous; To=$Target })
        [pscustomobject]@{ Message=('已切换到「' + $targetProfile.Name + '」。旧数据和快照均已保留，请回到概览，拥抱一下通过检查后再启动 Claude。'); Status=(Get-AppStatus $Root); Backup=$backup }
    } finally { $lock.Dispose() }
}

function Restore-LastData($Root) {
    $lock = Enter-Operation $Root
    try {
        $app = Get-ClaudeInstall
        $pendingPath = Join-Path $Root 'pending-switch.json'
        if (-not (Test-Path -LiteralPath $pendingPath)) { throw '没有可恢复的切换记录。' }
        $pending = Get-Content -LiteralPath $pendingPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $state = Get-AccountState $Root
        $from = if ($pending.From -eq 'none') { $state.Profiles[0].Id } else { $pending.From }
        [void](Get-AccountProfile $state $from)
        $backup = [string]$pending.Backup
        $parent = Split-Path -Parent $app.Data
        [void](Assert-ChildPath $backup $parent)
        if ((Split-Path -Leaf $backup) -notlike 'Claude.switcher-backup-*') { throw '恢复记录中的备份路径无效，现有数据保持原样。' }
        if ($pending.HadData -ne $false -and -not (Test-Path -LiteralPath $backup)) {
            # Data and stage both present, with no backup, identifies an interrupted first rename or its rollback.
            $oldStage=[string]$pending.Stage
            if (-not $pending.Completed -and $pending.Data -eq $app.Data -and $state.Current -eq $from -and $oldStage) {
                [void](Assert-ChildPath $oldStage $parent)
                if ((Split-Path -Leaf $oldStage) -like 'Claude.switcher-stage-*' -and
                    (Test-Path -LiteralPath $oldStage -PathType Container) -and (Test-Path -LiteralPath $app.Data -PathType Container)) {
                    Write-JsonAtomic $pendingPath ([pscustomobject]@{Completed=$true;RolledBack=$true;From=$pending.From;To=$pending.To;Stage=$oldStage})
                    return [pscustomobject]@{Message='上次操作尚未替换当前数据，已解除未完成状态；原数据及暂存目录均已保留。';Status=(Get-AppStatus $Root)}
                }
            }
            throw '未找到切换前的数据备份，现有数据保持原样。'
        }
        if ($pending.HadData -ne $false) { Assert-FreeSpace @(@{ Path=$parent; Bytes=(Get-TreeBytes $backup) }) }
        Stop-DesktopForSwitch $app
        $stamp = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N')
        $stage = Join-Path $parent ('Claude.switcher-stage-' + $stamp)
        if ($pending.HadData -eq $false) { [void](New-Item -ItemType Directory -Path $stage -Force) }
        else { [void](Copy-VerifiedTree $backup $stage) }
        $retained = Join-Path $parent ('Claude.switcher-backup-' + $stamp)
        $hadCurrentData = Test-Path -LiteralPath $app.Data
        Write-JsonAtomic $pendingPath ([pscustomobject]@{ Data=$app.Data; Stage=$stage; Backup=$retained; HadData=$hadCurrentData; From=$pending.To; To=$from })
        try { Replace-DataDirectory $app.Data $stage $retained }
        catch {
            if (((Test-Path -LiteralPath $app.Data) -or -not $hadCurrentData) -and -not (Test-Path -LiteralPath $retained)) {
                Write-JsonAtomic $pendingPath $pending
            }
            throw
        }
        $state.Current=$from
        Write-JsonAtomic (Join-Path $Root 'account-state.json') $state
        Write-JsonAtomic $pendingPath ([pscustomobject]@{ Completed=$true; Backup=$retained; HadData=$hadCurrentData; From=$pending.To; To=$from })
        [pscustomobject]@{ Message='已恢复切换前的数据；恢复前的数据也另行保留。请拥抱一下通过检查后再启动 Claude。'; Status=(Get-AppStatus $Root) }
    } finally { $lock.Dispose() }
}

function Get-AppStatus($Root) {
    $state = Get-AccountState $Root
    $profiles = @($state.Profiles | ForEach-Object {
        [pscustomobject]@{
            Id=$_.Id; Name=$_.Name; IsCurrent=($_.Id -eq $state.Current)
            Session=$(if ($_.Id -eq $state.Current) {'当前使用'} elseif ($_.Snapshot) {'已有本地快照'} else {'首次切换后登录'})
            Baseline='星链 AS14593 · 允许 IP 变化'
        }
    })
    [pscustomobject]@{ Current=$state.Current; CurrentName=(Get-AccountProfile $state $state.Current).Name; Profiles=$profiles; Guard=(Get-GuardStatus $Root); StateRoot=$Root }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $result = switch ($Command) {
            'check' { Get-EnvironmentCheck $StateRoot }
            'deep-check' { Get-DeepCheck $StateRoot }
            'network-insights' { Get-NetworkInsights $StateRoot }
            'fingerprint-check' { Get-FingerprintInsights $StateRoot }
            'fingerprint-save' { Get-FingerprintInsights $StateRoot -Remember }
            'flclash-check' { Get-FlClashCheck }
            'start' { Start-ProtectedClaude $StateRoot }
            'baseline' { Save-Baseline $StateRoot }
            'switch' { Switch-Account $StateRoot $Account }
            'account-add' { Add-Account $StateRoot ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($NameEncoded))) }
            'account-rename' { Rename-Account $StateRoot $Account ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($NameEncoded))) }
            'restore' { Restore-LastData $StateRoot }
            'guard-status' { [pscustomobject]@{ Guard=(Get-GuardStatus $StateRoot) } }
            'guard-start' { Start-Guard $StateRoot; Get-AppStatus $StateRoot }
            'guard-check' { Request-GuardCheck $StateRoot }
            'status' { Get-AppStatus $StateRoot }
            'environment-read' { Get-EnvironmentPreferences }
            'timezone-set' { Set-EnvironmentPreference $StateRoot 'Timezone' ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($NameEncoded))) }
            'format-set' { Set-EnvironmentPreference $StateRoot 'Format' ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($NameEncoded))) }
            'language-first' { Set-EnvironmentPreference $StateRoot 'Language' ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($NameEncoded))) }
        }
        $reportKind=switch ($Command) {'check' {'Basic'} 'flclash-check' {'FlClash'} 'deep-check' {'Deep'} 'network-insights' {'Network'} 'fingerprint-check' {'Fingerprint'} 'fingerprint-save' {'Fingerprint'}}
        if ($reportKind) {
            try { $result=Save-DiagnosticReport $StateRoot $result $reportKind }
            catch { $result | Add-Member -NotePropertyName ReportError -NotePropertyValue ('检测已完成，但本地记录未保存：'+$_.Exception.Message) }
        }
        [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
        $result | ConvertTo-Json -Depth 12 -Compress
    } catch {
        [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
        [pscustomobject]@{ Error=$_.Exception.Message } | ConvertTo-Json -Compress
        exit 1
    }
}
