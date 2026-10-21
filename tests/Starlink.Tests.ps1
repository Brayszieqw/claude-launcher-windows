param([string]$WorkRoot = (Join-Path $env:TEMP ('ClaudeStarlinkTests-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$package=Split-Path -Parent $PSScriptRoot
. (Join-Path $package 'claude-switch.ps1') -StateRoot $WorkRoot
[void](New-Item -ItemType Directory -Path $WorkRoot -Force)
$results=New-Object System.Collections.Generic.List[object]
function Get-GuardDnsCheck { New-Check 'fixture DNS' 'ok' 'fixture' }
function Assert($Condition,$Message) { if (-not $Condition) { throw $Message } }
function Test-Case($Name,[scriptblock]$Body) {
    try { & $Body; $results.Add([pscustomobject]@{Name=$Name;Status='PASS';Detail=''}) }
    catch { $results.Add([pscustomobject]@{Name=$Name;Status='FAIL';Detail=$_.Exception.Message}) }
}
function Expect-Error([scriptblock]$Body,$Pattern) {
    $caught=$false
    try { & $Body | Out-Null } catch { $caught=$true; Assert ($_.Exception.Message -match $Pattern) ('Unexpected error: '+$_.Exception.Message) }
    Assert $caught 'Expected rejection'
}
function Get-DnsClientCache { @() }
function Invoke-ProbeHttp { throw 'Unexpected external request in an offline test' }
function Start-ProbeHttp($Settings,$Endpoint,$Route,$Budget) {
    [pscustomobject]@{Settings=$Settings;Endpoint=$Endpoint;Route=$Route;Budget=$Budget;Process=$null}
}
function Receive-ProbeHttp($Probe) { Invoke-ProbeHttp $Probe.Settings $Probe.Endpoint $Probe.Route $Probe.Budget }
Test-Case 'ASN lookup queries the measured address and uses the explicit proxy' {
    function Invoke-ProbeHttp($Settings,$Endpoint,$Route) {
        Assert ($Endpoint -eq 'https://ipinfo.io/8.8.8.8/json' -and $Route -eq 'Proxy') 'Lookup used the wrong address or route'
        [pscustomobject]@{Body='{"ip":"8.8.8.8","org":"AS14593 Starlink"}'}
    }
    $result=Get-AddressNetwork @{ProxyPort=7890} '8.8.8.8'
    Assert ($result.Asn -eq 14593 -and $result.Source -eq 'ipinfo.io') 'Valid ASN was lost'
}
Test-Case 'Rate-limit failover stays on the proxy and verifies the returned address' {
    $script:calls=New-Object System.Collections.Generic.List[string]
    function Invoke-ProbeHttp($Settings,$Endpoint,$Route) {
        $script:calls.Add($Endpoint+' '+$Route)
        Assert ($Route -eq 'Proxy') 'Failover switched to direct'
        if ($Endpoint -like '*ipinfo.io*') { throw 'HTTP 429' }
        Assert ($Endpoint -eq 'https://ipwho.is/8.8.8.8') 'Fallback queried another IP'
        [pscustomobject]@{Body='{"success":true,"ip":"8.8.8.8","connection":{"asn":14593,"org":"SpaceX"}}'}
    }
    $result=Get-AddressNetwork @{} '8.8.8.8'
    Assert ($result.Asn -eq 14593 -and $result.Source -eq 'ipwho.is' -and $script:calls.Count -eq 2) 'Failover did not finish correctly'
}
Test-Case 'A confirmed other ASN cannot be replaced by a passing provider' {
    $script:calls=0
    function Invoke-ProbeHttp($Settings,$Endpoint,$Route) {
        $script:calls++
        Assert ($Endpoint -like '*ipinfo.io*') 'A known non-Starlink result was retried elsewhere'
        [pscustomobject]@{Body='{"ip":"8.8.8.8","org":"AS15169 Starlink-named fixture"}'}
    }
    Assert ((Get-AddressNetwork @{} '8.8.8.8').Asn -eq 15169 -and $script:calls -eq 1) 'Organization name bypassed the ASN rule'
}
Test-Case 'Wrong returned IP is rejected by both providers' {
    function Invoke-ProbeHttp { [pscustomobject]@{Body='{"ip":"9.9.9.9","org":"AS14593 Starlink","connection":{"asn":14593}}'} }
    Expect-Error { Get-AddressNetwork @{} '8.8.8.8' } '不属于所查询'
}
Test-Case 'Missing ASN, booleans, negatives and out-of-range ASN remain unknown' {
    foreach ($value in @('null','true','-1','4294967296','"Starlink"')) {
        $script:asnValue=$value
        function Invoke-ProbeHttp { [pscustomobject]@{Body=('{"ip":"8.8.8.8","org":"Starlink","connection":{"asn":'+$script:asnValue+'}}')} }
        Expect-Error { Get-AddressNetwork @{} '8.8.8.8' } '缺少有效 ASN'
    }
}
Test-Case 'Challenge pages and explicit provider errors cannot pass' {
    foreach ($body in @('<html>challenge</html>','{"success":false,"ip":"8.8.8.8","org":"AS14593 Starlink"}','{"error":"unavailable","ip":"8.8.8.8","org":"AS14593 Starlink"}')) {
        $script:responseBody=$body
        function Invoke-ProbeHttp { [pscustomobject]@{Body=$script:responseBody} }
        Expect-Error { Get-AddressNetwork @{} '8.8.8.8' } 'ASN 未核验'
    }
}
Test-Case 'Canonical IPv6 response matches the queried identity' {
    function Invoke-ProbeHttp { [pscustomobject]@{Body='{"ip":"2001:4860:4860:0:0:0:0:8888","org":"AS14593 Starlink"}'} }
    Assert ((Get-AddressNetwork @{} '2001:4860:4860::8888').Asn -eq 14593) 'Canonical IPv6 was rejected'
    Expect-Error { Get-AddressNetwork @{} '192.168.1.1' } '非公网'
}
Test-Case 'Different Starlink exits in the same round block even when all ASNs pass' {
    $script:traceIndex=0
    $script:traceCalls=New-Object System.Collections.Generic.List[string]
    function Invoke-ProbeHttp($Settings,$Endpoint,$Route) {
        if ($Endpoint -like '*/cdn-cgi/trace') {
            $script:traceCalls.Add($Endpoint+' '+$Route)
            $script:traceIndex++
            return [pscustomobject]@{Body=('ip=8.8.8.'+$script:traceIndex+"`nloc="+$(if ($script:traceIndex -eq 4) {'US'} else {'JP'}));Milliseconds=1}
        }
        Assert ($Route -eq 'Proxy') 'ASN query bypassed the explicit proxy'
        $address=([uri]$Endpoint).Segments[1].TrimEnd('/')
        [pscustomobject]@{Body=('{"ip":"'+$address+'","org":"AS14593 SpaceX"}')}
    }
    $result=Get-LaunchNetworkEvidence @{}
    Assert ($result.State -eq 'fail' -and $result.Checks.Count -eq 31 -and $result.Observations.Count -eq 30) 'Same-round mismatch was not blocked'
    Assert (@($script:traceCalls | Select-Object -Unique).Count -eq 30) 'A required domain/route was omitted'
    Assert (($result | ConvertTo-Json -Depth 8) -notmatch '8\.8\.8\.') 'Raw IP leaked into the result'
}
Test-Case 'Round-local lookup cache avoids redundant queries without reusing history' {
    $script:lookups=0
    function Invoke-ProbeHttp($Settings,$Endpoint,$Route) {
        if ($Endpoint -like '*/cdn-cgi/trace') { return [pscustomobject]@{Body="ip=8.8.8.8`nloc=JP";Milliseconds=1} }
        $script:lookups++
        [pscustomobject]@{Body='{"ip":"8.8.8.8","org":"AS14593 Starlink"}'}
    }
    $first=Get-LaunchNetworkEvidence @{}; $second=Get-LaunchNetworkEvidence @{}
    Assert ($first.State -eq 'ok' -and $second.State -eq 'ok' -and $script:lookups -eq 2) 'Cache was not limited to one round'
}
Test-Case 'One non-Starlink route blocks; one incomplete route is unknown' {
    foreach ($scenario in @('other','missing')) {
        $script:scenario=$scenario
        function Invoke-ProbeHttp($Settings,$Endpoint,$Route) {
            if ($Endpoint -eq 'https://claude.com/cdn-cgi/trace' -and $Route -eq 'System') {
                if ($script:scenario -eq 'missing') { throw 'HTTPS timeout' }
                return [pscustomobject]@{Body="ip=9.9.9.9`nloc=JP";Milliseconds=1}
            }
            [pscustomobject]@{Body="ip=8.8.8.8`nloc=JP";Milliseconds=1}
        }
        function Get-AddressNetwork($Settings,$Address) { [pscustomobject]@{Asn=$(if ($Address -eq '9.9.9.9') {15169} else {14593});Source='fixture';Organization='fixture'} }
        $result=Get-LaunchNetworkEvidence @{}
        $expected=if ($scenario -eq 'other') {'fail'} else {'unknown'}
        Assert ($result.State -eq $expected -and @($result.Checks | Where-Object Blocking).Count -eq $(if ($scenario -eq 'other') {2} else {1})) 'Partial or non-Starlink network was accepted'
    }
}
Test-Case 'Unavailable providers remain unknown and do not reuse an earlier pass' {
    function Invoke-ProbeHttp($Settings,$Endpoint,$Route) {
        if ($Endpoint -like '*/cdn-cgi/trace') { return [pscustomobject]@{Body="ip=8.8.8.8`nloc=JP";Milliseconds=1} }
        throw 'HTTP 429'
    }
    $result=Get-LaunchNetworkEvidence @{}
    Assert ($result.State -eq 'unknown' -and @($result.Checks | Where-Object Blocking).Count -eq 30) 'Unavailable ASN provider was treated as safe'
}
Test-Case 'Unknown evidence remains visible without preventing launch or becoming a saved baseline' {
    function Get-ClaudeInstall { [pscustomobject]@{Kind='fixture'} }
    function Get-ProtectionHealth { [pscustomobject]@{Healthy=$true;Core=$true;Tun=$true;Proxy=$true;Adapter='fixture'} }
    function Get-LaunchNetworkEvidence { [pscustomobject]@{State='unknown';Detail='fixture incomplete';Checks=@();Observations=@()} }
    function Get-FlClashCheck { [pscustomobject]@{Checks=@()} }
    function Get-LocalConfigurationChecks { @() }
    function Get-IPv6LocalCheck { New-Check 'IPv6' 'info' 'fixture' }
    $root=Join-Path $WorkRoot 'unknown-gate'
    $check=Assert-LaunchReady $root
    Assert ($check.Ready -and ($check.Checks | Where-Object Name -eq '代理 HTTPS 出口').State -eq 'unknown') 'Unknown evidence locked launch or became a pass'
    Expect-Error { Save-Baseline $root } 'fixture incomplete'
    Assert (-not (Test-Path (Join-Path $root 'account-state.json'))) 'Unknown evidence changed account metadata'
}
Test-Case 'Environment warnings never echo proxy credentials or bypass values' {
    $old=@{}
    foreach ($name in @('HTTPS_PROXY','NO_PROXY','NODE_TLS_REJECT_UNAUTHORIZED')) { $old[$name]=[Environment]::GetEnvironmentVariable($name,'Process') }
    try {
        $env:HTTPS_PROXY='socks5://fixture-user:fixture-password@invalid.test:1080'
        $env:NO_PROXY='claude.ai,private-fixture-domain'
        $env:NODE_TLS_REJECT_UNAUTHORIZED='0'
        $rows=@(Get-LocalConfigurationChecks @{ProxyPort=7890})
        $row=$rows | Where-Object Name -eq '启动环境 · Process'
        Assert ($row.State -eq 'warn' -and $row.Detail -match 'HTTPS_PROXY' -and $row.Detail -match 'NO_PROXY' -and $row.Detail -match 'NODE_TLS') 'Configuration issue was omitted'
        Assert (($rows | ConvertTo-Json) -notmatch 'fixture-password|fixture-user|private-fixture-domain|invalid.test') 'Environment values were exposed'
    } finally { foreach ($name in $old.Keys) { [Environment]::SetEnvironmentVariable($name,$old[$name],'Process') } }
}
Test-Case 'Guard summary rejects stale, future, previous-session and corrupt results' {
    $root=Join-Path $WorkRoot 'guard-summary'
    $ticks=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks.ToString()
    Write-JsonAtomic (Join-Path $root 'guard.json') @{Pid=$PID;StartTicks=$ticks}
    foreach ($scenario in @('fresh','stale','future','previous','corrupt')) {
        $record=@{Pid=$PID;StartTicks=$ticks;CheckedAt=[DateTime]::UtcNow.ToString('o');State='ok';Detail='fixture'}
        if ($scenario -eq 'stale') { $record.CheckedAt=[DateTime]::UtcNow.AddMinutes(-4).ToString('o') }
        if ($scenario -eq 'future') { $record.CheckedAt=[DateTime]::UtcNow.AddMinutes(4).ToString('o') }
        if ($scenario -eq 'previous') { $record.StartTicks='0' }
        $body=if ($scenario -eq 'corrupt') {'not json'} else {$record | ConvertTo-Json -Compress}
        [IO.File]::WriteAllText((Join-Path $root 'guard-observations.jsonl'),$body)
        $summary=Get-GuardSummary $root
        Assert (($summary -match '已核验星链') -eq ($scenario -eq 'fresh')) ('Incorrect guard freshness: '+$scenario)
    }
}
Test-Case 'Full-time guard does not show stale evidence as healthy' {
    $root=Join-Path $WorkRoot 'full-time-summary'
    $ticks=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks.ToString()
    Write-JsonAtomic (Join-Path $root 'guard.json') @{Pid=$PID;StartTicks=$ticks}
    foreach ($offset in @(0,-4,4)) {
        Write-JsonAtomic (Join-Path $root 'guard-state.json') @{Phase='守护中';Reason='';AlertKind='';CheckedAt=[DateTime]::UtcNow.AddMinutes($offset).ToString('o')}
        $summary=Get-GuardSummary $root
        Assert (($summary -like '全时段守护 · 守护中*') -eq ($offset -eq 0)) ('Incorrect full-time guard freshness: '+$offset)
    }
}
$results | ConvertTo-Json -Depth 8
if (@($results | Where-Object Status -eq 'FAIL').Count) { exit 1 }
