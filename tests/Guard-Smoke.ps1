param([string]$WorkRoot=(Join-Path $env:TEMP ('ClaudeGuardLifecycle-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$package=Split-Path -Parent $PSScriptRoot
$fixturePackage=Join-Path $WorkRoot 'package'
$root=Join-Path $WorkRoot 'state'
[void](New-Item -ItemType Directory -Path $fixturePackage,$root -Force)
foreach ($name in @('claude-switch.ps1','claude-bodyguard.ps1','guard-runtime.ps1','network-probes.ps1','environment-insights.ps1','diagnostic-reports.ps1','flclash-checks.ps1')) {
    Copy-Item -LiteralPath (Join-Path $package $name) -Destination $fixturePackage
}
$overrides=@'
function Get-ProtectionHealth {
    if (Test-Path -LiteralPath (Join-Path $StateRoot 'internal-error')) {throw 'fixture health query failed'}
    [pscustomobject]@{Healthy=(-not (Test-Path -LiteralPath (Join-Path $StateRoot 'local-failure')))}
}
function Get-GuardEvidence {
    $mode=[IO.File]::ReadAllText((Join-Path $StateRoot 'network-mode'))
    $hash=[IO.File]::ReadAllText((Join-Path $StateRoot 'egress'))
    [pscustomobject]@{State=$mode;Detail='fixture '+$mode;Observations=@([pscustomobject]@{Provider='claude.ai';Route='Proxy';Family='IPv4';Hash=$hash})}
}
'@
Add-Content -LiteralPath (Join-Path $fixturePackage 'claude-switch.ps1') -Value $overrides -Encoding UTF8
. (Join-Path $package 'claude-switch.ps1') -StateRoot $root
function Assert($Condition,$Message) {if (-not $Condition) {throw $Message}}
function Wait-State([scriptblock]$Predicate,$Message) {
    $deadline=[DateTime]::UtcNow.AddSeconds(40)
    do {
        $state=Read-GuardState $root
        if (& $Predicate $state) {return $state}
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)
    throw ($Message+'; last state: '+($state | ConvertTo-Json -Compress))
}
$exe=Join-Path $WorkRoot 'guard-fixture.exe'
$child=Join-Path $WorkRoot 'helper.exe'
Add-Type -TypeDefinition 'public class GuardChild { public static void Main() { System.Threading.Thread.Sleep(300000); } }' -OutputAssembly $child -OutputType ConsoleApplication
Add-Type -TypeDefinition 'public class GuardParent { public static void Main(string[] args) { var s=new System.Diagnostics.ProcessStartInfo(args[0]); s.UseShellExecute=false; s.CreateNoWindow=true; System.Diagnostics.Process.Start(s); System.Threading.Thread.Sleep(300000); } }' -OutputAssembly $exe -OutputType ConsoleApplication
$guard=$null; $fixture=$null
try {
    [IO.File]::WriteAllText((Join-Path $root 'network-mode'),'ok')
    [IO.File]::WriteAllText((Join-Path $root 'egress'),'first-hash')
    Write-JsonAtomic (Join-Path $root 'guard-state.json') @{Locked=$true;Phase='已阻断';Reason='legacy fixture';Revision='legacy'}
    $fixture=Start-Process -FilePath $exe -ArgumentList ('"'+$child+'"') -WindowStyle Hidden -PassThru
    $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $fixturePackage 'claude-bodyguard.ps1')+'" -StateRoot "'+$root+'"'
    $guard=Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $arguments -WindowStyle Hidden -PassThru
    $state=Wait-State {param($s) $s.Phase -eq '守护中'} 'First check did not complete'
    Assert (-not $state.PSObject.Properties['Locked'] -and -not $fixture.HasExited) 'Legacy lock survived or healthy fixture was killed'
    foreach ($mode in @('fail','unknown','fail')) {
        [IO.File]::WriteAllText((Join-Path $root 'network-mode'),$mode)
        $result=Request-GuardCheck $root
        $state=Read-GuardState $root
        Assert ($state.AlertKind -and $state.Reason -match $mode -and -not $fixture.HasExited) 'An abnormal check was hidden or terminated the fixture'
        Assert (@(Get-Process -Name helper -ErrorAction SilentlyContinue | Where-Object Path -eq $child).Count -eq 1) 'The child process was terminated or restarted'
    }
    [IO.File]::WriteAllText((Join-Path $root 'local-failure'),'persistent')
    [void](Wait-State {param($s) $s.AlertKind -eq 'Proxy'} 'Proxy failure did not raise an alert')
    Start-Sleep -Seconds 12
    Assert (-not $fixture.HasExited) 'A persistent proxy failure terminated the fixture'
    [IO.File]::Delete((Join-Path $root 'local-failure'))
    [IO.File]::WriteAllText((Join-Path $root 'network-mode'),'ok')
    Request-GuardCheck $root | Out-Null
    Assert ((Read-GuardState $root).Phase -eq '守护中' -and -not (Read-GuardState $root).AlertKind) 'Recovery did not clear the alert automatically'
    [IO.File]::WriteAllText((Join-Path $root 'egress'),'second-hash')
    Request-GuardCheck $root | Out-Null
    Assert ((Read-GuardState $root).AlertKind -eq 'IPChanged' -and -not $fixture.HasExited) 'IP change was missed or ended the fixture'
    Request-GuardCheck $root | Out-Null
    Assert (-not (Read-GuardState $root).AlertKind) 'A stable later check did not clear the IP-change notice'
    $invalidId=[guid]::NewGuid().ToString('N')
    Write-JsonAtomic (Join-Path $root 'guard-check.json') @{Id=$invalidId;Revision='expired-fixture';RequestedAt=[DateTime]::UtcNow.ToString('o')}
    $state=Wait-State {param($s) $s.RequestId -eq $invalidId} 'Invalid request did not complete'
    Assert ($state.Phase -eq '检测受限' -and -not $fixture.HasExited) 'Invalid request became a lock or stayed checking'
    Request-GuardCheck $root | Out-Null
    [IO.File]::WriteAllText((Join-Path $root 'internal-error'),'fail')
    Assert ($guard.WaitForExit(10000) -and -not $fixture.HasExited) 'Internal detection error killed the fixture'
    Assert ((Read-GuardState $root).Phase -eq '检测受限') 'Internal error was hidden'
    Assert (@(Get-Process -Name helper -ErrorAction SilentlyContinue | Where-Object Path -eq $child).Count -eq 1) 'Internal error killed the child'
    [pscustomobject]@{Status='PASS';LegacyLockRemoved=$true;RepeatedFailuresPreserveProcesses=$true;PersistentProxyFailurePreservesProcesses=$true;RecoveryClearsAlert=$true;IPChangeAlert=$true;StableIPClearsAlert=$true;InvalidRequestCompletes=$true;InternalErrorPreservesProcesses=$true;WorkRoot=$WorkRoot} | ConvertTo-Json
} finally {
    if ($guard -and -not $guard.HasExited) {$guard.Kill()}
    Get-Process -Name guard-fixture,helper -ErrorAction SilentlyContinue | Where-Object {$_.Path -in @($exe,$child)} | Stop-Process -Force
}
