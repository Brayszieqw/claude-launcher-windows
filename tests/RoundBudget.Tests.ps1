param([string]$WorkRoot=(Join-Path $env:TEMP ('ClaudeBudgetTests-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$package=Split-Path -Parent $PSScriptRoot
. (Join-Path $package 'claude-switch.ps1') -StateRoot $WorkRoot
Add-Type -Path (Join-Path $PSScriptRoot 'LoopbackFixtures.cs')
# Four representative paths exercise the shared deadline; the domain suite checks the full catalog.
function Get-ClaudeDomains {@('claude.ai','claude.com')}
$results=New-Object System.Collections.Generic.List[object]
function Get-GuardDnsCheck { New-Check 'fixture DNS' 'ok' 'fixture' }
function Assert($Condition,$Message) {if (-not $Condition) {throw $Message}}
function Test-Case($Name,[scriptblock]$Body) {
    try {$detail=& $Body; $results.Add([pscustomobject]@{Name=$Name;Status='PASS';Detail=$detail})}
    catch {$results.Add([pscustomobject]@{Name=$Name;Status='FAIL';Detail=$_.Exception.Message})}
}
$script:realStart=${function:Start-ProbeHttp}
Test-Case 'Four real HTTP probes run concurrently and stop as soon as all pass' {
    $script:servers=@(1..4 | ForEach-Object {[LoopbackFixture]::Http($false,"ip=8.8.8.8`nloc=JP",200,1000)})
    $script:started=0; $script:budget=$null; $script:lookups=0
    function Start-ProbeHttp($Settings,$Endpoint,$Route,$Budget) {
        if ($script:budget) {Assert ([object]::ReferenceEquals($Budget,$script:budget)) 'Trace reset the deadline'}
        else {$script:budget=$Budget}
        $server=$script:servers[$script:started++]
        & $script:realStart @{ProxyPort=$server.Port} ('http://127.0.0.1:'+$server.Port+'/trace') $Route $Budget
    }
    function Get-AddressNetwork($Settings,$Address,$Budget) {
        Assert ($script:started -eq 4) 'A trace was awaited before all four started'
        Assert ([object]::ReferenceEquals($Budget,$script:budget)) 'ASN lookup reset the deadline'
        $script:lookups++
        [pscustomobject]@{Asn=14593;Source='fixture';Organization='fixture'}
    }
    try {
        $watch=[Diagnostics.Stopwatch]::StartNew()
        $result=Get-LaunchNetworkEvidence @{}
        $elapsed=$watch.ElapsedMilliseconds
        Assert ($result.State -eq 'ok' -and $result.Observations.Count -eq 4 -and $script:lookups -eq 1) 'Incomplete paths or repeated ASN lookup'
        Assert ($elapsed -lt 3000) ('Requests ran serially or waited after success: '+$elapsed+' ms')
        Assert (@($script:servers | Where-Object {-not $_.LastRequest -or $_.Failure}).Count -eq 0) 'Loopback traffic failed'
        "$elapsed ms; four paths passed; one ASN lookup"
    } finally {foreach ($server in $script:servers) {$server.Dispose()}}
}
Test-Case 'HTTPS gets 60 seconds after local preparation and cannot pass on unrelated ok rows' {
    $script:servers=@(1..4 | ForEach-Object {[LoopbackFixture]::Http($false,"ip=8.8.8.8`nloc=JP",200,$(if ($_ -eq 4) {65000} else {0}))})
    $script:started=0; $script:budget=$null
    $script:probeIds=New-Object System.Collections.Generic.List[int]
    function Get-ClaudeInstall {[pscustomobject]@{Kind='fixture'}}
    function Get-ProtectionHealth {[pscustomobject]@{Healthy=$true;Core=$true;Tun=$true;Proxy=$true;Adapter='fixture'}}
    function Get-FlClashCheck {[pscustomobject]@{Checks=@(New-Check 'fixture config' 'ok' 'fixture')}}
    function Get-LocalConfigurationChecks {Start-Sleep -Milliseconds 1500}
    function Get-IPv6LocalCheck {New-Check 'IPv6' 'info' 'fixture'}
    function Start-ProbeHttp($Settings,$Endpoint,$Route,$Budget) {
        if ($script:started -eq 0) {Assert ($Budget.ElapsedMilliseconds -lt 500) 'Local preparation consumed the HTTPS budget'}
        $script:budget=$Budget
        $server=$script:servers[$script:started++]
        $probe=& $script:realStart @{ProxyPort=$server.Port} ('http://127.0.0.1:'+$server.Port+'/trace') $Route $Budget
        $script:probeIds.Add($probe.Process.Id)
        $probe
    }
    function Get-AddressNetwork {[pscustomobject]@{Asn=14593;Source='fixture';Organization='fixture'}}
    try {
        $watch=[Diagnostics.Stopwatch]::StartNew()
        $result=Get-EnvironmentCheck $WorkRoot
        $elapsed=$watch.ElapsedMilliseconds
        Assert ($elapsed -ge 61500 -and $elapsed -lt 64000) ('HTTPS did not receive its own 60 seconds: '+$elapsed+' ms')
        Assert (-not $result.Ready -and @($result.Checks | Where-Object State -eq 'ok').Count -gt 5) 'An arbitrary five ok rows unlocked launch'
        Assert (@($result.Checks | Where-Object {$_.Name -like 'claude.*' -and $_.State -eq 'unknown' -and $_.Blocking}).Count -eq 1) 'Incomplete path was not marked unknown/blocking'
        Assert (@($result.Checks | Where-Object {$_.Name -like 'claude.*' -and $_.State -eq 'ok'}).Count -eq 3) 'Completed paths were discarded'
        Assert (@(Get-Process -Id $script:probeIds.ToArray() -ErrorAction SilentlyContinue).Count -eq 0) 'An owned curl remained running'
        $caught=$false
        try {& $script:realStart @{ProxyPort=1} 'http://127.0.0.1:1' 'System' $script:budget | Out-Null}
        catch {$caught=$_.Exception.Message -match '60 秒'}
        Assert $caught 'An expired round started another request'
        "$elapsed ms; three paths retained; last path unverified; all four curl processes stopped"
    } finally {foreach ($server in $script:servers) {$server.Dispose()}}
}
$results | ConvertTo-Json -Depth 6
if (@($results | Where-Object Status -eq 'FAIL').Count) {exit 1}
