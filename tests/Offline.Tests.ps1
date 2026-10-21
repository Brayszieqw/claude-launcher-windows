param([string]$WorkRoot = (Join-Path $env:TEMP ('ClaudeSwitcherTests-' + [guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$package=Split-Path -Parent $PSScriptRoot
. (Join-Path $package 'claude-switch.ps1') -StateRoot $WorkRoot
[void](New-Item -ItemType Directory -Path $WorkRoot -Force)
$results=New-Object System.Collections.Generic.List[object]
function Get-GuardDnsCheck { New-Check 'fixture DNS' 'ok' 'fixture' }
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Test-Case($Name, [scriptblock]$Body) {
    try { & $Body; $results.Add([pscustomobject]@{Name=$Name;Status='PASS';Detail=''}) }
    catch { $results.Add([pscustomobject]@{Name=$Name;Status='FAIL';Detail=$_.Exception.Message}) }
}
function Expect-Error([scriptblock]$Body, $Pattern) {
    $caught=$false
    try { & $Body | Out-Null } catch { $caught=$true; Assert ($_.Exception.Message -match $Pattern) ('Unexpected error: '+$_.Exception.Message) }
    Assert $caught 'Expected a failure, but the operation completed.'
}
Test-Case 'PowerShell 5.1 syntax and UTF-8 BOM' {
    foreach ($file in Get-ChildItem -LiteralPath $package -Filter '*.ps1') {
        $tokens=$null; $errors=$null
        [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
        Assert ($errors.Count -eq 0) ($file.Name+': '+($errors.Message -join ';'))
        $bytes=[IO.File]::ReadAllBytes($file.FullName)
        Assert ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) ('Missing UTF8 BOM: '+$file.Name)
    }
}
Test-Case 'WPF XAML builds successfully' {
    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
    $text=[IO.File]::ReadAllText((Join-Path $package 'SwitcherUI.ps1'))
    $match=[regex]::Match($text,'(?s)\$xaml = @"\r?\n(.*?)\r?\n"@')
    Assert $match.Success 'XAML not found'
    $xml=[xml]$match.Groups[1].Value
    $window=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $xml))
    Assert ($null -ne $window.FindName('BtnStart')) 'Start button missing'
    Assert ($null -ne $window.FindName('BtnRestore')) 'Recovery button missing'
}
Test-Case 'Missing installation prevents launch without starting a guard' {
    function Get-ClaudeInstall {throw 'fixture missing installation'}
    function Start-Guard { throw 'GUARD WAS CALLED' }
    function Start-Desktop { throw 'LAUNCH WAS CALLED' }
    Expect-Error { Start-ProtectedClaude (Join-Path $WorkRoot 'blocked') } 'fixture missing installation'
}
Test-Case 'Explicit start starts the monitor before desktop without a network gate' {
    $script:calls=@()
    function Get-ClaudeInstall { [pscustomobject]@{Exe='fixture'} }
    function Get-EnvironmentCheck {throw 'NETWORK GATE WAS CALLED'}
    function Start-Guard { $script:calls+='guard' }
    function Start-Desktop { $script:calls+='desktop' }
    Start-ProtectedClaude (Join-Path $WorkRoot 'ready') | Out-Null
    Assert (($script:calls -join ',') -eq 'guard,desktop') 'Launch sequence is incorrect'
}
Test-Case 'Monitor startup failure is reported without preventing explicit launch' {
    function Get-ClaudeInstall {[pscustomobject]@{Exe='fixture'}}
    function Start-Guard {throw 'fixture monitor unavailable'}
    $script:launched=$false
    function Start-Desktop {$script:launched=$true}
    $result=Start-ProtectedClaude (Join-Path $WorkRoot 'monitor-unavailable')
    Assert ($script:launched -and $result.Message -match 'fixture monitor unavailable') 'Monitor error blocked launch or was hidden'
}
Test-Case 'Desktop identity filter excludes Claude Code' {
    function Get-Process { @([pscustomobject]@{Path='C:\Desktop\Claude.exe';Id=11},[pscustomobject]@{Path='C:\Code\claude.exe';Id=22}) }
    $found=@(Get-DesktopProcesses ([pscustomobject]@{Exe='C:\Desktop\Claude.exe'}))
    Assert ($found.Count -eq 1 -and $found[0].Id -eq 11) 'Code process was included'
}
Test-Case 'Account switch refuses active Claude Code' {
    function Get-Process { [pscustomobject]@{Path='C:\Code\claude.exe';Id=22} }
    Expect-Error { Stop-DesktopForSwitch ([pscustomobject]@{Exe='C:\Desktop\Claude.exe'}) } 'Claude Code'
}
Test-Case 'Manifest copies hidden files and empty directories' {
    $source=Join-Path $WorkRoot 'tree-source'; $dest=Join-Path $WorkRoot 'tree-copy'
    [void](New-Item -ItemType Directory -Path (Join-Path $source 'empty') -Force)
    [IO.File]::WriteAllText((Join-Path $source 'normal.txt'),'fixture alpha')
    [IO.File]::WriteAllText((Join-Path $source '隐藏.txt'),'fixture beta')
    (Get-Item -LiteralPath (Join-Path $source '隐藏.txt')).Attributes='Hidden'
    $manifest=@(Copy-VerifiedTree $source $dest)
    Assert ($manifest.Count -eq 3) 'Manifest did not cover the entire tree'
    Assert (Test-Path -LiteralPath (Join-Path $dest 'empty')) 'Empty directory lost'
}
Test-Case 'Robocopy failure is surfaced before accepting snapshot' {
    $source=Join-Path $WorkRoot 'vanish-source'; $dest=Join-Path $WorkRoot 'vanish-copy'; $moved=Join-Path $WorkRoot 'vanish-retained'
    [void](New-Item -ItemType Directory -Path $source)
    function Get-TreeManifest { param($Path) [void](Assert-ChildPath $Path $WorkRoot); [void](Assert-ChildPath $moved $WorkRoot); [IO.Directory]::Move($Path,$moved); @() }
    Expect-Error { Copy-VerifiedTree $source $dest } 'robocopy (8|16)'
    Assert (Test-Path -LiteralPath $moved) 'Fixture source was not retained'
    Assert (-not (Test-Path -LiteralPath $dest)) 'The failed partial copy was kept'
}
Test-Case 'Copy stops before writing when the drive lacks space' {
    $source=Join-Path $WorkRoot 'space-source'; $dest=Join-Path $WorkRoot 'space-copy'
    [void](New-Item -ItemType Directory -Path $source -Force)
    [IO.File]::WriteAllText((Join-Path $source 'session.txt'),'fixture')
    function Get-ManifestBytes { [long]1PB }
    Expect-Error { Copy-VerifiedTree $source $dest } '剩余'
    Assert (-not (Test-Path -LiteralPath $dest)) 'A copy was started without enough space'
}
Test-Case 'Switch checks free space before closing Claude' {
    $root=Join-Path $WorkRoot 'space-switch'
    $target=(Add-Account $root '空间不足').Selected
    $data=Join-Path $WorkRoot 'space-switch-data\Claude'
    [void](New-Item -ItemType Directory -Path $data -Force)
    [IO.File]::WriteAllText((Join-Path $data 'session.txt'),'fixture')
    $script:spaceApp=[pscustomobject]@{Exe='fixture.exe';Data=$data;AppId=''}
    function Get-EnvironmentCheck { [pscustomobject]@{Ready=$true;App=$script:spaceApp} }
    function Get-TreeBytes { [long]1PB }
    function Stop-DesktopForSwitch { throw 'SHUTDOWN WAS REQUESTED' }
    Expect-Error { Switch-Account $root $target } '剩余'
    Assert ((Get-AccountState $root).Current -eq 'primary') 'The refused switch changed the current account'
    Assert (-not (Test-Path -LiteralPath (Join-Path $root 'accounts'))) 'A snapshot was started'
}
Test-Case 'Restore checks free space before closing Claude' {
    $root=Join-Path $WorkRoot 'space-restore'
    $data=Join-Path $WorkRoot 'space-restore-data\Claude'
    $backup=Join-Path (Split-Path -Parent $data) 'Claude.switcher-backup-fixture'
    [void](New-Item -ItemType Directory -Path $data,$backup -Force)
    Write-JsonAtomic (Join-Path $root 'pending-switch.json') @{Completed=$true;Backup=$backup;HadData=$true;From='primary';To='primary'}
    $script:restoreApp=[pscustomobject]@{Data=$data;Exe='fixture.exe'}
    function Get-ClaudeInstall { $script:restoreApp }
    function Get-TreeBytes { [long]1PB }
    function Stop-DesktopForSwitch { throw 'SHUTDOWN WAS REQUESTED' }
    Expect-Error { Restore-LastData $root } '剩余'
}
Test-Case 'A reused guard PID owned by an unreadable process is not the guard' {
    $root=Join-Path $WorkRoot 'guard-pid-reuse'
    Write-JsonAtomic (Join-Path $root 'guard.json') @{Pid=4242;StartTicks='639279117385023858';Exe='C:\fixture\Claude.exe'}
    # A SYSTEM or elevated process is visible to this user, but its start time reads as empty.
    function Get-Process { [pscustomobject]@{Id=4242;StartTime=$null} }
    Assert (-not (Get-GuardStatus $root)) 'A reused PID was treated as the running guard'
    Assert (-not (Get-AppStatus $root).Guard) 'Account status failed or reported a guard'
}
Test-Case 'Snapshot tampering is rejected' {
    $snapshot=Save-Snapshot (Join-Path $WorkRoot 'snapshots') (Join-Path $WorkRoot 'tree-source') 'A'
    Assert-Snapshot (Join-Path $WorkRoot 'snapshots') $snapshot
    [IO.File]::WriteAllText((Join-Path $snapshot 'data\normal.txt'),'changed')
    Expect-Error { Assert-Snapshot (Join-Path $WorkRoot 'snapshots') $snapshot } '校验失败'
}
Test-Case 'Second directory move failure restores original data' {
    $parent=Join-Path $WorkRoot 'rollback'
    $live=Join-Path $parent 'Claude'; $stage=Join-Path $parent 'Claude.switcher-stage-test'; $backup=Join-Path $parent 'Claude.switcher-backup-test'
    [void](New-Item -ItemType Directory -Path $live,$stage -Force)
    [IO.File]::WriteAllText((Join-Path $live 'keep.txt'),'original')
    $script:moveCount=0
    function Move-DataDirectory($Source,$Destination,$Parent) {
        [void](Assert-ChildPath $Source $Parent); [void](Assert-ChildPath $Destination $Parent)
        $script:moveCount++
        if ($script:moveCount -eq 2) { throw 'SIMULATED SECOND MOVE FAILURE' }
        [IO.Directory]::Move($Source,$Destination)
    }
    Expect-Error { Replace-DataDirectory $live $stage $backup } 'SIMULATED'
    Assert ([IO.File]::ReadAllText((Join-Path $live 'keep.txt')) -eq 'original') 'Original data was lost'
    Assert (Test-Path -LiteralPath $stage) 'Staged data was lost'
}
Test-Case 'Exclusive operation lock blocks concurrent mutation' {
    $root=Join-Path $WorkRoot 'lock'
    $first=Enter-Operation $root
    try { Expect-Error { Enter-Operation $root } '另一项操作' } finally { $first.Dispose() }
}
Test-Case 'Atomic settings update preserves timestamped backup' {
    $path=Join-Path $WorkRoot 'json\settings.json'
    Write-JsonAtomic $path @{Value=1}
    Write-JsonAtomic $path @{Value=2}
    Assert ((Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).Value -eq 2) 'New settings not committed'
    $backups=@(Get-ChildItem -LiteralPath (Split-Path $path) -Filter '*.backup-*')
    Assert ($backups.Count -eq 1) 'Backup was not retained'
    Assert ((Get-Content -LiteralPath $backups[0].FullName -Raw | ConvertFrom-Json).Value -eq 1) 'Backup content changed'
}
Test-Case 'Incomplete switch blocks startup' {
    $root=Join-Path $WorkRoot 'incomplete'
    Write-JsonAtomic (Join-Path $root 'pending-switch.json') @{Completed=$false}
    Expect-Error { Assert-LaunchReady $root } '未完成'
}
Test-Case 'Path traversal outside the data parent is rejected' {
    Expect-Error { Assert-ChildPath (Join-Path $WorkRoot '..\elsewhere') $WorkRoot } '路径不在'
}
Test-Case 'Three named profiles preserve session bytes and restore prior data' {
    $root=Join-Path $WorkRoot 'roundtrip-state'
    $data=Join-Path $WorkRoot 'roundtrip-data\Claude'
    [void](New-Item -ItemType Directory -Path $data -Force)
    [IO.File]::WriteAllText((Join-Path $data 'session.txt'),'primary fixture')
    [IO.File]::WriteAllText((Join-Path $data 'Local State'),'{"device":"stable-fixture-only"}')
    [IO.File]::WriteAllBytes((Join-Path $data 'storage.bin'),[byte[]](0,7,13,128,200,255))
    $original=@(Get-TreeManifest $data)
    $second=(Add-Account $root '工作账号').Selected
    $third=(Add-Account $root '个人账号').Selected
    $script:fixtureApp=[pscustomobject]@{Exe='fixture.exe';Data=$data;AppId=''}
    function Get-EnvironmentCheck { [pscustomobject]@{Ready=$true;App=$script:fixtureApp} }
    function Get-ClaudeInstall { $script:fixtureApp }
    function Stop-DesktopForSwitch {}
    Switch-Account $root $second | Out-Null
    Assert (@(Get-ChildItem -LiteralPath $data -Force).Count -eq 0) 'New profile inherited another session'
    [IO.File]::WriteAllText((Join-Path $data 'session.txt'),'second fixture')
    Switch-Account $root $third | Out-Null
    Assert (@(Get-ChildItem -LiteralPath $data -Force).Count -eq 0) 'Third profile inherited another session'
    [IO.File]::WriteAllText((Join-Path $data 'session.txt'),'third fixture')
    Switch-Account $root 'primary' | Out-Null
    Assert ((@(Get-TreeManifest $data) -join '|') -ceq ($original -join '|')) 'Session or local identity bytes changed'
    Assert ((Get-AccountState $root).Current -eq 'primary') 'Account label inconsistent'
    Restore-LastData $root | Out-Null
    Assert ([IO.File]::ReadAllText((Join-Path $data 'session.txt')) -eq 'third fixture') 'Recovery did not restore third profile'
    Assert ((Get-AccountState $root).Current -eq $third) 'Recovery selected the wrong profile'
    Switch-Account $root $second | Out-Null
    Assert ([IO.File]::ReadAllText((Join-Path $data 'session.txt')) -eq 'second fixture') 'Second profile was overwritten'
    $backups=@(Get-ChildItem -LiteralPath (Split-Path $data) -Directory -Filter 'Claude.switcher-backup-*')
    Assert ($backups.Count -ge 3) 'A backup was removed'
}
Test-Case 'Fresh account status is read-only and starts with one profile' {
    $root=Join-Path $WorkRoot 'read-only-state'
    $status=Get-AppStatus $root
    Assert (-not (Test-Path -LiteralPath $root)) 'Reading status created durable state'
    Assert (@($status.Profiles).Count -eq 1 -and $status.Current -eq 'primary') 'Unexpected default profile'
}
Test-Case 'Interrupted recovery blocks launch and can restore the pre-recovery session' {
    $root=Join-Path $WorkRoot 'recovery-interruption'
    $id=(Add-Account $root '恢复前').Selected
    $data=Join-Path $WorkRoot 'recovery-data\Claude'
    $backup=Join-Path (Split-Path -Parent $data) 'Claude.switcher-backup-fixture'
    [void](New-Item -ItemType Directory -Path $data,$backup -Force)
    [IO.File]::WriteAllText((Join-Path $data 'session.txt'),'before recovery')
    [IO.File]::WriteAllText((Join-Path $backup 'session.txt'),'earlier primary')
    $state=Get-AccountState $root; $state.Current=$id
    Write-JsonAtomic (Join-Path $root 'account-state.json') $state
    Write-JsonAtomic (Join-Path $root 'pending-switch.json') @{Completed=$true;Backup=$backup;HadData=$true;From='primary';To=$id}
    $script:recoveryApp=[pscustomobject]@{Data=$data;Exe='fixture.exe'}
    function Get-ClaudeInstall { $script:recoveryApp }
    function Stop-DesktopForSwitch {}
    $realWrite=${function:Write-JsonAtomic}
    function Write-JsonAtomic($Path,$Value) {
        if ((Split-Path -Leaf $Path) -eq 'account-state.json') { throw 'SIMULATED STATE COMMIT FAILURE' }
        & $realWrite $Path $Value
    }
    Expect-Error { Restore-LastData $root } 'SIMULATED STATE COMMIT FAILURE'
    Assert ([IO.File]::ReadAllText((Join-Path $data 'session.txt')) -eq 'earlier primary') 'Failure was not injected after replacement'
    Expect-Error { Assert-NoPendingSwitch $root } '未完成'
    ${function:Write-JsonAtomic}=$realWrite
    Restore-LastData $root | Out-Null
    Assert ([IO.File]::ReadAllText((Join-Path $data 'session.txt')) -eq 'before recovery') 'Interrupted recovery lost the prior session'
    Assert ((Get-AccountState $root).Current -eq $id) 'Recovery label does not match restored data'
    Assert-NoPendingSwitch $root
}
Test-Case 'A journal written before the first rename can be recovered without touching session data' {
    $root=Join-Path $WorkRoot 'pre-rename'
    $id=(Add-Account $root 'Target').Selected
    $data=Join-Path $WorkRoot 'pre-rename-data\Claude'
    $stage=Join-Path (Split-Path -Parent $data) 'Claude.switcher-stage-fixture'
    $backup=Join-Path (Split-Path -Parent $data) 'Claude.switcher-backup-fixture'
    [void](New-Item -ItemType Directory -Path $data,$stage -Force)
    [IO.File]::WriteAllText((Join-Path $data 'session.txt'),'unchanged original')
    Write-JsonAtomic (Join-Path $root 'pending-switch.json') @{Data=$data;Stage=$stage;Backup=$backup;HadData=$true;From='primary';To=$id}
    $script:recoveryApp=[pscustomobject]@{Data=$data;Exe='fixture.exe'}
    function Get-ClaudeInstall {$script:recoveryApp}
    function Stop-DesktopForSwitch {throw 'Unchanged original must not be stopped'}
    Expect-Error {Assert-NoPendingSwitch $root} '未完成'
    Restore-LastData $root | Out-Null
    Assert-NoPendingSwitch $root
    Assert ([IO.File]::ReadAllText((Join-Path $data 'session.txt')) -eq 'unchanged original') 'Original session changed'
    Assert ((Get-AccountState $root).Current -eq 'primary' -and (Test-Path -LiteralPath $stage)) 'Account or staged evidence changed'
}
Test-Case 'Missing backup after replacement is not mistaken for a pre-rename interruption' {
    $root=Join-Path $WorkRoot 'missing-backup'
    $data=Join-Path $WorkRoot 'missing-backup-data\Claude'
    [void](New-Item -ItemType Directory -Path $data -Force)
    $parent=Split-Path -Parent $data
    Write-JsonAtomic (Join-Path $root 'pending-switch.json') @{Data=$data;Stage=(Join-Path $parent 'Claude.switcher-stage-missing');Backup=(Join-Path $parent 'Claude.switcher-backup-missing');HadData=$true;From='primary';To='primary'}
    $script:recoveryApp=[pscustomobject]@{Data=$data;Exe='fixture.exe'}
    function Get-ClaudeInstall {$script:recoveryApp}
    function Stop-DesktopForSwitch {throw 'Must not stop on ambiguous recovery'}
    Expect-Error {Restore-LastData $root} '未找到'
    Expect-Error {Assert-NoPendingSwitch $root} '未完成'
}
Test-Case 'Legacy A/B state migrates in memory without rewriting or losing snapshots' {
    $root=Join-Path $WorkRoot 'legacy'
    Write-JsonAtomic (Join-Path $root 'account-state.json') @{Current='B';A='fixture-a';B='fixture-b';Recovery='old'}
    Write-JsonAtomic (Join-Path $root 'settings.json') @{ProxyPort=7890;EgressHash='legacy-hash';Country='JP'}
    $before=(Get-FileHash -LiteralPath (Join-Path $root 'account-state.json')).Hash
    $state=Get-AccountState $root
    Assert ($state.Version -eq 2 -and $state.Current -eq 'B') 'Legacy active profile lost'
    Assert ((Get-AccountProfile $state 'A').Snapshot -eq 'fixture-a') 'Legacy snapshot lost'
    Assert ((Get-AccountProfile $state 'B').EgressHash -eq 'legacy-hash') 'Active baseline lost'
    Assert (-not (Get-AccountProfile $state 'A').EgressHash) 'Global baseline incorrectly copied to another profile'
    Assert ((Get-FileHash -LiteralPath (Join-Path $root 'account-state.json')).Hash -eq $before) 'Read-only migration wrote to disk'
    Add-Account $root '新账号' | Out-Null
    Assert (@((Get-AccountState $root).Profiles).Count -eq 3) 'Migrated account catalog did not persist'
    Assert (@(Get-ChildItem -LiteralPath $root -Filter 'account-state.json.backup-*').Count -eq 1) 'Legacy state backup missing'
}
Test-Case 'Adding and renaming accounts never reads Claude data or uses the network' {
    function Get-ClaudeInstall { throw 'LIVE APP WAS READ' }
    function Stop-DesktopForSwitch { throw 'APP STOP WAS REQUESTED' }
    function Get-EnvironmentCheck { throw 'NETWORK CHECK WAS REQUESTED' }
    $root=Join-Path $WorkRoot 'metadata-only'
    $id=(Add-Account $root '  名称 "quote" & 中文  ').Selected
    $profile=Get-AccountProfile (Get-AccountState $root) $id
    Assert ($profile.Id -cmatch '^p-[a-f0-9]{32}$' -and -not $profile.Snapshot) 'Account ID is not stable metadata'
    Rename-Account $root $id '新的名称' | Out-Null
    Assert ((Get-AccountProfile (Get-AccountState $root) $id).Name -eq '新的名称') 'Rename failed'
    Assert ((Get-AccountState $root).Current -eq 'primary') 'Metadata action switched active profile'
    Assert (-not (Test-Path -LiteralPath (Join-Path $root 'accounts'))) 'Metadata action copied data'
}
Test-Case 'Duplicate, empty and control-character names are rejected' {
    $root=Join-Path $WorkRoot 'invalid-names'
    $id=(Add-Account $root 'Work').Selected
    Expect-Error { Add-Account $root 'work' } '同名'
    Expect-Error { Add-Account $root '   ' } '1–32'
    Expect-Error { Rename-Account $root $id ('bad'+[char]10+'name') } '控制字符'
    Assert (@((Get-AccountState $root).Profiles).Count -eq 2) 'Failed validation wrote an account'
}
Test-Case 'Account baseline and identity remain separate after rename and reload' {
    $root=Join-Path $WorkRoot 'profile-baselines'
    $id=(Add-Account $root '工作').Selected
    function Get-ProtectionHealth { [pscustomobject]@{Healthy=$true} }
    function Get-LaunchNetworkEvidence { [pscustomobject]@{State='ok';Observations=@([pscustomobject]@{Hash='primary-hash';Country='JP';Asn=14593})} }
    Save-Baseline $root | Out-Null
    $state=Get-AccountState $root
    Assert (-not (Get-AccountProfile $state $id).EgressHash) 'Baseline leaked to a different profile'
    $state.Current=$id
    (Get-AccountProfile $state $id).Snapshot='fixture-snapshot-location'
    Write-JsonAtomic (Join-Path $root 'account-state.json') $state
    function Get-LaunchNetworkEvidence { [pscustomobject]@{State='ok';Observations=@([pscustomobject]@{Hash='second-hash';Country='CA';Asn=14593})} }
    Save-Baseline $root | Out-Null
    Rename-Account $root $id '改名后' | Out-Null
    $state=Get-AccountState $root; $profile=Get-AccountProfile $state $id
    Assert ($profile.EgressHash -eq 'second-hash' -and $profile.Country -eq 'CA' -and $profile.Snapshot -eq 'fixture-snapshot-location') 'Rename changed account state'
    Assert ((Get-AccountProfile $state 'primary').EgressHash -eq 'primary-hash') 'Another baseline was overwritten'
    $json=Get-AppStatus $root | ConvertTo-Json -Depth 8
    Assert ($json -notmatch 'primary-hash|second-hash|fixture-snapshot-location') 'UI status exposed internal data'
}
Test-Case 'Switch validates the target policy before any desktop shutdown' {
    $root=Join-Path $WorkRoot 'target-gate'
    $target=(Add-Account $root '目标').Selected
    $script:checkedId=''
    function Get-EnvironmentCheck($Root,$AccountId) { $script:checkedId=$AccountId; [pscustomobject]@{Ready=$false;Checks=@([pscustomobject]@{Blocking=$true;Detail='target mismatch'})} }
    function Stop-DesktopForSwitch { throw 'SHUTDOWN WAS REQUESTED' }
    Expect-Error { Switch-Account $root $target } 'target mismatch'
    Assert ($script:checkedId -eq $target) 'Switch checked the current account instead of the target'
    Assert ((Get-AccountState $root).Current -eq 'primary') 'Rejected switch changed current account'
}
Test-Case 'Starlink dynamic exits ignore legacy per-account IP pins' {
    $root=Join-Path $WorkRoot 'baseline-gate'
    $id=(Add-Account $root '另一个出口').Selected
    $state=Get-AccountState $root
    (Get-AccountProfile $state 'primary').EgressHash='observed'
    (Get-AccountProfile $state $id).EgressHash='different'
    Write-JsonAtomic (Join-Path $root 'account-state.json') $state
    function Get-ClaudeInstall { [pscustomobject]@{Kind='fixture'} }
    function Get-ProtectionHealth { [pscustomobject]@{Healthy=$true;Core=$true;Tun=$true;Proxy=$true;Adapter='fixture'} }
    function Get-LaunchNetworkEvidence { [pscustomobject]@{State='ok';Detail='AS14593';Checks=@();Observations=@([pscustomobject]@{Hash='observed';Country='JP';Asn=14593})} }
    function Get-FlClashCheck { [pscustomobject]@{Checks=@()} }
    function Get-LocalConfigurationChecks { @() }
    function Get-IPv6LocalCheck { New-Check 'IPv6' 'info' 'fixture' }
    Assert (Get-EnvironmentCheck $root).Ready 'Current profile baseline incorrectly blocked'
    $check=Get-EnvironmentCheck $root $id
    Assert $check.Ready 'Legacy IP pin blocked a verified Starlink exit'
    Assert (@($check.Checks | Where-Object { $_.Name -eq '星链出口策略' -and $_.State -eq 'info' }).Count -eq 1) 'Dynamic Starlink policy was not visible'
    Assert ((Get-AccountProfile (Get-AccountState $root) $id).EgressHash -eq 'different') 'Read-only check rewrote legacy metadata'
}
Test-Case 'Unknown account and path-like IDs fail before touching application data' {
    $root=Join-Path $WorkRoot 'unknown-account'
    function Get-EnvironmentCheck { throw 'CHECK WAS CALLED' }
    Expect-Error { Switch-Account $root '..\escape' } '未找到'
    Write-JsonAtomic (Join-Path $root 'account-state.json') @{Version=2;Current='../bad';Profiles=@(@{Id='../bad';Name='bad'})}
    Expect-Error { Get-AccountState $root } '记录无效'
}
Test-Case 'Selecting the current account never rewrites or closes its session' {
    $root=Join-Path $WorkRoot 'same-account'
    function Get-EnvironmentCheck { [pscustomobject]@{Ready=$true;App=[pscustomobject]@{Exe='fixture.exe';Data='must-not-read'}} }
    function Stop-DesktopForSwitch { throw 'SHUTDOWN WAS REQUESTED' }
    Switch-Account $root 'primary' | Out-Null
    Assert (-not (Test-Path -LiteralPath (Join-Path $root 'account-state.json'))) 'Same-account operation rewrote state'
}
$results | ConvertTo-Json -Depth 5
if (@($results | Where-Object Status -eq 'FAIL').Count) { exit 1 }
