# Optional diagnostic scores never control the launch gate; ASN policy lives in network-probes.ps1.
function Get-ProbeText($Value, [int]$Limit=180) {
    if ($Value -isnot [string]) { return '' }
    $text=($Value -replace '[\x00-\x1f\x7f]',' ').Trim()
    # Provider metadata sometimes embeds addresses. Keep reports suitable for sharing.
    $text=$text -replace '(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?:/\d{1,2})?', '[IP 已隐藏]'
    $text=[regex]::Replace($text,'(?i)(?<![\w:])(?:[a-f0-9]{0,4}:){2,}[a-f0-9:.]*(?:/\d{1,3})?', [Text.RegularExpressions.MatchEvaluator]{param($m)
        $address=$null
        if ([Net.IPAddress]::TryParse(($m.Value -split '/')[0],[ref]$address)) {return '[IPv6 已隐藏]'}
        $m.Value
    })
    $text.Substring(0,[Math]::Min($Limit,$text.Length))
}

function Get-LocalConfigurationChecks($Settings) {
    foreach ($scope in @('Process','User','Machine')) {
        $issues=New-Object System.Collections.Generic.List[string]
        foreach ($name in @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY')) {
            $value=[Environment]::GetEnvironmentVariable($name,$scope)
            if (-not $value) { continue }
            $uri=$null
            if (-not [uri]::TryCreate($value,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('http','https') -or -not $uri.IsLoopback -or $uri.Port -ne $Settings.ProxyPort) {
                $issues.Add($name+' 指向其他路径或协议，需核对使用它的程序。')
            }
        }
        $bypass=[Environment]::GetEnvironmentVariable('NO_PROXY',$scope)
        if ($bypass -match '\*|claude|anthropic') { $issues.Add('NO_PROXY 含通配符或 Claude / Anthropic 域名候选，可能绕开显式代理。') }
        if ([Environment]::GetEnvironmentVariable('NODE_TLS_REJECT_UNAUTHORIZED',$scope) -eq '0') { $issues.Add('NODE_TLS_REJECT_UNAUTHORIZED=0 会关闭使用它的 Node 程序的证书验证。') }
        New-Check ('启动环境 · '+$scope) $(if ($issues.Count) {'warn'} else {'info'}) $(if ($issues.Count) {$issues -join ' '} else {'未发现已检查环境变量的路径冲突或禁用证书验证设置。'})
    }
    New-Check '配置核验范围' 'info' '环境变量仅报告问题类别，不输出原值；未读取账号凭据。Claude Code 的用户、项目与受管设置需在对应会话核对，不能由桌面启动助手代替。'
}

function New-InsightRow($Name,$State,$Detail,$Group,$Source,$Evidence,$Advice) {
    $row=New-Check $Name $State $Detail
    $row | Add-Member -NotePropertyMembers @{Group=$Group;Source=$Source;Evidence=$Evidence;Advice=$Advice}
    $row
}

function Read-TraceResponse([string]$Body) {
    $fields=@{}
    foreach ($line in ($Body -split '\r?\n')) {
        $parts=$line -split '=',2
        if ($parts.Count -eq 2) { $fields[$parts[0]]=$parts[1].Trim() }
    }
    if (-not $fields['ip'] -or $fields['loc'] -cnotmatch '^[A-Z]{2}$') { throw 'Trace 响应缺少有效的 IP / 地区，可能是验证页面。' }
    $identity=Get-AddressIdentity $fields['ip']
    if (-not (Test-PublicAddress $identity.Address)) { throw 'Trace 未返回公网出口。' }
    $transport=@(foreach ($key in @('colo','http','tls','kex','warp','gateway')) {
        if ($fields[$key]) { $key+' = '+(Get-ProbeText $fields[$key] 80) }
    }) -join '；'
    [pscustomobject]@{Identity=$identity;Country=$fields['loc'];Transport=$transport}
}

function Read-ProbeJson([string]$Body) {
    try { $Body | ConvertFrom-Json -ErrorAction Stop }
    catch { throw '服务响应不是有效 JSON，可能遇到验证页面或接口变更。' }
}

function Read-IpPureResponse([string]$Body) {
    $data=Read-ProbeJson $Body
    if (-not $data.ip -or $data.countryCode -cnotmatch '^[A-Z]{2}$') { throw 'IPPure 响应缺少有效的 IP / 地区。' }
    $identity=Get-AddressIdentity $data.ip
    if (-not (Test-PublicAddress $identity.Address)) { throw 'IPPure 未返回公网出口。' }
    $score=$null
    if ($null -ne $data.fraudScore) {
        if ($data.fraudScore -isnot [ValueType] -or $data.fraudScore -is [bool] -or $data.fraudScore -lt 0 -or $data.fraudScore -gt 100 -or [double]::IsNaN([double]$data.fraudScore)) { throw 'IPPure 评分字段格式已变化。' }
        $score=[double]$data.fraudScore
    }
    $residential=if ($data.isResidential -is [bool]) { if ($data.isResidential) {'住宅'} else {'非住宅'} } else {'未提供'}
    $broadcast=if ($data.isBroadcast -is [bool]) { if ($data.isBroadcast) {'广播 IP 标签 isBroadcast：是'} else {'广播 IP 标签 isBroadcast：否'} } else {'广播 IP 标签 isBroadcast：未提供'}
    $asn=if ([string]$data.asn -match '^\d+$') {'AS'+$data.asn} else {'ASN 未提供'}
    [pscustomobject]@{Identity=$identity;Country=$data.countryCode;Score=$score;Residential=$residential;Asn=$asn;Organization=(Get-ProbeText $data.asOrganization);Region=(Get-ProbeText $data.region);City=(Get-ProbeText $data.city);Broadcast=$broadcast}
}

function Read-DnsProbeResponse([ValidateSet('IP-API','Surfshark','Fastly','BrowserLeaks')][string]$Provider,[string]$Body) {
    $data=Read-ProbeJson $Body
    $values=@(); $ecs=$null; $ecsDetail='服务未提供 ECS 字段，无法判断客户端子网披露。'
    switch ($Provider) {
        'IP-API' {
            $ecs=$false; $ecsDetail='本次响应未返回 EDNS 客户端子网，不覆盖其他 DNS 查询。'
            $values=@([pscustomobject]@{IP=$data.dns.ip;Country='';Geo=$data.dns.geo;Org=''})
            if ($data.PSObject.Properties['edns']) {
                $ecs=[bool]$data.edns.ip
                $ecsDetail=if ($ecs) {'响应含 EDNS 客户端子网（已隐藏地址）。这可能透露一段地址范围，无法据此断定是本机公网地址。'} else {'本次响应未含 EDNS 客户端子网；不覆盖其他 DNS 查询。'}
                if ($ecs) {
                    $parts=([string]$data.edns.ip).Split('/')
                    if (-not (Test-PublicAddress $parts[0])) { throw 'ECS 字段不是有效的公网子网。' }
                    if ($parts.Count -gt 1) {
                        $max=if ((Get-AddressIdentity $parts[0]).Family -eq 'IPv4') {32} else {128}
                        if ($parts.Count -ne 2 -or $parts[1] -notmatch '^\d+$' -or [int]$parts[1] -gt $max) { throw 'ECS 子网长度无效。' }
                        $ecsDetail+=' 前缀长度 /'+$parts[1]+'。'
                    }
                }
            }
        }
        'Surfshark' { $values=@($data.PSObject.Properties | Where-Object {$_.Value.IP} | ForEach-Object { [pscustomobject]@{IP=$_.Value.IP;Country=$_.Value.CountryCode;Geo=([string]$_.Value.Country+' '+[string]$_.Value.City);Org=$_.Value.ISP} }) }
        'Fastly' { $values=@([pscustomobject]@{IP=$data.dns_resolver_info.ip;Country=$data.dns_resolver_info.cc;Geo='';Org=$data.dns_resolver_info.as_name}) }
        'BrowserLeaks' { $values=@($data.PSObject.Properties | Where-Object {$_.Value -is [array] -and $_.Value.Count -ge 3} | ForEach-Object { [pscustomobject]@{IP=$_.Name;Country=$_.Value[0];Geo=$_.Value[1];Org=$_.Value[2]} }) }
    }
    if (-not $values.Count) { throw 'DNS 服务未返回解析器地址。' }
    $seen=@{}; $resolvers=@(foreach ($value in $values) {
        if (-not $value.IP -or -not (Test-PublicAddress $value.IP)) { throw 'DNS 服务返回了无效的解析器地址。' }
        $identity=Get-AddressIdentity $value.IP
        if (-not $seen.ContainsKey($identity.Hash)) {
            $seen[$identity.Hash]=$true
            [pscustomobject]@{Address=$identity.Address;Hash=$identity.Hash;Family=$identity.Family;Country=$(if ([string]$value.Country -match '^[a-z]{2}$') {([string]$value.Country).ToUpperInvariant()} else {''});Geo=(Get-ProbeText $value.Geo);Organization=(Get-ProbeText $value.Org)}
        }
    })
    [pscustomobject]@{Resolvers=$resolvers;Hashes=@($resolvers | ForEach-Object Hash);Ecs=$ecs;EcsDetail=$ecsDetail}
}

function New-InsightsResult([string]$Kind,$Rows,$Observations=@()) {
    [pscustomobject]@{Kind=$Kind;CheckedAt=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss');Checks=@($Rows);Observations=@($Observations);Message='结果只代表本次探测；没有修改网络或 Claude 会话。'}
}

function Get-ServiceStatusRows([string]$Body) {
    $data=Read-ProbeJson $Body
    $source='https://status.claude.com/api/v2/summary.json'
    $states=@{operational='正常';degraded_performance='性能下降';partial_outage='部分故障';major_outage='重大故障';under_maintenance='维护中'}
    if ($data.status.indicator -notin @('none','minor','major','critical','maintenance') -or $data.components -isnot [array] -or -not $data.components.Count) { throw '官方状态响应缺少状态或组件。' }
    $updated=Get-ProbeText $data.page.updated_at
    $rows=New-Object System.Collections.Generic.List[object]
    $summary=@{none='官方报告服务总体正常';minor='官方报告部分服务异常';major='官方报告重大服务异常';critical='官方报告严重服务故障';maintenance='官方报告正在维护'}
    $rows.Add((New-InsightRow 'Claude 官方概况' $(if ($data.status.indicator -eq 'none') {'ok'} else {'warn'}) $summary[[string]$data.status.indicator] '官方服务状态' $source ('状态页更新时间：'+$updated+'；原文：'+(Get-ProbeText $data.status.description)) '状态页有更新延迟；官方正常不代表每个账号或请求都正常。'))
    foreach ($component in @($data.components)) {
        $known=$states.ContainsKey([string]$component.status)
        $state=if (-not $known) {'unknown'} elseif ($component.status -eq 'operational') {'ok'} else {'warn'}
        $label=if ($known) {$states[[string]$component.status]} else {'未识别状态'}
        $rows.Add((New-InsightRow ('服务 · '+(Get-ProbeText $component.name 70)) $state $label '官方服务状态' $source ('官方状态代码：'+(Get-ProbeText $component.status)+'；'+$updated) '服务端异常时可查看官方事件进展；本工具不重启你的连接。'))
    }
    foreach ($incident in @($data.incidents | Where-Object {$_ -and $_.status -notin @('resolved','postmortem')})) {
        $rows.Add((New-InsightRow ('事件 · '+(Get-ProbeText $incident.name 100)) 'warn' (Get-ProbeText $incident.status) '官方服务状态' $source ('更新：'+(Get-ProbeText $incident.updated_at)) '官方事件可能影响部分功能，请以状态页后续更新为准。'))
    }
    $rows.ToArray()
}

function Get-NetworkInsights($Root) {
    $settings=Get-Settings $Root
    $rows=New-Object System.Collections.Generic.List[object]
    $observations=New-Object System.Collections.Generic.List[object]
    $live=New-Object System.Collections.Generic.List[object]
    if (-not (Get-ProtectionHealth $settings).Healthy) {
        $rows.Add((New-Check '网络前提' 'unknown' '代理内核、TUN 或监听端口未就绪；未发送外部请求。请先检查环境。'))
        return New-InsightsResult 'Network' $rows.ToArray()
    }
    $references=@{}
    foreach ($family in @('IPv4','IPv6')) {
        $name='ipify '+$family+' 基准'
        try {
            $reference=Invoke-AddressProbe $settings $true ($family -eq 'IPv6')
            $references[$family]=$reference
            $rows.Add((New-InsightRow $name 'ok' ('出口摘要 '+$reference.Hash.Substring(0,12)) '出口与路由' 'https://www.ipify.org/' '显式 HTTP 代理。IPv6 指代理远端访问 IPv6 目标的能力，不代表本机 IPv6 已启用。' '只将同地址族的结果互相比较。'))
            $observations.Add([pscustomobject]@{Type='Egress';Provider='ipify';Route='Proxy';Family=$family;Hash=$reference.Hash;Country=''})
        } catch { $rows.Add((New-InsightRow $name 'unknown' $_.Exception.Message '出口与路由' 'https://www.ipify.org/' '未取得此地址族对照。' 'IPv6 不可达时保留未验证状态，不改动 IPv6 设置。')) }
    }
    $targets=@(@{Host='4.ipcheck.ing';Routes=@('Proxy')},@{Host='6.ipcheck.ing';Routes=@('Proxy')})+@(Get-ClaudeDomains | ForEach-Object {@{Host=$_;Routes=@('Proxy','System')}})
    foreach ($target in $targets) {
        $sameTarget=@{}
        foreach ($route in $target.Routes) {
            $routeName=if ($route -eq 'Proxy') {'显式代理'} else {'系统 / TUN'}
            $name=$target.Host+' · '+$routeName; $endpoint='https://'+$target.Host+'/cdn-cgi/trace'
            try {
                $response=Invoke-ProbeHttp $settings $endpoint $route
                $trace=Read-TraceResponse $response.Body
                if (($target.Host -eq '4.ipcheck.ing' -and $trace.Identity.Family -ne 'IPv4') -or ($target.Host -eq '6.ipcheck.ing' -and $trace.Identity.Family -ne 'IPv6')) { throw 'IPCheck 返回的地址族与目标不一致。' }
                $compare=if ($route -eq 'System') {$sameTarget} else {$references}
                $row=Compare-ProbeAddresses $name @($trace.Identity.Address) $compare
                if ($route -eq 'Proxy') { $sameTarget[$trace.Identity.Family]=$trace.Identity }
                $detail=$trace.Identity.Family+' · '+$trace.Country+' · '+$response.Milliseconds+' ms · 摘要 '+$trace.Identity.Hash.Substring(0,12)+"`n"+$row.Detail
                $evidence='HTTP '+$response.Status+'；'+$trace.Transport+'。TLS / HTTP 来自本工具 curl 请求；不是 Claude 的 JA3 / JA4。'
                $rows.Add((New-InsightRow $name $row.State $detail '出口与路由' $endpoint $evidence '出口差异需核对域名分流或负载均衡；独立 Trace 不代表已登录会话。请求耗时不是网速。'))
                $live.Add([pscustomobject]@{Type='Egress';Provider=$target.Host;Route=$route;Address=$trace.Identity.Address;Hash=$trace.Identity.Hash;Family=$trace.Identity.Family;Country=$trace.Country;Milliseconds=$response.Milliseconds;State=$row.State})
                $observations.Add([pscustomobject]@{Type='Egress';Provider=$target.Host;Route=$route;Family=$trace.Identity.Family;Hash=$trace.Identity.Hash;Country=$trace.Country;Milliseconds=$response.Milliseconds;Transport=$trace.Transport})
            } catch { $rows.Add((New-InsightRow $name 'unknown' $_.Exception.Message '出口与路由' $endpoint '请求失败或响应不可验证；其他路径仍分别检测。' '保留现有连接，可稍后手动复测；不将 403 或验证码当作封号。')) }
        }
    }
    try {
        $source='https://my.ippure.com/v1/info'
        $pure=Read-IpPureResponse (Invoke-ProbeHttp $settings $source 'Proxy').Body
        $comparison=Compare-ProbeAddresses 'IPPure 出口核对' @($pure.Identity.Address) $references
        $rows.Add((New-InsightRow $comparison.Name $comparison.State $comparison.Detail '网络归属与信誉' $source ('出口摘要 '+$pure.Identity.Hash.Substring(0,12)) '数据库结论只适用于该次请求的出口。'))
        $rows.Add((New-InsightRow 'IPPure 网络归属' 'info' ($pure.Country+' · '+$pure.Region+' · '+$pure.City+"`n"+$pure.Asn+' · '+$pure.Organization) '网络归属与信誉' $source ($pure.Residential+'；'+$pure.Broadcast) '位置是 IP 数据库估计，不是设备 GPS；住宅分类不保证未被用作代理。'))
        $rows.Add((New-InsightRow 'IPPure 信誉评分' $(if ($null -eq $pure.Score) {'unknown'} else {'info'}) $(if ($null -eq $pure.Score) {'接口未提供评分。'} else {'fraudScore = '+$pure.Score+' / 100'}) '网络归属与信誉' $source '第三方 IP 数据库评分；不同服务的分数不能混算。' '不是 Claude 风控分或封号概率，不决定能否启动。'))
        $observations.Add([pscustomobject]@{Type='Egress';Provider='IPPure';Route='Proxy';Family=$pure.Identity.Family;Hash=$pure.Identity.Hash;Country=$pure.Country;Asn=$pure.Asn;Organization=$pure.Organization;Score=$pure.Score})
    } catch { $rows.Add((New-InsightRow 'IPPure 数据服务' 'unknown' $_.Exception.Message '网络归属与信誉' 'https://my.ippure.com/v1/info' '没有可验证的第三方数据。' '缺失不按零风险处理。')) }
    $dnsResults=@{}
    foreach ($provider in @('IP-API','Surfshark','Fastly','BrowserLeaks')) {
        foreach ($route in @('System','Proxy')) {
            $routeName=if ($route -eq 'Proxy') {'显式代理'} else {'系统 / TUN'}
            $name=$provider+' · '+$routeName
            $nonce=[guid]::NewGuid().ToString('N')
            $endpoint=switch ($provider) {
                'IP-API' {'https://'+$nonce+'.edns.ip-api.com/json'}
                'Surfshark' {'https://'+$nonce.Substring(0,13)+'.ipv4.surfsharkdns.com/'}
                'Fastly' {'https://'+$nonce+'.u.fastly-analytics.com/debug_resolver'}
                'BrowserLeaks' {'https://'+$nonce.Substring(0,12)+'.dns4.browserleaks.net/'}
            }
            $source=([uri]$endpoint).DnsSafeHost -replace '^[^.]+\.',''
            try {
                $dns=Read-DnsProbeResponse $provider (Invoke-ProbeHttp $settings $endpoint $route).Body
                $dnsResults[$provider+'/'+$route]=$dns
                $evidence=@(foreach ($resolver in $dns.Resolvers) {
                    $live.Add([pscustomobject]@{Type='DNS';Provider=$provider;Route=$route;Address=$resolver.Address;Hash=$resolver.Hash;Family=$resolver.Family;Country=$resolver.Country;Geo=$resolver.Geo;Organization=$resolver.Organization;Ecs=$dns.Ecs})
                    $observations.Add([pscustomobject]@{Type='DNS';Provider=$provider;Route=$route;Hash=$resolver.Hash;Family=$resolver.Family;Country=$resolver.Country;Geo=$resolver.Geo;Organization=$resolver.Organization;Ecs=$dns.Ecs})
                    $resolver.Family+' #'+$resolver.Hash.Substring(0,12)+' · '+$resolver.Country+' '+$resolver.Geo+' · '+$resolver.Organization
                }) -join "`n"
                $china=@($dns.Resolvers | Where-Object Country -eq 'CN').Count
                $rows.Add((New-InsightRow $name $(if ($dns.Ecs -or $china) {'warn'} else {'info'}) ('观察到 '+$dns.Resolvers.Count+' 个解析器；其中中国 '+$china+' 个。展开核对路径与 ECS。') 'DNS 解析路径' $source ($evidence+"`n"+$dns.EcsDetail) '意外中国解析器或 ECS 需要核对，不自动判定本机真实 IP 泄露。解析器数量少也不代表安全；请同时运行 Chrome 深度测试，单站结果不覆盖浏览器自有 DoH。'))
            } catch { $rows.Add((New-InsightRow $name 'unknown' $_.Exception.Message 'DNS 解析路径' $source '本次随机子域探测没有获得有效结果。' '接口限流、IPv6 不可达、验证页面均可能造成失败；不能因此宣称没有泄漏。')) }
        }
        $systemDns=$dnsResults[$provider+'/System']; $proxyDns=$dnsResults[$provider+'/Proxy']
        if ($systemDns -and $proxyDns) {
            $shared=@($systemDns.Hashes | Where-Object {$_ -in $proxyDns.Hashes}).Count
            $rows.Add((New-InsightRow ($provider+' 路径比较') 'info' ('两条路径共享 '+$shared+' 个解析器出口。') 'DNS 解析路径' $source '使用不同随机子域，分别触发系统 / TUN 与显式代理解析。' '解析器集群、缓存及地域调度都可能产生不同结果；差异本身不证明泄漏。'))
        }
    }
    $unique=@($observations | Where-Object Type -eq 'DNS' | Select-Object -ExpandProperty Hash -Unique).Count
    $rows.Add((New-InsightRow 'DNS 覆盖汇总' $(if ($dnsResults.Count -eq 8) {'info'} else {'unknown'}) ($dnsResults.Count.ToString()+' / 8 次探测获得结果；合并后 '+$unique+' 个解析器。') 'DNS 解析路径' 'IP-API / Surfshark / Fastly / BrowserLeaks' '4 个服务 × 2 条路径；没有启动浏览器 DNS、DNSSEC 权威测试或旁路抓包。' '位置只作为来源信息；需要核对时先查看各条路径，不自动更换 DNS。'))
    try {
        foreach ($row in @(Get-ServiceStatusRows (Invoke-ProbeHttp $settings 'https://status.claude.com/api/v2/summary.json' 'Proxy').Body)) { $rows.Add($row) }
    } catch { $rows.Add((New-InsightRow 'Claude 官方状态' 'unknown' $_.Exception.Message '官方服务状态' 'https://status.claude.com' '未能读取官方公开状态页。' '未知不代表服务正常或故障。')) }
    $rows.Add((New-InsightRow '检测边界' 'info' '匿名请求，不携带 Claude Cookie；时区和语言未采集。' '范围与解释' '本地实现 / 公开接口' '本次最多 18 个小型 HTTPS 请求，各自有超时，无自动重试；不测速、不切换节点、不模拟断线。未接入网站私有风控数据库、Turnstile、reCAPTCHA 或 Claude 实际 TLS 指纹。' '从单次证据判断具体路径；不据此推断账号限制状态。'))
    $result=New-InsightsResult 'Network' $rows.ToArray() $observations.ToArray()
    # Full addresses are for this window only; diagnostic persistence selects the redacted contract.
    $result | Add-Member -NotePropertyName LiveDetails -NotePropertyValue $live.ToArray()
    $result
}

function Get-FingerprintInsights($Root,[switch]$Remember) {
    $fingerprint=(Get-BrowserProbe -Mode Fingerprint -StunUrls @()).Fingerprint
    if (-not $fingerprint -or $fingerprint.Schema -ne 2) { throw '浏览器未返回当前版本的设备特征。' }
    $labels=[ordered]@{Browser='独立 Edge / UA';Platform='浏览器平台';ClientHints='UA Client Hints';Screen='屏幕与触摸';Hardware='硬件并行度与内存';WebGL='WebGL 渲染器';WebGLCapabilities='WebGL 能力';Fonts='可见字体样本';FontMetrics='文字测量摘要';Canvas='Canvas 绘图摘要';CanvasRepeat='Canvas 重复采样';Emoji='Emoji 渲染摘要';EmojiStyle='Emoji 像素特征';Audio='离线音频摘要';Storage='存储可用性';Privacy='Cookie 与 DNT';Plugins='插件与 MIME';Media='媒体编解码支持';Math='数学运算摘要';Automation='探测环境标记'}
    $hashes=[ordered]@{}; $rows=New-Object System.Collections.Generic.List[object]
    $baselinePath=Join-Path $Root 'fingerprint-baseline.json'; $baseline=$null
    if (Test-Path -LiteralPath $baselinePath) { $baseline=Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8 | ConvertFrom-Json }
    $changed=@(); $missing=@(); $observations=@(foreach ($key in $labels.Keys) {
        $value=[string]$fingerprint.$key; $state='info'; $comparison='尚无此版本基准'
        if ([string]::IsNullOrWhiteSpace($value)) {
            $state='unknown'; $missing+=$key; $comparison='未取得'
            $value='浏览器未提供；'+[string]$fingerprint.Errors.$key
        } else {
            $hashes[$key]=Get-TextHash $value
            if ($baseline -and $baseline.Schema -eq 2 -and $baseline.Hashes.$key) {
                if ($hashes[$key] -eq $baseline.Hashes.$key) {$comparison='与基准一致';$state='ok'} else {$comparison='相对基准变化';$state='warn';$changed+=$key}
            } elseif ($baseline) { $missing+=$key }
        }
        $group=if ($key -in @('WebGL','WebGLCapabilities','Fonts','FontMetrics','Canvas','CanvasRepeat','Emoji','EmojiStyle','Audio','Math')) {'渲染与计算'} else {'浏览器能力'}
        $short=if ($value.Length -gt 160) {$value.Substring(0,160)+'…'} else {$value}
        $evidence=$value+"`n基准："+$comparison
        if ($baseline) { $evidence+="`n基准采集："+[string]$baseline.CheckedAt }
        if ($hashes.Contains($key)) { $evidence+="`n当前特征摘要："+$hashes[$key] }
        $rows.Add((New-InsightRow $labels[$key] $state $short $group '本地独立 Edge / Web API' $evidence '系统、浏览器或驱动更新会改变结果。探测浏览器的自动化、GPU 和屏幕参数不代表正在运行的 Claude；变化不等于风险。'))
        [pscustomobject]@{Type='Fingerprint';Key=$key;Hash=$hashes[$key];Comparison=$comparison}
    })
    if ($Remember) {
        if ($hashes.Count -ne $labels.Count) { throw '有设备特征未取得，未覆盖已有基准。请先查看检测结果。' }
        Write-JsonAtomic $baselinePath ([pscustomobject]@{Schema=2;CheckedAt=(Get-Date -Format 'o');Hashes=$hashes})
        $rows.Add((New-Check '设备基准' 'ok' '已保存 20 项特征摘要，旧基准如存在已自动备份。没有更改指纹。'))
    } elseif (-not $baseline) { $rows.Add((New-Check '设备基准对比' 'info' '尚未采集基准。需要跟踪变化时，可手动记住本次特征。')) }
    elseif ($missing.Count) { $rows.Add((New-Check '设备基准对比' 'unknown' ('有 '+$missing.Count+' 项不可比较。旧版算法与新版不同，请在查看结果后手动更新基准；原基准保留。'))) }
    elseif ($changed.Count) { $rows.Add((New-Check '设备基准对比' 'warn' ('变化 '+$changed.Count+' 项：'+(($changed | ForEach-Object {$labels[$_]}) -join '、')+'。逐项展开可查看当前摘要。'))) }
    else { $rows.Add((New-Check '设备基准对比' 'ok' '20 项可测特征与基准一致；不是唯一性或匿名性证明。')) }
    $regional=[ordered]@{Timezone='浏览器时区';Languages='浏览器语言';Locale='Intl 区域格式';TimezoneOffset='UTC 偏移'}
    foreach ($key in $regional.Keys) {
        $value=[string]$fingerprint.$key
        if ([string]::IsNullOrWhiteSpace($value)) {$value='未取得；'+[string]$fingerprint.Errors.$key}
        $rows.Add((New-InsightRow $regional[$key] 'info' $value '时区与语言（忽略影响）' '本地独立 Edge / Intl 与 navigator' '仅展示，不计风险分，不写入 20 项指纹基准，不影响启动判断。' '这是独立探测浏览器的设置；浏览器自身配置可能与 Windows 不同。可在环境设置中手动调整系统选项。'))
    }
    $rows.Add((New-InsightRow '特征解释' 'info' '独立临时 Edge 中本地执行，不上传特征。' '范围与解释' 'https://ippure.com/fingerprint / MyIP BrowserInfo' '音频仅离线计算，不发声、不读取麦克风；存储测试仅写临时探测页面。字体与 Emoji 只描述渲染，不判断地区。时区与语言单独作为信息展示，不参与基准。摄像头、设备名称和账号 Cookie 均未采集。' '基准仅保存摘要；本地诊断记录包含显示的设备信息，导出前可先预览。'))
    New-InsightsResult 'Fingerprint' $rows.ToArray() $observations
}

function Get-UserFormatName {
    # Windows PowerShell 5.1 caches culture in an existing session; read it in a fresh process.
    $value=& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command '(Get-Culture).Name'
    if ($LASTEXITCODE -ne 0 -or -not $value) {throw '无法读取当前 Windows 区域格式。'}
    ([string]$value).Trim()
}

function Get-EnvironmentPreferences {
    [TimeZoneInfo]::ClearCachedData()
    $zone=Get-TimeZone
    $languages=Get-WinUserLanguageList
    [pscustomobject]@{
        Timezone=$zone.Id; Format=(Get-UserFormatName); Language=$languages[0].LanguageTag
        Timezones=@(Get-TimeZone -ListAvailable | ForEach-Object {[pscustomobject]@{Id=$_.Id;Label=$_.DisplayName}})
        Formats=@([Globalization.CultureInfo]::GetCultures([Globalization.CultureTypes]::SpecificCultures) | Sort-Object Name | ForEach-Object {[pscustomobject]@{Id=$_.Name;Label=$_.DisplayName+' · '+$_.Name}})
        Languages=@($languages | ForEach-Object {[pscustomobject]@{Id=$_.LanguageTag;Label=$_.LocalizedName+' · '+$_.LanguageTag}})
    }
}

function Set-EnvironmentPreference($Root,[ValidateSet('Timezone','Format','Language')][string]$Kind,[string]$Value) {
    $lock=Enter-Operation $Root
    try {
        $before=Get-EnvironmentPreferences
        $options=switch ($Kind) {'Timezone' {$before.Timezones} 'Format' {$before.Formats} 'Language' {$before.Languages}}
        if (-not @($options | Where-Object Id -eq $Value).Count) {throw '所选设置已无效；请刷新。新增语言请使用 Windows 语言设置。'}
        if ($before.$Kind -eq $Value) {return [pscustomobject]@{Environment=$before;Message='所选值与当前设置相同，没有修改。'}}
        $languages=Get-WinUserLanguageList
        $backup=Join-Path $Root ('environment-settings\'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'-'+[guid]::NewGuid().ToString('N')+'.json')
        Write-JsonAtomic $backup ([pscustomobject]@{CheckedAt=(Get-Date -Format 'o');Kind=$Kind;Before=$before.$Kind;Requested=$Value;Timezone=$before.Timezone;Format=$before.Format;Languages=@($languages | Select-Object LanguageTag,InputMethodTips,Spellchecking,Handwriting)})
        $warnings=@()
        try {
            switch ($Kind) {
                'Timezone' {Set-TimeZone -Id $Value -ErrorAction Stop}
                'Format' {Set-Culture -CultureInfo $Value -ErrorAction Stop}
                'Language' {
                    # Move the existing language object; retain every language and its input methods.
                    $selected=@($languages | Where-Object LanguageTag -eq $Value)[0]
                    [void]$languages.Remove($selected)
                    $languages.Insert(0,$selected)
                    Set-WinUserLanguageList -LanguageList $languages -Force -ErrorAction Stop -WarningAction SilentlyContinue -WarningVariable warnings
                }
            }
            $after=Get-EnvironmentPreferences
            if ($after.$Kind -ne $Value) {throw 'Windows 读回值与请求不一致，请刷新并检查系统策略。'}
        } catch {throw ('设置未确认完成：'+$_.Exception.Message+' 修改前记录：'+$backup)}
        $message='Windows 设置已写入并读回确认。部分应用会在下次自行打开后采用新设置；本工具不会重启 Claude 或注销系统。修改前记录：'+$backup
        if ($warnings.Count) {$message+='；Windows 提示：'+($warnings -join '；')}
        [pscustomobject]@{Environment=$after;Message=$message}
    } finally {$lock.Dispose()}
}
