param([string]$WorkRoot = (Join-Path $env:TEMP ('ClaudeProbeTests-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$package=Split-Path -Parent $PSScriptRoot
. (Join-Path $package 'claude-switch.ps1') -StateRoot $WorkRoot
[void](New-Item -ItemType Directory -Path $WorkRoot -Force)
Add-Type -Path (Join-Path $PSScriptRoot 'LoopbackFixtures.cs')
$results=New-Object System.Collections.Generic.List[object]
$liveBefore=@(Get-Process -Name Claude,FlClash,FlClashCore -ErrorAction SilentlyContinue | ForEach-Object Id)
function Assert($Condition,$Message) { if (-not $Condition) { throw $Message } }
function Test-Case($Name,[scriptblock]$Body) {
    try { & $Body; $results.Add([pscustomobject]@{Name=$Name;Status='PASS';Detail=''}) }
    catch { $results.Add([pscustomobject]@{Name=$Name;Status='FAIL';Detail=$_.Exception.Message}) }
}
function From-Hex($Text) { ,([byte[]]@(for ($i=0;$i -lt $Text.Length;$i+=2) { [Convert]::ToByte($Text.Substring($i,2),16) })) }
$request=From-Hex '000100002112a442b7e7a701bc34d686fa87dfae'
$packet4=From-Hex '0101000c2112a442b7e7a701bc34d686fa87dfae002000080001a147e112a643'
$packet6=From-Hex '010100182112a442b7e7a701bc34d686fa87dfae002000140002a1470113a9faa5d3f179bc25f4b5bed2b9d9'
$references=@{IPv4=(Get-AddressIdentity '8.8.8.8');IPv6=(Get-AddressIdentity '2001:4860:4860::8888')}
Test-Case 'STUN IPv4 XOR address vector' {
    Assert ((Read-StunAddress $packet4 $request) -eq '192.0.2.1') 'IPv4 XOR mapping mismatch'
}
Test-Case 'STUN IPv6 XOR address vector' {
    Assert ((Read-StunAddress $packet6 $request) -eq '2001:db8:1234:5678:11:2233:4455:6677') 'IPv6 XOR mapping mismatch'
}
Test-Case 'STUN rejects a different transaction' {
    $bad=$packet4.Clone(); $bad[8]=$bad[8] -bxor 1; $caught=$false
    try { Read-StunAddress $bad $request | Out-Null } catch { $caught=$_.Exception.Message -match '事务标识' }
    Assert $caught 'Mismatched transaction accepted'
}
Test-Case 'STUN rejects a truncated packet' {
    $caught=$false
    try { Read-StunAddress $packet4[0..28] $request | Out-Null } catch { $caught=$_.Exception.Message -match '长度' }
    Assert $caught 'Truncated packet accepted'
}
Test-Case 'IPv6 identity is canonical' {
    Assert ((Get-AddressIdentity '2001:4860:4860:0:0:0:0:8888').Hash -eq $references.IPv6.Hash) 'Equivalent IPv6 addresses compared differently'
}
Test-Case 'Address digests use a per-installation key, not a bare SHA-256' {
    $hash=(Get-AddressIdentity '8.8.8.8').Hash
    Assert ($hash -ne (Get-TextHash '8.8.8.8')) 'An address digest can be matched by hashing candidate addresses'
    Assert ($hash -eq $references.IPv4.Hash -and $hash -match '^[0-9a-f]{64}$') 'Digests on this installation are not stable'
    Assert (([Convert]::FromBase64String([IO.File]::ReadAllText((Join-Path $WorkRoot 'address-key.txt')).Trim())).Length -eq 32) 'Installation key was not stored in the state folder'
    $saved=$script:addressKey
    try { $script:addressKey=[byte[]](1..32); Assert ((Get-AddressIdentity '8.8.8.8').Hash -ne $hash) 'Another installation produced the same digest' }
    finally { $script:addressKey=$saved }
}
Test-Case 'A damaged installation key is replaced and kept aside' {
    $savedRoot=$StateRoot; $savedKey=$script:addressKey
    try {
        $script:StateRoot=Join-Path $WorkRoot 'damaged-key'
        [void](New-Item -ItemType Directory -Path $script:StateRoot -Force)
        [IO.File]::WriteAllText((Join-Path $script:StateRoot 'address-key.txt'),'not a key')
        $script:addressKey=$null
        Assert ((Get-AddressKey).Length -eq 32) 'No usable key after damage'
        Assert (@(Get-ChildItem -LiteralPath $script:StateRoot -Filter 'address-key.txt.invalid-*').Count -eq 1) 'The damaged key was not kept aside'
    } finally { $script:StateRoot=$savedRoot; $script:addressKey=$savedKey }
}
Test-Case 'Private, mDNS and fake-IP candidates are excluded' {
    foreach ($address in @('127.0.0.1','192.168.1.2','10.2.3.4','fe80::1','fd00::1','host.local','198.18.0.2','100.64.1.1')) {
        Assert (-not (Test-PublicAddress $address)) ('Not a public candidate: '+$address)
    }
}
Test-Case 'No UDP response never means pass' {
    Assert ((Compare-ProbeAddresses 'UDP' @() $references 2).State -eq 'unknown') 'No response passed'
}
Test-Case 'Partial successful probes remain unverified' {
    Assert ((Compare-ProbeAddresses 'UDP' @('8.8.8.8') $references 1).State -eq 'unknown') 'Partial completion passed'
}
Test-Case 'Observed different egress is reported without exposing IP' {
    $result=Compare-ProbeAddresses 'UDP' @('9.9.9.9') $references
    Assert ($result.State -eq 'warn' -and $result.Detail -match '未核验 ASN' -and $result.Detail -notmatch '9\.9\.9\.9') 'IP difference alone was treated as a confirmed wrong network'
}
Test-Case 'Separate IPv4 and IPv6 reference addresses match' {
    Assert ((Compare-ProbeAddresses 'WebRTC' @('8.8.8.8','2001:4860:4860::8888') $references).State -eq 'ok') 'Matching references not recognized'
}
Test-Case 'Missing IPv6 reference never means pass' {
    Assert ((Compare-ProbeAddresses 'IPv6' @('2001:4860:4860::8888') @{IPv4=$references.IPv4}).State -eq 'unknown') 'Missing baseline passed'
}
Test-Case 'Real IPv4 HTTP probe reaches loopback only' {
    $server=[LoopbackFixture]::Http($false)
    try {
        $result=Invoke-AddressProbe @{ProxyPort=1} $false $false ('http://127.0.0.1:'+$server.Port)
        Assert ($result.Address -eq '8.8.8.8' -and -not $server.Failure) 'Local HTTP probe failed'
    } finally { $server.Dispose() }
}
Test-Case 'Real IPv6 HTTP probe reaches loopback only' {
    $server=[LoopbackFixture]::Http($true)
    try {
        $result=Invoke-AddressProbe @{ProxyPort=1} $false $true ('http://[::1]:'+$server.Port)
        Assert ($result.Address -eq '2001:4860:4860::8888' -and -not $server.Failure) 'Local IPv6 probe failed'
    } finally { $server.Dispose() }
}
Test-Case 'Explicit proxy path goes to the fixture proxy only' {
    $server=[LoopbackFixture]::Http($false)
    try {
        $result=Invoke-AddressProbe @{ProxyPort=$server.Port} $true $false 'http://example.invalid'
        Assert ($result.Address -eq '8.8.8.8' -and $server.LastRequest -eq 'GET http://example.invalid/ HTTP/1.1') 'Proxy request bypassed fixture'
    } finally { $server.Dispose() }
}
Test-Case 'Real UDP STUN transaction uses loopback only' {
    $server=[LoopbackFixture]::Stun()
    try {
        $result=Invoke-StunProbe '127.0.0.1' $server.Port
        Assert ($result.Address -eq '8.8.8.8' -and -not $server.Failure) 'Local STUN transaction failed'
    } finally { $server.Dispose() }
}
Test-Case 'Slow proxy CONNECT receives its response beyond four seconds' {
    $server=[LoopbackFixture]::Http($false,'',502,4500)
    try {
        $caught=$false
        try { Invoke-ProbeHttp @{ProxyPort=$server.Port} 'https://example.invalid' 'Proxy' | Out-Null }
        catch { $caught=$_.Exception.Message -match 'curl 7' }
        Assert ($caught -and $server.LastRequest -eq 'CONNECT example.invalid:443 HTTP/1.1' -and -not $server.Failure) 'Proxy response was cut off or bypassed'
    } finally { $server.Dispose() }
}
Test-Case 'Slow HTTP response survives the old curl and process deadlines' {
    $server=[LoopbackFixture]::Http($false,'8.8.8.8',200,12000)
    try {
        $result=Invoke-AddressProbe @{ProxyPort=$server.Port} $true $false 'http://example.invalid'
        Assert ($result.Address -eq '8.8.8.8' -and -not $server.Failure) 'Slow valid response was discarded'
    } finally { $server.Dispose() }
}
Test-Case 'Address services cannot provide private or wrong-family baselines' {
    foreach ($value in @('192.168.1.1','198.18.0.1','2001:4860:4860::8888')) {
        function Invoke-ProbeHttp { [pscustomobject]@{Body=$value} }
        $caught=$false
        try { Invoke-AddressProbe @{ProxyPort=1} $true $false | Out-Null } catch {$caught=$true}
        Assert $caught 'Private, fake-IP or wrong-family reference accepted'
    }
}
Test-Case 'Deep-check pipeline uses independent probes and never starts a guard' {
    function Get-EnvironmentCheck($Root) { [pscustomobject]@{Ready=$true} }
    function Get-Settings($Root) { [pscustomobject]@{ProxyPort=1} }
    function Invoke-AddressProbe($Settings,$ViaProxy,$IPv6) {
        Get-AddressIdentity $(if ($IPv6) {'2001:4860:4860::8888'} else {'8.8.8.8'})
    }
    function Invoke-StunProbe($Server,$Port) { Get-AddressIdentity '8.8.8.8' }
    function Get-BrowserProbe { [pscustomobject]@{Candidates=@([pscustomobject]@{Address='8.8.8.8'});Errors=@();TimedOut=$false} }
    function Start-Guard { throw 'Live guard must never be started by diagnostics' }
    function Stop-DesktopForSwitch { throw 'Live desktop must never be stopped by diagnostics' }
    $result=Get-DeepCheck $WorkRoot
    Assert ($result.Deep -and $result.Ready -and $result.Checks.Count -eq 7) 'Deep diagnostic pipeline failed'
}
Test-Case 'Failed basic readiness prevents external deep probes' {
    function Get-EnvironmentCheck($Root) { [pscustomobject]@{Ready=$false} }
    function Invoke-AddressProbe { throw 'Unexpected external probe' }
    Assert (-not (Get-DeepCheck $WorkRoot).Ready) 'Invalid baseline was ignored'
}
Test-Case 'Isolated Edge WebRTC callback completes with no external STUN servers' {
    $browserBefore=@(Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | ForEach-Object {
        $role='browser'; if ($_.CommandLine -match '--type=([^ ]+)') { $role=$Matches[1] }
        [pscustomobject]@{Pid=$_.ProcessId;Role=$role;Probe=($_.CommandLine -match 'ClaudeProbe-')}
    })
    $browserPids=@($browserBefore | ForEach-Object Pid)
    $profilesBefore=@(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Directory -Filter 'ClaudeProbe-*' | ForEach-Object FullName)
    $result=Get-BrowserProbe -StunUrls @()
    Assert ($null -ne $result.Candidates -and -not $result.Error) 'WebRTC callback failed'
    $kept=@(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Directory -Filter 'ClaudeProbe-*' | Where-Object { $_.FullName -notin $profilesBefore })
    Assert ($kept.Count -eq 0) 'The temporary probe profile was left in TEMP'
    $after=@(Get-Process -Name msedge -ErrorAction SilentlyContinue | ForEach-Object Id)
    $exited=@($browserBefore | Where-Object { $_.Pid -notin $after })
    $exited | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $WorkRoot 'browser-exits.json') -Encoding UTF8
    Assert ($exited.Count -eq 0) ('An existing browser process exited: '+(($exited | ForEach-Object { $_.Role+' PID='+$_.Pid+' Probe='+$_.Probe }) -join ', '))
    $leftover=@(Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | Where-Object { $_.CommandLine -match 'ClaudeProbe-' -and $_.ProcessId -notin $browserPids })
    Assert ($leftover.Count -eq 0) 'A disposable probe browser was left running'
}
Test-Case 'Only stale probe profiles are cleared from TEMP' {
    $temp=Join-Path $WorkRoot 'temp-sweep'
    $old=Join-Path $temp ('ClaudeProbe-'+[guid]::NewGuid().ToString('N'))
    $fresh=Join-Path $temp ('ClaudeProbe-'+[guid]::NewGuid().ToString('N'))
    $tests=Join-Path $temp ('ClaudeProbeTests-'+[guid]::NewGuid().ToString('N'))
    $other=Join-Path $temp 'ClaudeProbe-notanonce'
    foreach ($directory in $old,$fresh,$tests,$other) { [void](New-Item -ItemType Directory -Path (Join-Path $directory 'Default') -Force) }
    foreach ($directory in $old,$tests,$other) { (Get-Item -LiteralPath $directory).CreationTime=(Get-Date).AddHours(-2) }
    $saved=$env:TMP,$env:TEMP
    try { $env:TMP=$temp; $env:TEMP=$temp; Clear-StaleProbeProfiles }
    finally { $env:TMP,$env:TEMP=$saved }
    Assert (-not (Test-Path -LiteralPath $old)) 'A stale probe profile was kept'
    Assert ((Test-Path -LiteralPath $fresh) -and (Test-Path -LiteralPath $tests) -and (Test-Path -LiteralPath $other)) 'A recent or unrelated folder was removed'
}
Test-Case 'Existing Claude and FlClash processes remain running' {
    $after=@(Get-Process -Name Claude,FlClash,FlClashCore -ErrorAction SilentlyContinue | ForEach-Object Id)
    Assert (@($liveBefore | Where-Object { $_ -notin $after }).Count -eq 0) 'A live process exited'
}
$results | ConvertTo-Json -Depth 5
if (@($results | Where-Object Status -eq 'FAIL').Count) { exit 1 }
