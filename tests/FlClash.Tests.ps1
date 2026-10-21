param([string]$WorkRoot=(Join-Path $env:TEMP ('ClaudeFlClashTests-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$package=Split-Path -Parent $PSScriptRoot
. (Join-Path $package 'claude-switch.ps1') -StateRoot $WorkRoot
[void](New-Item -ItemType Directory -Path $WorkRoot -Force)
$results=New-Object System.Collections.Generic.List[object]
function Get-GuardDnsCheck { New-Check 'fixture DNS' 'ok' 'fixture' }
function Assert($Condition,$Message) {if (-not $Condition) {throw $Message}}
function Test-Case($Name,[scriptblock]$Body) {
    try {& $Body; $results.Add([pscustomobject]@{Name=$Name;Status='PASS';Detail=''})}
    catch {$results.Add([pscustomobject]@{Name=$Name;Status='FAIL';Detail=$_.Exception.Message})}
}
function Expect-Error([scriptblock]$Body) {
    $caught=$false
    try {& $Body | Out-Null} catch {$caught=$true}
    Assert $caught 'Expected rejection'
}
$script:goodYaml=@'
dns:
  enable: true
  nameserver:
    - https://1.1.1.1/dns-query
    - https://1.0.0.1/dns-query
  direct-nameserver: []
tun:
  enable: true
  strict-route: true
  dns-hijack:
    - any:53
    - tcp://any:53
proxies:
  - name: private-node
    password: do-not-report-password
'@
function New-FixtureSnapshot {
    [pscustomobject]@{Active=$true;Version='0.9.1+fixture';Generated=$script:goodYaml.Replace("`r",'');ScriptExists=$true;Profile=@('script','368065208121298944','1');Patch=[pscustomobject]@{'tun-override-keys'=@('strict-route');'tun-override'=[pscustomobject]@{'strict-route'=$true};'dns-override-keys'=@('direct-nameserver')}}
}
function Get-FlClashSnapshot {$script:snapshot}
Test-Case 'Repaired config is recognized without claiming a browser pass' {
    $script:snapshot=New-FixtureSnapshot
    $r=Get-FlClashCheck
    Assert (@($r.Checks|Where-Object Blocking).Count -eq 0) 'Repaired settings blocked'
    Assert (($r.Checks|Where-Object Name -eq '直连专用 DNS').State -eq 'ok') 'Empty direct DNS did not inherit'
    Assert (($r.Checks|Where-Object Name -eq 'DNS 劫持覆盖').State -eq 'ok') 'TCP and UDP not recognized'
    Assert (($r.Checks|Where-Object Name -eq '主 DNS 与覆写顺序').Detail -match '2 项') 'Nameserver list collapsed'
    Assert (($r.Checks|Where-Object Name -eq '浏览器复测与证据范围').Detail -match '不代表 DNS 已无泄露') 'Configuration pass became a browser pass'
    Assert (($r|ConvertTo-Json -Depth 8) -notmatch 'private-node|do-not-report-password|368065208121298944') 'Private config leaked into report'
}
Test-Case 'Missing strict route and disabled DNS or TUN block new starts' {
    foreach ($case in @(@('  strict-route: true','', '严格路由'),@('dns:\n  enable: true','dns:\n  enable: false','DNS 接管'),@('tun:\n  enable: true','tun:\n  enable: false','TUN 配置'))) {
        $script:snapshot=New-FixtureSnapshot
        $snapshot.Generated=$snapshot.Generated.Replace($case[0].Replace('\n',"`n"),$case[1].Replace('\n',"`n"))
        $snapshot.Patch.'tun-override-keys'=@()
        $r=(Get-FlClashCheck).Checks|Where-Object Name -eq $case[2]
        Assert ($r.Blocking -and $r.State -eq 'fail') ('Missing block: '+$case[2])
    }
}
Test-Case 'Selected strict-route override must agree with generated state' {
    $script:snapshot=New-FixtureSnapshot
    $snapshot.Patch.'tun-override'.'strict-route'=$false
    $r=(Get-FlClashCheck).Checks|Where-Object Name -eq '严格路由'
    Assert ($r.State -eq 'unknown' -and $r.Blocking) 'Contradictory settings passed'
}
Test-Case 'Script mode with null, orphaned or missing script blocks' {
    foreach ($case in @('null','orphan','file')) {
        $script:snapshot=New-FixtureSnapshot
        if ($case -eq 'null') {$snapshot.Profile=@('script',$null,'0')}
        if ($case -eq 'orphan') {$snapshot.Profile=@('script','42','0')}
        if ($case -eq 'file') {$snapshot.ScriptExists=$false}
        $r=(Get-FlClashCheck).Checks|Where-Object Name -eq '当前配置的脚本绑定'
        Assert ($r.State -eq 'fail' -and $r.Blocking) ('Broken script passed: '+$case)
    }
}
Test-Case 'Standard profiles are valid; unreadable binding is unknown' {
    $script:snapshot=New-FixtureSnapshot
    $snapshot.Profile=@('standard',$null,'0')
    Assert (@((Get-FlClashCheck).Checks|Where-Object Blocking).Count -eq 0) 'Standard mode forced an optional script'
    $snapshot.Profile=$null
    $r=(Get-FlClashCheck).Checks|Where-Object Name -eq '当前配置的脚本绑定'
    Assert ($r.State -eq 'unknown' -and $r.Blocking) 'Unreadable binding passed'
}
Test-Case 'Domestic direct DNS warns but does not assert a proven leak' {
    $script:snapshot=New-FixtureSnapshot
    $snapshot.Generated=$snapshot.Generated.Replace('direct-nameserver: []','direct-nameserver: [https://dns.alidns.com/dns-query, https://doh.pub/dns-query]')
    $r=(Get-FlClashCheck).Checks|Where-Object Name -eq '直连专用 DNS'
    Assert ($r.State -eq 'warn' -and -not $r.Blocking -and $r.Detail -match '国内公共解析器.*可能') 'Domestic branch was hidden or overclaimed'
}
Test-Case 'Foreign direct DNS remains a separate branch; main overrides remain visible' {
    $script:snapshot=New-FixtureSnapshot
    $snapshot.Generated=$snapshot.Generated.Replace('direct-nameserver: []',"direct-nameserver:`n    - https://9.9.9.9/dns-query")
    $snapshot.Patch.'dns-override-keys'=@('nameserver','fallback')
    $r=Get-FlClashCheck
    Assert (($r.Checks|Where-Object Name -eq '直连专用 DNS').Detail -match '独立 DNS') 'Nonempty direct DNS was treated as inherited'
    Assert (($r.Checks|Where-Object Name -eq '主 DNS 与覆写顺序').State -eq 'warn') 'Selected main override hidden'
}
Test-Case 'UDP shorthand cannot pass TCP coverage' {
    $script:snapshot=New-FixtureSnapshot
    $snapshot.Generated=$snapshot.Generated.Replace('    - tcp://any:53','')
    $r=(Get-FlClashCheck).Checks|Where-Object Name -eq 'DNS 劫持覆盖'
    Assert ($r.State -eq 'warn' -and $r.Detail -match 'TCP：未显式覆盖') 'UDP shorthand counted as TCP'
}
Test-Case 'Generated YAML reader supports inline, quoted and indented lists' {
    Assert (@(Read-FlClashGeneratedField "tun:`n    dns-hijack: ['any:53', tcp://any:53] # comment`ndns: {ignored: true}" tun dns-hijack).Count -eq 2) 'Inline quoted list failed'
    Assert ((Read-FlClashGeneratedField "tun:`n  strict-route: true # explanation" tun strict-route) -eq 'true') 'Trailing comment failed'
    Assert (@(Read-FlClashGeneratedField "dns:`n  nameserver:`n  - https://1.1.1.1/dns-query#PROXY`n  direct-nameserver: []" dns nameserver).Count -eq 1) 'Indentless generated list failed'
}
Test-Case 'DNS servers routed through Chinese, emoji or spaced proxy groups are read' {
    $cases=[ordered]@{
        '    - https://1.1.1.1/dns-query#节点选择'="https://1.1.1.1/dns-query#节点选择"
        '    - https://dns.google/dns-query#🚀 节点选择'="https://dns.google/dns-query#🚀 节点选择"
        "    - 'https://dns.google/dns-query#🚀 节点选择'"="https://dns.google/dns-query#🚀 节点选择"
        '    - "https://1.1.1.1/dns-query#Proxy Group"'="https://1.1.1.1/dns-query#Proxy Group"
        '    - https://dns.google/dns-query#香港:01&h3=true # comment'="https://dns.google/dns-query#香港:01&h3=true"
    }
    foreach ($line in $cases.Keys) {
        $value=@(Read-FlClashGeneratedField ("dns:`n  nameserver:`n"+$line+"`n  direct-nameserver: []") dns nameserver)
        Assert ($value.Count -eq 1 -and $value[0] -ceq $cases[$line]) ('Proxy group was not read: '+$line)
    }
    Assert (@(Read-FlClashGeneratedField "dns:`n  nameserver: [https://1.1.1.1/dns-query#节点选择, system]" dns nameserver).Count -eq 2) 'Inline list with a proxy group failed'
    $script:snapshot=New-FixtureSnapshot
    $snapshot.Generated=$snapshot.Generated.Replace('    - https://1.0.0.1/dns-query','    - https://dns.google/dns-query#🚀 节点选择')
    $r=Get-FlClashCheck
    Assert (@($r.Checks|Where-Object Blocking).Count -eq 0) 'A proxy-group DNS server blocked launch'
    Assert (($r.Checks|Where-Object Name -eq '主 DNS 与覆写顺序').Detail -match '2 项') 'Proxy-group DNS server was not counted'
}
Test-Case 'Proxy groups never hide YAML that is not a plain server' {
    foreach ($line in @('    - https://1.1.1.1/dns-query#组: 值','    - https://1.1.1.1/dns-query#','    - &anchor https://1.1.1.1/dns-query#组','    - "https://1.1.1.1/dns-query#组''名"')) {
        Expect-Error {Read-FlClashGeneratedField ("dns:`n  nameserver:`n"+$line+"`n  direct-nameserver: []") dns nameserver}
    }
}
Test-Case 'Duplicates, aliases, maps and unsupported syntax cannot produce a pass' {
    foreach ($body in @("tun:`n  strict-route: true`n  strict-route: false",'tun: {strict-route: true}',"tun:`n  <<: *base`n  strict-route: true","tun:`n  strict-route: *saved")) {
        Expect-Error {Read-FlClashGeneratedField $body tun strict-route}
    }
    $script:snapshot=New-FixtureSnapshot
    $snapshot.Generated=$snapshot.Generated.Replace('  nameserver:', '  nameserver: {key: value}')
    $r=(Get-FlClashCheck).Checks|Where-Object Name -eq 'DNS 上游配置'
    Assert ($r.State -eq 'unknown' -and $r.Blocking) 'Unsupported YAML passed'
    $snapshot.Generated=$script:goodYaml.Replace('direct-nameserver: []','direct-nameserver: false')
    Assert (((Get-FlClashCheck).Checks|Where-Object Name -eq 'DNS 上游配置').Blocking) 'Boolean direct DNS was accepted as a list'
}
Test-Case 'Read-only SQLite preserves exact 64-bit profile IDs and file bytes' {
    if (-not ('FlClashProfile' -as [type])) {Add-Type -Path (Join-Path $package 'probe\FlClashProfile.cs')}
    $db=Join-Path $PSScriptRoot 'fixtures\flclash-profiles.sqlite'
    $before=(Get-FileHash -LiteralPath $db).Hash
    $bound=[FlClashProfile]::Read($db,363580556476157952)
    Assert (($bound -join '|') -eq 'script|368065208121298944|1') 'Exact current profile lost'
    $missing=[FlClashProfile]::Read($db,2)
    Assert ($missing[0] -eq 'script' -and -not $missing[1]) 'Null binding misread'
    $orphan=[FlClashProfile]::Read($db,3)
    Assert ($orphan[2] -eq '0') 'Orphan binding was accepted'
    Expect-Error {[FlClashProfile]::Read($db,99)}
    $absent=Join-Path $WorkRoot 'must-not-create.sqlite'
    Expect-Error {[FlClashProfile]::Read($absent,1)}
    Assert (-not (Test-Path -LiteralPath $absent)) 'Read created a database'
    Assert ((Get-FileHash -LiteralPath $db).Hash -eq $before) 'Read mutated database'
}
Test-Case 'DNS failure stays visible and skips invalid probes without locking explicit launch' {
    $script:snapshot=New-FixtureSnapshot
    $snapshot.Generated=$snapshot.Generated.Replace('  strict-route: true','  strict-route: false')
    $snapshot.Patch.'tun-override'.'strict-route'=$false
    function Get-ClaudeInstall {[pscustomobject]@{Kind='fixture';Exe='fixture'}}
    function Get-ProtectionHealth {[pscustomobject]@{Core=$true;Tun=$true;Proxy=$true;Healthy=$true;Adapter='fixture'}}
    function Get-LocalConfigurationChecks {@()}
    function Get-IPv6LocalCheck {New-Check IPv6 info fixture}
    function Get-LaunchNetworkEvidence {throw 'EXTERNAL REQUEST WAS CALLED'}
    function Start-Guard {}
    $script:desktopStarted=$false
    function Start-Desktop {$script:desktopStarted=$true}
    $r=Get-EnvironmentCheck $WorkRoot
    Assert ($r.Ready -and ($r.Checks|Where-Object Name -eq '严格路由').Blocking) 'DNS warning was hidden or locked launch'
    Start-ProtectedClaude $WorkRoot | Out-Null
    Assert $script:desktopStarted 'Network warning prevented explicit launch'
}
Test-Case 'FlClash history is distinct, exportable and credential-free' {
    $script:snapshot=New-FixtureSnapshot
    $result=Get-FlClashCheck
    Save-DiagnosticReport $WorkRoot $result FlClash | Out-Null
    $record=@(Get-DiagnosticReports $WorkRoot|Where-Object Kind -eq 'FlClash')[0].Report
    Assert ($record.Kind -eq 'FlClash' -and $record.Checks.Count -gt 5) 'FlClash record was lost or mixed with Network'
    Assert ((ConvertTo-DiagnosticMarkdown $record) -notmatch 'private-node|do-not-report-password') 'Export exposed config'
}
Test-Case 'Chrome pages keep their destinations and reject unsupported requests' {
    $script:opened=@()
    function Test-Path {return $true}
    function Start-Process($FilePath,$ArgumentList) {$script:opened+=@([pscustomobject]@{File=$FilePath;Url=$ArgumentList})}
    Expect-Error {Open-DnsTestPage IPCheck}
    Open-DnsTestPage BrowserLeaks
    Assert ($script:opened.Count -eq 1 -and $script:opened[0].File -like '*chrome.exe') 'BrowserLeaks used another executable'
    Assert ($script:opened[0].Url -eq 'https://browserleaks.com/dns') 'Browser URL changed'
    foreach ($page in @('Languages','Fonts','IpPure')) {Open-ChromePage $page}
    Assert (($script:opened.Url -join '|') -eq 'https://browserleaks.com/dns|chrome://settings/languages|chrome://settings/fonts|https://ippure.com/claude') 'Chrome settings or retest destination changed'
    Assert (@($script:opened | Where-Object File -notlike '*chrome.exe').Count -eq 0) 'A Chrome page used another browser'
    Expect-Error {Open-ChromePage 'https://example.invalid'}
    Assert ($script:opened.Count -eq 4) 'Unsupported destination started a process'
    function Test-Path {return $false}
    foreach ($page in @('BrowserLeaks','Languages','Fonts','IpPure')) {Expect-Error {Open-ChromePage $page}}
    Assert ($script:opened.Count -eq 4) 'Missing Chrome silently used a fallback'
}
$results|ConvertTo-Json -Depth 5
if (@($results|Where-Object Status -eq 'FAIL').Count) {exit 1}
