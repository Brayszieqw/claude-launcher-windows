param([string]$WorkRoot=(Join-Path $env:TEMP ('ClaudeInsightsTests-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$package=Split-Path -Parent $PSScriptRoot
. (Join-Path $package 'claude-switch.ps1') -StateRoot $WorkRoot
Add-Type -Path (Join-Path $PSScriptRoot 'LoopbackFixtures.cs')
$results=New-Object System.Collections.Generic.List[object]
$before=@(Get-Process -Name Claude,FlClash,FlClashCore -ErrorAction SilentlyContinue | ForEach-Object Id)
function Get-DnsClientCache {@()}
function Assert($Condition,$Message) { if (-not $Condition) { throw $Message } }
function Test-Case($Name,[scriptblock]$Body) {
    try { & $Body; $results.Add([pscustomobject]@{Name=$Name;Status='PASS';Detail=''}) }
    catch { $results.Add([pscustomobject]@{Name=$Name;Status='FAIL';Detail=$_.Exception.Message}) }
}
$pure='{"ip":"8.8.8.8","countryCode":"US","asn":15169,"asOrganization":"测试组织","fraudScore":75,"isResidential":false}'
Test-Case 'HTTP reader preserves Unicode through an explicit loopback proxy' {
    $server=[LoopbackFixture]::Http($false,$pure,200)
    try {
        $response=Invoke-ProbeHttp @{ProxyPort=$server.Port} 'http://example.invalid' 'Proxy'
        $data=Read-IpPureResponse $response.Body
        Assert ($data.Organization -eq '测试组织' -and $data.Score -eq 75) 'UTF-8 response lost data'
        Assert ($server.LastRequest -eq 'GET http://example.invalid/ HTTP/1.1') 'Explicit proxy not used'
    } finally { $server.Dispose() }
}
Test-Case 'Redirects, access challenges and rate limits are not a pass' {
    foreach ($code in @(302,403,429)) {
        $server=[LoopbackFixture]::Http($false,'challenge',$code)
        try {
            $caught=$false
            try { Invoke-ProbeHttp @{ProxyPort=$server.Port} 'http://example.invalid' 'Proxy' | Out-Null }
            catch { $caught=$_.Exception.Message -match "HTTP $code" }
            Assert $caught ('HTTP '+$code+' was accepted')
        } finally { $server.Dispose() }
    }
}
Test-Case 'Unavailable explicit proxy never falls back to the reachable target' {
    $target=[LoopbackFixture]::Http($false,'unexpected',200)
    $reserved=New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback),0
    $reserved.Start(); $port=$reserved.LocalEndpoint.Port; $reserved.Stop()
    try {
        $caught=$false
        try { Invoke-ProbeHttp @{ProxyPort=$port} ('http://127.0.0.1:'+$target.Port) 'Proxy' | Out-Null } catch { $caught=$true }
        Assert ($caught -and -not $target.LastRequest) 'Proxy failure bypassed to target'
    } finally { $target.Dispose() }
}
Test-Case 'Cloudflare challenge HTML cannot masquerade as a trace' {
    $caught=$false
    try { Read-TraceResponse '<html>Challenge</html>' | Out-Null } catch { $caught=$true }
    Assert $caught 'Challenge HTML passed'
    $trace=Read-TraceResponse "ip=8.8.8.8`nloc=US`n"
    Assert ($trace.Country -eq 'US' -and $trace.Identity.Family -eq 'IPv4') 'Trace parsing failed'
}
Test-Case 'IPPure missing fields remain unknown and wrong types are rejected' {
    $data=Read-IpPureResponse '{"ip":"8.8.8.8","countryCode":"US"}'
    Assert ($null -eq $data.Score -and $data.Residential -eq '未提供') 'Missing score converted to zero or residential'
    foreach ($body in @('{"ip":"8.8.8.8","countryCode":"US","fraudScore":"0"}', '{"ip":"8.8.8.8","countryCode":"US","fraudScore":101}', '{"ip":"127.0.0.1","countryCode":"US"}')) {
        $caught=$false; try { Read-IpPureResponse $body | Out-Null } catch { $caught=$true }
        Assert $caught 'Malformed provider response accepted'
    }
}
Test-Case 'DNS keeps all resolver addresses for live display and detects ECS' {
    $dns=Read-DnsProbeResponse 'Surfshark' '{"8.8.8.8":{"IP":"8.8.8.8"},"1.1.1.1":{"IP":"1.1.1.1"},"2":{"IP":"8.8.8.8"}}'
    Assert ($dns.Hashes.Count -eq 2) 'Resolvers were dropped or duplicated'
    $dns=Read-DnsProbeResponse 'IP-API' '{"dns":{"ip":"8.8.8.8","geo":"United States - Google"},"edns":{"ip":"192.0.2.0"}}'
    Assert ($dns.Ecs -and $dns.Resolvers[0].Address -eq '8.8.8.8' -and $dns.EcsDetail -notmatch '192\.0\.2') 'Resolver address missing or ECS subnet exposed'
}
Test-Case 'Empty DNS results and private resolver values cannot pass' {
    foreach ($body in @('{}','{"0":{"IP":"192.168.1.1"}}','{"0":{"IP":"invalid"}}')) {
        $caught=$false; try { Read-DnsProbeResponse Surfshark $body | Out-Null } catch { $caught=$true }
        Assert $caught 'Invalid resolver accepted'
    }
}
Test-Case 'Network prerequisites stop external probes without touching sessions' {
    function Get-ProtectionHealth { [pscustomobject]@{Healthy=$false} }
    function Invoke-ProbeHttp { throw 'Unexpected request' }
    function Start-Guard { throw 'Unexpected guard' }
    function Stop-DesktopForSwitch { throw 'Unexpected stop' }
    $result=Get-NetworkInsights $WorkRoot
    Assert ($result.Checks.Count -eq 1 -and $result.Checks[0].State -eq 'unknown') 'Prerequisites ignored'
}
Test-Case 'Network pipeline retains live addresses, redacts reports and leaves scores informational' {
    $calls=New-Object System.Collections.Generic.List[object]
    function Get-ProtectionHealth { [pscustomobject]@{Healthy=$true} }
    function Invoke-ProbeHttp($Settings,$Endpoint,$Route) {
        $calls.Add([pscustomobject]@{Endpoint=$Endpoint;Route=$Route})
        $body=switch -Regex ($Endpoint) {
            'api6\.ipify' {'2001:4860:4860::8888';break}
            'api\.ipify' {'8.8.8.8';break}
            '6\.ipcheck' {"ip=2001:4860:4860::8888`nloc=US`ntls=TLSv1.3`n";break}
            'my\.ippure' {$pure;break}
            'edns\.ip-api' {'{"dns":{"ip":"1.1.1.1"}}';break}
            'surfsharkdns' {'{"0":{"IP":"1.1.1.1"}}';break}
            'fastly-analytics' {'{"dns_resolver_info":{"ip":"1.1.1.1","cc":"US","as_name":"Fixture"}}';break}
            'browserleaks' {'{"1.1.1.1":["US","Fixture City","Fixture ISP"]}';break}
            'status.claude' {'{"status":{"indicator":"none","description":"All Operational"},"page":{"updated_at":"2026-10-16T12:00:00Z"},"components":[{"name":"API","status":"operational"}],"incidents":[]}';break}
            default {"ip=8.8.8.8`nloc=US`ntls=TLSv1.3`nhttp=http/2`ncolo=NRT`nwarp=off`n"}
        }
        [pscustomobject]@{Body=$body;Status=200;Milliseconds=10}
    }
    function Start-Guard { throw 'Unexpected guard' }
    function Stop-DesktopForSwitch { throw 'Unexpected stop' }
    $result=Get-NetworkInsights $WorkRoot
    $invalid=@($result.Checks | Where-Object State -in @('fail','unknown'))
    Assert ($invalid.Count -eq 0) ('Valid responses rejected: '+(($invalid | ForEach-Object {$_.Name+': '+$_.Detail}) -join '; '))
    Assert (($result.Checks | Where-Object Name -eq 'IPPure 信誉评分').State -eq 'info') 'Provider score became a risk gate'
    Assert (@($result.LiveDetails | Where-Object {$_.Type -eq 'Egress' -and $_.Address -eq '8.8.8.8'}).Count -eq 31) 'Live domain addresses were lost'
    Assert (@($result.LiveDetails | Where-Object {$_.Type -eq 'DNS' -and $_.Address -eq '1.1.1.1'}).Count -eq 8) 'Live resolver addresses were lost'
    Save-DiagnosticReport (Join-Path $WorkRoot 'address-report') $result Network | Out-Null
    $saved=Get-Content -LiteralPath $result.ReportPath -Raw -Encoding UTF8
    Assert ($saved -notmatch 'LiveDetails|8\.8\.8\.8|1\.1\.1\.1|2001:4860') 'Full addresses persisted into a report'
    $md=ConvertTo-DiagnosticMarkdown ($saved | ConvertFrom-Json)
    Assert ($md -notmatch '8\.8\.8\.8|1\.1\.1\.1|2001:4860') 'Full addresses escaped into export'
    Assert ($calls.Count -eq 44) 'Unexpected request count or retries'
    foreach ($route in @('System','Proxy')) {
        Assert (@($calls | Where-Object { $_.Endpoint -match 'edns|surfsharkdns|fastly-analytics|browserleaks' -and $_.Route -eq $route }).Count -eq 4) 'DNS path coverage incomplete'
    }
    Assert (@($result.Observations | Where-Object Type -eq 'DNS').Count -eq 8) 'Resolver details not retained'
    Assert (($result.Checks | Where-Object Name -eq 'claude.ai · 显式代理').Evidence -match 'TLSv1.3') 'Transport evidence dropped'
    Assert (@($calls | Where-Object { $_.Endpoint -match '^https://claude\.' -and $_.Route -eq 'System' }).Count -eq 2) 'Claude system paths missing'
    Assert (@($calls | Where-Object { $_.Endpoint -match 'ippure|ipcheck|ipify' -and $_.Route -ne 'Proxy' }).Count -eq 0) 'Provider request bypassed proxy'
}
Test-Case 'Provider failures retain partial results without blanket success' {
    function Get-ProtectionHealth { [pscustomobject]@{Healthy=$true} }
    function Invoke-ProbeHttp { throw '服务返回 HTTP 429' }
    $result=Get-NetworkInsights $WorkRoot
    Assert (@($result.Checks | Where-Object State -eq 'unknown').Count -eq 45) 'Failure evidence lost'
    Assert (@($result.Checks | Where-Object State -eq 'ok').Count -eq 0) 'Unavailable service marked pass'
}
Test-Case 'Local browser fingerprint executes, saves only hashes and detects changes' {
    $probe=Get-BrowserProbe -Mode Fingerprint -StunUrls @()
    Assert ($probe.Fingerprint.Canvas -match '^[a-f0-9]{64}$') 'Canvas was not measured'
    Assert ($probe.Fingerprint.Emoji -match '^[a-f0-9]{64}$') 'Emoji was not measured'
    Assert ($probe.Fingerprint.Audio -match '^[a-f0-9]{64}$') 'Audio was not computed'
    Assert ($probe.Fingerprint.FontMetrics -match '^[a-f0-9]{64}$') 'Font metrics missing'
    Assert ($probe.Fingerprint.WebGLCapabilities -match 'MAX_TEXTURE_SIZE') 'GPU limits missing'
    Assert ($probe.Fingerprint.CanvasRepeat -match '一致') 'Repeated canvas did not agree'
    Assert ($probe.Candidates.Count -eq 0) 'Fingerprint mode started WebRTC'
    Assert ($probe.Fingerprint.Timezone -and $probe.Fingerprint.Languages -and $probe.Fingerprint.Locale -and $probe.Fingerprint.TimezoneOffset -match '^UTC') 'Regional display measurements missing'
    function Get-BrowserProbe { $probe }
    Get-FingerprintInsights $WorkRoot -Remember | Out-Null
    $baselinePath=Join-Path $WorkRoot 'fingerprint-baseline.json'
    $saved=Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json
    Assert (@($saved.Hashes.PSObject.Properties).Count -eq 20) 'Incomplete baseline saved'
    foreach ($entry in $saved.Hashes.PSObject.Properties) { Assert ($entry.Value -match '^[a-f0-9]{64}$') 'Raw feature saved' }
    $same=Get-FingerprintInsights $WorkRoot
    Assert (($same.Checks | Where-Object Name -eq '设备基准对比').State -eq 'ok') 'Identical fingerprint changed'
    $probe.Fingerprint.Timezone='Fixture/Other'
    $probe.Fingerprint.Languages='fixture-language'
    $regional=Get-FingerprintInsights $WorkRoot
    Assert (($regional.Checks | Where-Object Name -eq '设备基准对比').State -eq 'ok') 'Regional change incorrectly affected fingerprint baseline'
    Assert (@($regional.Checks | Where-Object {$_.Group -eq '时区与语言（忽略影响）' -and $_.State -eq 'info'}).Count -eq 4) 'Regional fields affected risk states'
    $probe.Fingerprint.Canvas=('a'*64)
    $changed=Get-FingerprintInsights $WorkRoot
    Assert (($changed.Checks | Where-Object Name -eq '设备基准对比').State -eq 'warn') 'Canvas change was missed'
    Get-FingerprintInsights $WorkRoot -Remember | Out-Null
    Assert (@(Get-ChildItem -LiteralPath $WorkRoot -Filter 'fingerprint-baseline.json.backup-*').Count -eq 1) 'Old baseline not backed up'
    $probe.Fingerprint.Canvas=''
    $partial=Get-FingerprintInsights $WorkRoot
    Assert (($partial.Checks | Where-Object Name -eq '设备基准对比').State -eq 'unknown') 'Missing feature marked equal'
    $caught=$false; try { Get-FingerprintInsights $WorkRoot -Remember | Out-Null } catch { $caught=$true }
    Assert $caught 'Incomplete sample replaced baseline'
}
Test-Case 'Resolver metadata masks embedded addresses while retaining explicit address fields' {
    $dns=Read-DnsProbeResponse BrowserLeaks '{"8.8.8.8":["US","City 8.8.8.8","Google"],"2001:4860:4860::8888":["US","Other","Org 2001:4860:4860::8888"]}'
    Assert ($dns.Resolvers.Count -eq 2 -and $dns.Resolvers[1].Family -eq 'IPv6') 'IPv6 or resolver metadata dropped'
    Assert ((@($dns.Resolvers | Select-Object Geo,Organization) | ConvertTo-Json -Depth 8) -notmatch '8\.8\.8\.8|2001:4860') 'Metadata exposed an address'
    $dns=Read-DnsProbeResponse Fastly '{"dns_resolver_info":{"ip":"8.8.8.8","cc":"us","as_name":"Google"}}'
    Assert ($dns.Resolvers[0].Country -eq 'US' -and $dns.Resolvers[0].Organization -eq 'Google' -and $null -eq $dns.Ecs) 'Fastly schema or unknown ECS wrong'
    $dns=Read-DnsProbeResponse IP-API '{"dns":{"ip":"8.8.8.8"},"edns":{"ip":"192.0.2.0/24"}}'
    Assert ($dns.Ecs -and $dns.EcsDetail -match '/24' -and $dns.EcsDetail -notmatch '192\.0') 'ECS prefix was not explained safely'
    Assert ((Get-ProbeText '2026-10-16T12:24:40Z') -eq '2026-10-16T12:24:40Z') 'Timestamp mistaken for IP'
}
Test-Case 'Independent system path is measured when same-domain proxy trace fails' {
    $calls=New-Object System.Collections.Generic.List[string]
    function Get-ProtectionHealth { [pscustomobject]@{Healthy=$true} }
    function Invoke-ProbeHttp($Settings,$Endpoint,$Route) {
        $calls.Add($Endpoint+' '+$Route)
        if ($Endpoint -eq 'https://claude.ai/cdn-cgi/trace' -and $Route -eq 'System') {return [pscustomobject]@{Body="ip=8.8.8.8`nloc=US`n";Status=200;Milliseconds=1}}
        throw 'fixture unavailable'
    }
    $result=Get-NetworkInsights $WorkRoot
    Assert ($calls.Contains('https://claude.ai/cdn-cgi/trace System')) 'System path skipped after proxy failure'
    $row=$result.Checks | Where-Object Name -eq 'claude.ai · 系统 / TUN'
    Assert ($row.State -eq 'unknown' -and $row.Detail -match '摘要') 'Missing reference falsely passed or evidence lost'
}
Test-Case 'IPv6-only target returning IPv4 is not a verified IPv6 path' {
    function Get-ProtectionHealth { [pscustomobject]@{Healthy=$true} }
    function Invoke-ProbeHttp { [pscustomobject]@{Body="ip=8.8.8.8`nloc=US`n";Status=200;Milliseconds=1} }
    $result=Get-NetworkInsights $WorkRoot
    $row=$result.Checks | Where-Object Name -eq '6.ipcheck.ing · 显式代理'
    Assert ($row.State -eq 'unknown' -and $row.Detail -match '地址族') 'Wrong-family target silently accepted'
}
Test-Case 'Official incidents and degraded components cannot appear operational' {
    $rows=@(Get-ServiceStatusRows '{"status":{"indicator":"minor","description":"Partial outage"},"page":{"updated_at":"2026-10-16T12:24:40Z"},"components":[{"name":"Claude","status":"degraded_performance"},{"name":"Future","status":"new_state"}],"incidents":[{"name":"Issue","status":"investigating"}]}')
    Assert (@($rows | Where-Object State -eq 'warn').Count -eq 3) 'Incident or degradation lost'
    Assert (@($rows | Where-Object State -eq 'unknown').Count -eq 1) 'New state defaulted to healthy'
    $caught=$false;try {Get-ServiceStatusRows '{}' | Out-Null}catch {$caught=$true}
    Assert $caught 'Empty status response accepted'
}
Test-Case 'History excludes session paths, compares hashes and exports actual reports with backup' {
    $root=Join-Path $WorkRoot 'history'
    $result=[pscustomobject]@{CheckedAt='2026-10-16 12:00:00';Checks=@((New-InsightRow 'Example' 'info' 'UTF8 中文' 'Group' 'Source' 'Evidence' 'Advice'));Observations=@([pscustomobject]@{Type='Egress';Provider='Fixture';Route='Proxy';Family='IPv4';Hash=('a'*64)});App=[pscustomobject]@{Data='private-session-path'};Message='read only'}
    Save-DiagnosticReport $root $result Network | Out-Null
    $first=@(Get-DiagnosticReports $root)[0].Report
    Assert ($first.CheckedAt -eq $result.CheckedAt) 'Measurement time replaced with import time'
    Assert (($first | ConvertTo-Json -Depth 8) -notmatch 'private-session') 'App data path persisted'
    $result.Observations[0].Hash='b'*64
    $result.CheckedAt='2026-10-16 12:01:00'
    $result.PSObject.Properties.Remove('ReportPath')
    Save-DiagnosticReport $root $result Network | Out-Null
    $reports=@(Get-DiagnosticReports $root)
    Assert ($reports.Count -eq 2) 'History overwritten'
    Assert ((Compare-DiagnosticReports $reports[0].Report $first) -match '摘要变化') 'Changed egress was missed'
    $md=Join-Path $root 'export.md';$json=Join-Path $root 'export.json'
    Export-DiagnosticReport $first $md
    Export-DiagnosticReport $reports[0].Report $md
    Export-DiagnosticReport $first $json
    Assert (@(Get-ChildItem $root -Filter 'export.md.backup-*').Count -eq 1) 'Export overwrote without backup'
    Assert ((Get-Content $md -Raw -Encoding UTF8) -match 'UTF8 中文') 'Markdown content missing'
    Assert ((Get-Content $json -Raw -Encoding UTF8 | ConvertFrom-Json).Kind -eq 'Network') 'JSON round trip failed'
    Set-Content (Join-Path $root 'diagnostics/corrupt.json') '{' -Encoding UTF8
    Assert (@(Get-DiagnosticReports $root | Where-Object Error).Count -eq 1) 'Corrupt report concealed'
}
Test-Case 'Old fingerprint baseline stays unmodified until explicit resampling' {
    $root=Join-Path $WorkRoot 'legacy-fingerprint'
    $path=Join-Path $root 'fingerprint-baseline.json'
    Write-JsonAtomic $path ([pscustomobject]@{Schema=1;Hashes=@{Canvas=('a'*64)}})
    $beforeHash=(Get-FileHash $path).Hash
    function Get-BrowserProbe { [pscustomobject]@{Fingerprint=[pscustomobject]@{Schema=2;Canvas=('b'*64)}} }
    $result=Get-FingerprintInsights $root
    Assert (($result.Checks | Where-Object Name -eq '设备基准对比').State -eq 'unknown') 'Old algorithm silently compared'
    Assert ((Get-FileHash $path).Hash -eq $beforeHash) 'Old baseline was mutated'
}

Test-Case 'Environment preferences read actual Windows values without changing settings' {
    $beforeZone=(Get-TimeZone).Id
    $beforeLanguages=@(Get-WinUserLanguageList | ForEach-Object LanguageTag) -join ','
    $prefs=Get-EnvironmentPreferences
    Assert ($prefs.Timezone -eq $beforeZone -and $prefs.Timezones.Count -gt 1) 'Timezone read failed'
    Assert ($prefs.Format -and $prefs.Formats.Count -gt 1 -and $prefs.Languages.Count -ge 1) 'Preference choices missing'
    Assert ((Get-TimeZone).Id -eq $beforeZone -and (@(Get-WinUserLanguageList | ForEach-Object LanguageTag) -join ',') -eq $beforeLanguages) 'Read mutated preferences'
}
Test-Case 'Manual setting changes validate choices, back up first and verify readback using isolated commands' {
    $root=Join-Path $WorkRoot 'settings-fixture'
    $script:mockPrefs=[pscustomobject]@{Timezone='old-zone';Format='en-US';Language='en-US';Timezones=@(@{Id='old-zone'},@{Id='new-zone'});Formats=@(@{Id='en-US'},@{Id='zh-CN'});Languages=@(@{Id='en-US'},@{Id='zh-CN'})}
    $script:mockLanguageList=New-Object 'System.Collections.Generic.List[object]'
    $script:mockLanguageList.Add([pscustomobject]@{LanguageTag='en-US';InputMethodTips=@('keep-en');Spellchecking=$true;Handwriting=$false})
    $script:mockLanguageList.Add([pscustomobject]@{LanguageTag='zh-CN';InputMethodTips=@('keep-zh');Spellchecking=$false;Handwriting=$true})
    $script:mutations=0
    function Get-EnvironmentPreferences {$script:mockPrefs}
    function Get-WinUserLanguageList {return ,$script:mockLanguageList}
    function Set-TimeZone($Id) {
        Assert (@(Get-ChildItem (Join-Path $root 'environment-settings') -Filter '*.json').Count -eq 1) 'Mutation happened before backup'
        $script:mutations++;$script:mockPrefs.Timezone=$Id
    }
    function Set-Culture($CultureInfo) {$script:mutations++;$script:mockPrefs.Format=$CultureInfo}
    function Set-WinUserLanguageList($LanguageList,[switch]$Force) {
        Assert ($LanguageList.Count -eq 2 -and $LanguageList[0].InputMethodTips[0] -eq 'keep-zh' -and $LanguageList[1].InputMethodTips[0] -eq 'keep-en') 'Language reorder lost input methods'
        Assert ($LanguageList[0].Handwriting -and $LanguageList[1].Spellchecking) 'Language properties changed'
        $script:mutations++;$script:mockPrefs.Language=$LanguageList[0].LanguageTag
    }
    $caught=$false;try {Set-EnvironmentPreference $root Timezone 'not-installed' | Out-Null}catch {$caught=$true}
    Assert ($caught -and $script:mutations -eq 0) 'Unknown timezone reached system setter'
    Set-EnvironmentPreference $root Timezone 'old-zone' | Out-Null
    Assert ($script:mutations -eq 0 -and -not (Test-Path (Join-Path $root 'environment-settings'))) 'No-op wrote settings or backup'
    Set-EnvironmentPreference $root Timezone 'new-zone' | Out-Null
    Set-EnvironmentPreference $root Format 'zh-CN' | Out-Null
    Set-EnvironmentPreference $root Language 'zh-CN' | Out-Null
    Assert ($script:mutations -eq 3) 'Requested changes did not reach isolated setter'
    $backups=@(Get-ChildItem (Join-Path $root 'environment-settings') -Filter '*.json' | ForEach-Object {Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json})
    Assert ($backups.Count -eq 3 -and @($backups | Where-Object {$_.Kind -eq 'Language' -and $_.Languages[0].InputMethodTips[0] -eq 'keep-en'}).Count -eq 1) 'Backup lost original language order or input methods'
    function Set-Culture($CultureInfo) {throw 'fixture denied'}
    $caught=$false;try {Set-EnvironmentPreference $root Format 'en-US' | Out-Null}catch {$caught=$_.Exception.Message -match 'fixture denied.*修改前记录'}
    Assert ($caught -and $script:mockPrefs.Format -eq 'zh-CN') 'Setter failure was hidden'
    function Set-Culture($CultureInfo) {}
    $caught=$false;try {Set-EnvironmentPreference $root Format 'en-US' | Out-Null}catch {$caught=$_.Exception.Message -match '读回值'}
    Assert $caught 'Unconfirmed system change reported success'
}

Test-Case 'Existing Claude and FlClash processes remain running' {
    $after=@(Get-Process -Name Claude,FlClash,FlClashCore -ErrorAction SilentlyContinue | ForEach-Object Id)
    Assert (@($before | Where-Object {$_ -notin $after}).Count -eq 0) 'A pre-existing process exited'
}
$results | ConvertTo-Json -Depth 5
if (@($results | Where-Object Status -eq 'FAIL').Count) { exit 1 }
