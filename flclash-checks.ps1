function Read-FlClashGeneratedField([string]$Text,[string]$Section,[string]$Key) {
    # Read the generated block format, not subscription YAML. Unknown syntax must never produce a pass.
    $lines=@($Text -split '\r?\n')
    $heads=@(for ($i=0;$i -lt $lines.Count;$i++) {if ($lines[$i] -match ('^'+[regex]::Escape($Section)+':(?:\s|$)')) {$i}})
    if ($heads.Count -ne 1 -or $lines[$heads[0]] -notmatch ('^'+[regex]::Escape($Section)+':\s*(?:#.*)?$')) {throw '生成配置的区块格式无法核验。'}
    $body=New-Object System.Collections.Generic.List[string]
    for ($i=$heads[0]+1;$i -lt $lines.Count;$i++) {
        if ($lines[$i] -match '^\S' -and $lines[$i] -notmatch '^#') {break}
        if ($lines[$i] -notmatch '^\s*(?:#.*)?$') {$body.Add($lines[$i])}
    }
    if (-not $body.Count -or $body[0] -notmatch '^( +)[a-zA-Z][\w-]*:') {throw '生成配置的缩进无法核验。'}
    $indent=$Matches[1].Length
    $prefix='^ {'+$indent+'}'
    if (@($body | Where-Object {$_ -match '^\s*<<:' -or $_ -match '^\t'}).Count) {throw '生成配置含不支持的合并或缩进。'}
    $entries=@(for ($i=0;$i -lt $body.Count;$i++) {if ($body[$i] -match ($prefix+[regex]::Escape($Key)+':(?:\s|$)')) {$i}})
    if (-not $entries.Count) {return $null}
    if ($entries.Count -ne 1) {throw '生成配置含重复字段，无法确认实际值。'}
    $index=$entries[0]
    $value=($body[$index] -replace ($prefix+[regex]::Escape($Key)+':\s*'),'')
    $value=($value -replace '\s+#.*$','').Trim()
    if ($value -in @('true','false','null','~','[]')) {return $value}
    $values=New-Object System.Collections.Generic.List[string]
    if ($value.StartsWith('[') -and $value.EndsWith(']')) {
        foreach ($item in ($value.Substring(1,$value.Length-2) -split ',')) {$values.Add($item.Trim())}
    } elseif ($value) {throw '生成配置字段类型无法核验。'}
    else {
        for ($i=$index+1;$i -lt $body.Count;$i++) {
            if ($body[$i] -match ($prefix+'\S') -and $body[$i] -notmatch ($prefix+'- ')) {break}
            if ($body[$i] -notmatch '^ +-[ ]+(.+)$') {throw '生成配置列表格式无法核验。'}
            $values.Add(($Matches[1] -replace '\s+#.*$','').Trim())
        }
    }
    if (-not $values.Count) {throw '生成配置列表为空或不完整。'}
    $plain=@(foreach ($item in $values) {
        $clean=$item; $quoted=$false
        if ($clean -match '^"[^"\\]*"$|^''[^'']*''$') {$clean=$clean.Substring(1,$clean.Length-2); $quoted=$true}
        # After "#" Mihomo names the proxy group that carries the query. Group names are free text (Chinese, emoji,
        # spaces); only the server address before it must stay plain.
        $split=$clean.IndexOf('#')
        $address=if ($split -ge 0) {$clean.Substring(0,$split)} else {$clean}
        $group=if ($split -ge 0) {$clean.Substring($split+1)} else {$null}
        if ($address -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.:/_?&=%+@;~!()\[\]-]*$') {throw '生成配置列表含无法核验的内容。'}
        # Unquoted, ": " would make YAML read the item as a mapping rather than a server.
        if ($null -ne $group -and ($group -notmatch '^[^\p{Cc}"'']+$' -or (-not $quoted -and $group -match ':(\s|$)'))) {throw '生成配置列表含无法核验的内容。'}
        $clean
    })
    return $plain
}

function Get-FlClashSnapshot {
    $core=@(Get-Process -Name FlClashCore -ErrorAction SilentlyContinue)
    if (-not $core.Count) {return [pscustomobject]@{Active=$false}}
    # The elevated core's Path is unavailable to a normal launcher; version belongs to the desktop app.
    $paths=@(Get-Process -Name FlClash -ErrorAction SilentlyContinue | ForEach-Object Path | Where-Object {$_} | Select-Object -Unique)
    $version=if ($paths.Count -eq 1) {(Get-Item -LiteralPath $paths[0]).VersionInfo.ProductVersion} else {'未取得（主界面进程不可读）'}
    $directory=Join-Path $env:APPDATA 'com.follow\clash'
    $preferences=Get-Content -LiteralPath (Join-Path $directory 'shared_preferences.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $config=$preferences.'flutter.config' | ConvertFrom-Json
    if (-not $config.patchClashConfig -or -not $config.currentProfileId) {throw 'FlClash 设置结构或当前配置标识无法核验。'}
    $profile=$null
    try {
        if (-not ('FlClashProfile' -as [type])) {Add-Type -Path (Join-Path $PSScriptRoot 'probe\FlClashProfile.cs')}
        $profile=[FlClashProfile]::Read((Join-Path $directory 'database.sqlite'),[long]$config.currentProfileId)
    } catch { $profile=$null }
    [pscustomobject]@{
        Active=$true;Version=$version;Patch=$config.patchClashConfig;Profile=$profile
        ScriptExists=($profile -and $profile[1] -match '^\d+$' -and (Test-Path -LiteralPath (Join-Path $directory ('scripts\'+$profile[1]+'.js'))))
        Generated=[IO.File]::ReadAllText((Join-Path $directory 'config.yaml'))
    }
}

function Get-FlClashCheck {
    $rows=New-Object System.Collections.Generic.List[object]
    $source='FlClash 本机设置 / 生成配置；未执行浏览器泄露测试'
    try {$snapshot=Get-FlClashSnapshot} catch {
        $rows.Add((New-Check 'FlClash 配置读取' 'unknown' '当前配置不可读或结构不支持，无法核验 DNS 防护。请确认 FlClash 已启动，并检查网络页的修复步骤。' $true))
        return New-InsightsResult 'FlClash' $rows.ToArray()
    }
    if (-not $snapshot.Active) {
        $rows.Add((New-Check 'FlClash 配置检查' 'unknown' '未检测到 FlClashCore。本模块未核验其他客户端；代理基础检查仍独立生效。'))
        return New-InsightsResult 'FlClash' $rows.ToArray()
    }
    $patch=$snapshot.Patch
    $rows.Add((New-InsightRow 'FlClash 版本与覆写机制' 'info' ('当前 '+(Get-ProbeText $snapshot.Version 50)+'；0.9.0 起 DNS 按选中键全局覆写，0.9.1 起桌面 TUN 同样按键覆写。') 'FlClash / DNS' 'https://github.com/chen08209/FlClash/releases/tag/v0.9.1' '显示的保存值、选中的覆写键、生成配置需要一起核对。' '升级或更换订阅后重新检查；不要直接修改会被重新生成的 config.yaml。'))
    $profile=$snapshot.Profile
    if (-not $profile) {$rows.Add((New-Check '当前配置的脚本绑定' 'unknown' '配置数据库暂不可读或格式不支持，未确认脚本绑定。' $true))}
    elseif ($profile[0] -eq 'script') {
        $bound=$profile[1] -match '^\d+$' -and $profile[2] -eq '1' -and $snapshot.ScriptExists
        $rows.Add((New-Check '当前配置的脚本绑定' $(if ($bound) {'ok'} else {'fail'}) $(if ($bound) {'已绑定且脚本文件存在；具体 DNS 仍以下方生成配置为准。'} else {'当前选择脚本模式，但脚本未绑定或已丢失。进入配置 → 当前订阅 → 扩展 → 脚本，重新选择已有脚本。'}) (-not $bound)))
    } else {$rows.Add((New-Check '当前配置的脚本绑定' 'info' '当前使用非脚本模式。若依赖固定 Claude 出口脚本，请在当前订阅的扩展设置中确认。'))}
    foreach ($entry in @(@('tun','enable','TUN 配置'),@('tun','strict-route','严格路由'),@('dns','enable','DNS 接管'))) {
        try {
            $value=Read-FlClashGeneratedField $snapshot.Generated $entry[0] $entry[1]
            if ($null -ne $value -and $value -notin @('true','false')) {throw 'Unexpected boolean'}
            $enabled=$value -eq 'true'
            $detail=if ($enabled) {'生成配置已启用；实际流量仍需复测。'} else {'生成配置未启用。请在 FlClash 工具 → 进阶配置中检查对应选项。'}
            if ($entry[1] -eq 'strict-route') {
                $selected='strict-route' -in @($patch.'tun-override-keys')
                if ($selected -and $patch.'tun-override'.'strict-route' -is [bool] -and ($patch.'tun-override'.'strict-route' -ne $enabled)) {throw 'Override mismatch'}
                $detail+=if ($selected) {' 严格路由已选为覆写项。'} else {' 当前随订阅配置；要跨订阅保留，请添加“严格路由”覆写并开启。'}
            }
            $rows.Add((New-Check $entry[2] $(if ($enabled) {'ok'} else {'fail'}) $detail (-not $enabled)))
        } catch {$rows.Add((New-Check $entry[2] 'unknown' '保存值与生成配置不一致，或字段格式无法核验。请等待 FlClash 应用设置后重新检查。' $true))}
    }
    try {
        $hijack=@(Read-FlClashGeneratedField $snapshot.Generated 'tun' 'dns-hijack')
        $udp=@($hijack | Where-Object {$_ -in @('any:53','udp://any:53','0.0.0.0:53','udp://0.0.0.0:53')}).Count -gt 0
        $tcp=@($hijack | Where-Object {$_ -in @('tcp://any:53','tcp://0.0.0.0:53')}).Count -gt 0
        $rows.Add((New-InsightRow 'DNS 劫持覆盖' $(if ($udp -and $tcp) {'ok'} else {'warn'}) ('UDP：'+$(if ($udp) {'已覆盖'} else {'未显式覆盖'})+'；TCP：'+$(if ($tcp) {'已覆盖'} else {'未显式覆盖'})+'。any:53 默认只表示 UDP。') 'FlClash / DNS' 'https://wiki.metacubex.one/config/inbound/tun/' '根据生成配置识别全目标 53 端口规则，未发送旁路探测。' '严格路由和 DNS 劫持作用不同；TCP 未显式覆盖时需单独复测。严格路由不等于退出 FlClash 后仍生效的永久断网保护。'))
    } catch {$rows.Add((New-Check 'DNS 劫持覆盖' 'unknown' '无法读取 DNS 劫持列表，UDP / TCP 覆盖未验证。'))}
    try {
        $main=@(Read-FlClashGeneratedField $snapshot.Generated 'dns' 'nameserver')
        if (-not $main.Count -or $main[0] -in @($null,'[]','null','~','true','false')) {throw 'No main DNS'}
        $direct=@(Read-FlClashGeneratedField $snapshot.Generated 'dns' 'direct-nameserver')
        if ($direct.Count -eq 1 -and $direct[0] -in @('true','false')) {throw 'Invalid direct DNS list'}
        $inherits=-not $direct.Count -or ($direct.Count -eq 1 -and $direct[0] -in @($null,'[]','null','~'))
        $domestic=@($direct | Where-Object {$_ -match '^(?:(?:https|tls|quic)://)?(?:dns\.alidns\.com|doh\.pub|dns\.pub|223\.5\.5\.5|223\.6\.6\.6|119\.29\.29\.29|114\.114\.114\.114)(?:[/:#?]|$)'}).Count -gt 0
        $detail=if ($inherits) {'直连专用 DNS 为空，继承主解析流程；本次发现的独立直连解析缺口已避开。'} elseif ($domestic) {'直连专用 DNS 含已知国内公共解析器，可能重现本次泄露。进入 DNS → 添加 Direct Nameserver 覆写 → 清空列表，再用浏览器复测。'} else {'直连流量使用独立 DNS，上游与主 DNS 可能不同；请核对是否符合预期。'}
        $rows.Add((New-InsightRow '直连专用 DNS' $(if ($inherits) {'ok'} else {'warn'}) $detail 'FlClash / DNS' 'https://wiki.metacubex.one/config/dns/' '空列表表示继承，不表示停止解析。国内网站策略与节点域名引导解析需要分别判断。' '不要将 bootstrap / 节点解析强行改为依赖同一个尚未建立的代理，以免循环依赖。'))
        $override=@($patch.'dns-override-keys')
        $overridesMain='nameserver' -in $override -or 'fallback' -in $override
        $rows.Add((New-Check '主 DNS 与覆写顺序' $(if ($overridesMain) {'warn'} else {'info'}) ('生成配置主 DNS 共 '+$main.Count+' 项；'+$(if ($overridesMain) {'Nameserver 或 Fallback 已选为全局覆写，会覆盖订阅 / 脚本同名字段，需确认是否有意设置。'} else {'Nameserver / Fallback 未选为全局覆写，使用订阅或脚本结果。'}))))
    } catch {$rows.Add((New-Check 'DNS 上游配置' 'unknown' '生成配置中的主 DNS / 直连 DNS 无法可靠解析，当前未核验。' $true))}
    $rows.Add((New-InsightRow '浏览器复测与证据范围' 'info' '本机配置检查不代表 DNS 已无泄露。IPCheck 测量助手内嵌浏览器；BrowserLeaks 测量 Chrome，两者的浏览器 DNS 设置可能不同。' 'FlClash / DNS' $source '解析器数量多不等于泄露；ECS 表示子网披露，但不能直接认定是本机真实网段。' '出现意外中国解析器或 ECS 时核对路径；单站通过、无响应、重启前的结果都不能代替当前验证。'))
    New-InsightsResult 'FlClash' $rows.ToArray()
}

function Open-ChromePage([ValidateSet('BrowserLeaks','Languages','Fonts','IpPure')][string]$Page) {
    $url=switch ($Page) {
        'BrowserLeaks' {'https://browserleaks.com/dns'}
        'Languages' {'chrome://settings/languages'}
        'Fonts' {'chrome://settings/fonts'}
        'IpPure' {'https://ippure.com/claude'}
    }
    $chrome=@("$env:ProgramFiles\Google\Chrome\Application\chrome.exe","${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe","$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe" | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1)
    if (-not $chrome.Count) {throw '未找到 Chrome，请手动在 Chrome 打开 '+$url}
    Start-Process -FilePath $chrome[0] -ArgumentList $url
}

function Open-DnsTestPage([ValidateSet('IPCheck','BrowserLeaks')][string]$Provider, $Owner, [string]$StateRoot) {
    if ($Provider -eq 'IPCheck') {
        if (-not $Owner -or -not $StateRoot) {throw '请从助手窗口打开 IPCheck 深度 DNS。'}
        if (-not ('IpCheckWindow' -as [type])) {
            Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Drawing
            $sdk=Join-Path $PSScriptRoot 'lib\WebView2'
            $core=Join-Path $sdk 'Microsoft.Web.WebView2.Core.dll'
            $wpf=Join-Path $sdk 'Microsoft.Web.WebView2.Wpf.dll'
            Add-Type -Path $core,$wpf
            [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::SetLoaderDllFolderPath($sdk)
            $references=@($core,$wpf,'System.dll','System.Core.dll','System.Drawing.dll','System.Xaml.dll',
                [Windows.Window].Assembly.Location,[Windows.Media.Visual].Assembly.Location,[Windows.Threading.Dispatcher].Assembly.Location)
            Add-Type -Path (Join-Path $PSScriptRoot 'launcher\IpCheckWindow.cs') -ReferencedAssemblies $references
        }
        return [IpCheckWindow]::Open($Owner,$StateRoot,$PSScriptRoot)
    }
    Open-ChromePage BrowserLeaks
}
