param([string]$WorkRoot=(Join-Path $env:TEMP ('ClaudeGuardTests-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'claude-switch.ps1') -StateRoot $WorkRoot
$results=New-Object System.Collections.Generic.List[object]
function Assert($Condition,$Message) {if (-not $Condition) {throw $Message}}
function Case($Name,[scriptblock]$Body) {
    try {& $Body; $results.Add(@{Name=$Name;Status='PASS'})}
    catch {$results.Add(@{Name=$Name;Status='FAIL';Detail=$_.Exception.Message})}
}
Case 'Guard identity can be read while atomic replacement holds delete access' {
    $root=Join-Path $WorkRoot 'shared-identity'
    $path=Join-Path $root 'guard.json'
    Write-JsonAtomic $path @{Pid=$PID;StartTicks=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks.ToString()}
    Add-Type -TypeDefinition @'
public static class GuardFileFixture {
    [System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode, SetLastError=true)]
    public static extern Microsoft.Win32.SafeHandles.SafeFileHandle CreateFile(string path, uint access, uint share, System.IntPtr security, uint creation, uint flags, System.IntPtr template);
}
'@
    $handle=[GuardFileFixture]::CreateFile($path,0x10000,7,[IntPtr]::Zero,3,0,[IntPtr]::Zero)
    try {
        Assert (-not $handle.IsInvalid) 'Could not hold replacement access to the fixture file'
        Assert (Get-GuardStatus $root) 'Running guard was not recognized during replacement'
    } finally {$handle.Dispose()}
}
Case 'Official domains and boundary-safe wildcard discovery' {
    function Get-DnsClientCache {
        @('preview.livepreview.claude.app','frame.claudeusercontent.com','tool.claudemcpcontent.com','api.anthropic.com.evil.test','evilclaude.ai','api.anthropic.com') | ForEach-Object {[pscustomobject]@{Entry=$_}}
    }
    $domains=@(Get-ClaudeDomains)
    Assert ($domains.Count -eq 18 -and 'api.anthropic.com' -in $domains -and 'tool.claudemcpcontent.com' -in $domains) 'Required domains missing or duplicated'
    Assert (@($domains | Where-Object {$_ -like '*evil*'}).Count -eq 0) 'Suffix boundary accepted an unrelated host'
}
Case 'All fixed domains use both paths and API-only split blocks' {
    function Get-DnsClientCache {@()}
    $script:paths=New-Object System.Collections.Generic.List[string]
    function Start-ProbeHttp($Settings,$Endpoint,$Route,$Budget) {
        $script:paths.Add($Endpoint+' '+$Route)
        [pscustomobject]@{Endpoint=$Endpoint;Route=$Route;Process=$null}
    }
    function Receive-ProbeHttp($Probe) {
        $ip=if ($Probe.Endpoint -eq 'https://api.anthropic.com/cdn-cgi/trace' -and $Probe.Route -eq 'System') {'9.9.9.9'} else {'8.8.8.8'}
        [pscustomobject]@{Body="ip=$ip`nloc=JP";Milliseconds=1}
    }
    function Get-AddressNetwork($Settings,$Address) {[pscustomobject]@{Asn=$(if ($Address -eq '9.9.9.9') {15169} else {14593});Source='fixture';Organization='fixture'}}
    $result=Get-LaunchNetworkEvidence @{}
    Assert ($script:paths.Count -eq 30 -and $result.State -eq 'fail') 'API split was accepted or a path omitted'
    Assert (@($result.Checks | Where-Object {$_.Name -like 'api.anthropic.com*' -and $_.Blocking}).Count -eq 1) 'API result not independently classified'
}
Case 'DNS interception requires TCP and UDP; direct upstream stays blocked' {
    foreach ($mode in @('ok','udp-only','direct','unreadable')) {
        $script:dnsMode=$mode
        function Get-FlClashSnapshot {if ($script:dnsMode -eq 'unreadable') {throw 'fixture'}; [pscustomobject]@{Generated='fixture'}}
        function Read-FlClashGeneratedField($Text,$Section,$Key) {
            if ($Key -eq 'dns-hijack') {if ($script:dnsMode -eq 'udp-only') {@('any:53')} else {@('any:53','tcp://any:53')}}
            elseif ($Key -eq 'direct-nameserver' -and $script:dnsMode -eq 'direct') {@('1.1.1.1')}
        }
        $row=Get-GuardDnsCheck
        Assert (($row.State -eq 'ok') -eq ($mode -eq 'ok')) ('Wrong DNS verdict: '+$mode)
        Assert ($row.Blocking -eq ($mode -ne 'ok')) 'DNS unknown failed open'
    }
}
Case 'Route evidence respects first-match ordering, rejects opaque rules and keeps host boundaries' {
    $config="rules:`n  - 'DOMAIN-SUFFIX,anthropic.com,starlink'`n  - 'DOMAIN-SUFFIX,claude.com,starlink'`n  - MATCH,other`n"
    Assert ((Get-ClaudeDomainPolicy $config 'a-cdn.anthropic.com') -eq 'starlink') 'Quoted suffix rule was not read'
    Assert ((Get-ClaudeDomainPolicy $config 'anthropic.com.evil.test') -eq '') 'Domain boundary bypass'
    $overridden="rules:`n  - DOMAIN,api.anthropic.com,DIRECT`n  - DOMAIN-SUFFIX,anthropic.com,starlink"
    Assert ((Get-ClaudeDomainPolicy $overridden 'api.anthropic.com') -eq '') 'Earlier direct rule was ignored'
    $opaque="rules:`n  - RULE-SET,remote-rules,other`n  - DOMAIN-SUFFIX,anthropic.com,starlink"
    Assert ((Get-ClaudeDomainPolicy $opaque 'a-cdn.anthropic.com') -eq '') 'An unknown earlier rule was skipped'
}
Case 'Unreadable DNS evidence remains unknown instead of a confirmed network fault' {
    function Get-ProtectionHealth {[pscustomobject]@{Healthy=$true}}
    function Get-FlClashCheck {[pscustomobject]@{Checks=@()}}
    function Get-GuardDnsCheck {New-Check '守护 DNS' 'unknown' 'fixture unreadable config' $true}
    function Get-LaunchNetworkEvidence {throw 'Network probe should not run without local configuration evidence'}
    Assert ((Get-GuardEvidence $WorkRoot).State -eq 'unknown') 'A config read failure became a confirmed fault'
}
Case 'Resource 404 is route-only evidence and requires a successful API anchor' {
    function Get-DnsClientCache {@()}
    function Get-FlClashSnapshot {[pscustomobject]@{Generated="rules:`n  - DOMAIN-SUFFIX,anthropic.com,starlink"}}
    function Start-ProbeHttp($Settings,$Endpoint,$Route,$Budget) {[pscustomobject]@{Endpoint=$Endpoint;Route=$Route;Process=$null}}
    function Get-AddressNetwork {[pscustomobject]@{Asn=14593;Source='fixture';Organization='fixture'}}
    foreach ($mode in @('valid','api-missing')) {
        $script:mode=$mode
        function Receive-ProbeHttp($Probe) {
            if ($Probe.Endpoint -like '*a-cdn.anthropic.com*' -or ($script:mode -eq 'api-missing' -and $Probe.Endpoint -eq 'https://api.anthropic.com/cdn-cgi/trace')) {
                return [pscustomobject]@{Status=404;Body='not found';Milliseconds=1}
            }
            [pscustomobject]@{Status=200;Body="ip=8.8.8.8`nloc=JP";Milliseconds=1}
        }
        $result=Get-LaunchNetworkEvidence @{}
        $resources=@($result.Checks | Where-Object Name -like 'a-cdn.anthropic.com*')
        if ($mode -eq 'valid') {
            Assert ($result.State -eq 'ok' -and @($resources | Where-Object State -eq 'warn').Count -eq 2) 'Resource route evidence was lost or mislabeled'
            Assert (@($result.Observations | Where-Object Provider -eq 'a-cdn.anthropic.com').Count -eq 0) 'An unmeasured IP was fabricated'
        } else {
            Assert ($result.State -eq 'unknown' -and @($resources | Where-Object Blocking).Count -eq 2) 'Missing API anchor incorrectly accepted route evidence'
        }
    }
}
$results | ConvertTo-Json -Depth 4
if (@($results | Where-Object Status -eq 'FAIL').Count) {exit 1}
