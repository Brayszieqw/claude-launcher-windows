# Read-only probes. No network settings, application sessions or firewall rules are changed.
function Get-AddressKey {
    # One random key per installation keeps address digests comparable on this machine, while a shared report
    # can no longer be matched back to an address by hashing every IPv4 address. The key never leaves the state folder.
    if ($script:addressKey) { return $script:addressKey }
    $root=if ($StateRoot) {$StateRoot} else {Join-Path $env:LOCALAPPDATA 'ClaudeSwitcherWindows'}
    $path=Join-Path $root 'address-key.txt'
    for ($attempt=0; $attempt -lt 3; $attempt++) {
        if (Test-Path -LiteralPath $path) {
            $key=$null
            try { $key=[Convert]::FromBase64String([IO.File]::ReadAllText($path).Trim()) } catch { $key=$null }
            if ($key.Length -eq 32) { $script:addressKey=$key; return $key }
            # A damaged key only restarts the digests (history comparisons show one change); the old file is kept.
            Move-Item -LiteralPath $path -Destination ($path+'.invalid-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')) -Force
        }
        $fresh=New-Object byte[] 32
        $random=[Security.Cryptography.RandomNumberGenerator]::Create()
        try { $random.GetBytes($fresh) } finally { $random.Dispose() }
        [void](New-Item -ItemType Directory -Path $root -Force)
        $temporary=Join-Path $root ([guid]::NewGuid().ToString('N')+'.tmp')
        [IO.File]::WriteAllText($temporary,[Convert]::ToBase64String($fresh))
        # Another process may create the key at the same moment; whichever file landed first is read back next round.
        try { [IO.File]::Move($temporary,$path) } catch [IO.IOException] { [IO.File]::Delete($temporary) }
    }
    throw '无法建立本机地址摘要密钥，请检查状态目录的写入权限。'
}

function Get-AddressHash([string]$Address) {
    $hmac=New-Object Security.Cryptography.HMACSHA256 (,(Get-AddressKey))
    try { -join ($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($Address)) | ForEach-Object { $_.ToString('x2') }) }
    finally { $hmac.Dispose() }
}

function Get-AddressIdentity([string]$Value) {
    $address = $null
    if (-not [Net.IPAddress]::TryParse($Value.Trim(), [ref]$address)) { throw '探测服务未返回有效的 IP 地址。' }
    if ($address.IsIPv4MappedToIPv6) { $address=$address.MapToIPv4() }
    [pscustomobject]@{ Address=$address.ToString(); Hash=(Get-AddressHash $address.ToString()); Family=$(if ($address.AddressFamily -eq 'InterNetworkV6') {'IPv6'} else {'IPv4'}) }
}

function Test-PublicAddress([string]$Value) {
    $address=$null
    if (-not [Net.IPAddress]::TryParse($Value,[ref]$address)) { return $false }
    if ($address.IsIPv4MappedToIPv6) { $address=$address.MapToIPv4() }
    if ([Net.IPAddress]::IsLoopback($address)) { return $false }
    $b=$address.GetAddressBytes()
    if ($address.AddressFamily -eq 'InterNetworkV6') { return (($b[0] -band 0xe0) -eq 0x20) }
    -not ($b[0] -in @(0,10,127) -or $b[0] -ge 224 -or
        ($b[0] -eq 169 -and $b[1] -eq 254) -or ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or
        ($b[0] -eq 192 -and $b[1] -eq 168) -or ($b[0] -eq 100 -and $b[1] -ge 64 -and $b[1] -le 127) -or
        ($b[0] -eq 198 -and $b[1] -in @(18,19)))
}

function Get-IPv6LocalCheck {
    $addresses=@(Get-NetIPAddress -AddressFamily IPv6 -ErrorAction Stop | Where-Object { $_.AddressState -eq 'Preferred' -and (Test-PublicAddress $_.IPAddress) })
    $routes=@(Get-NetRoute -AddressFamily IPv6 -ErrorAction Stop | Where-Object { $_.DestinationPrefix -in @('::/0','::/1','8000::/1') })
    if (-not $addresses.Count -and -not $routes.Count) { return New-Check 'IPv6' 'info' '未发现全局 IPv6 地址或默认路由；未改变 IPv6 设置。深度检测可进一步测试出站。' }
    New-Check 'IPv6' 'unknown' ("发现 $($addresses.Count) 个全局地址、$($routes.Count) 条默认 / 分割路由。点击深度检测，比较实际 IPv6 出口。")
}

function Start-ProbeHttp($Settings, [string]$Endpoint, [ValidateSet('Proxy','System','IPv4','IPv6')][string]$Route='Proxy', [Diagnostics.Stopwatch]$Budget=[Diagnostics.Stopwatch]::StartNew(), [int]$TimeoutMilliseconds=60000) {
    $uri=[uri]$Endpoint
    if (-not $uri.IsAbsoluteUri -or $uri.Scheme -notin @('http','https') -or $Endpoint -match '["\r\n]' -or $uri.UserInfo) { throw '无效的探测地址。' }
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=Join-Path $env:SystemRoot 'System32/curl.exe'
    $remaining=[Math]::Min($TimeoutMilliseconds,60000-$Budget.ElapsedMilliseconds)
    if ($remaining -le 0) { throw '本轮检测时限已到（上限 60 秒），未完成的请求已停止。' }
    $seconds=($remaining/1000.0).ToString('0.000',[Globalization.CultureInfo]::InvariantCulture)
    $info.Arguments='--disable --silent --show-error --connect-timeout '+$seconds+' --max-time '+$seconds+' --max-filesize 131072 --write-out "\n%{http_code}" '
    if ($Route -eq 'Proxy') {
        $port=[int]$Settings.ProxyPort
        if ($port -lt 1 -or $port -gt 65535) { throw '代理端口无效。' }
        $info.Arguments+='--proxy http://127.0.0.1:'+ $port +' --noproxy "" '
    } else { $info.Arguments+='--noproxy "*" ' }
    if ($Route -eq 'IPv6') { $info.Arguments+='--ipv6 ' }
    elseif ($Route -eq 'IPv4') { $info.Arguments+='--ipv4 ' }
    $info.Arguments+='"'+$uri.AbsoluteUri+'"'
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    $info.StandardOutputEncoding=New-Object Text.UTF8Encoding($false)
    $info.StandardErrorEncoding=New-Object Text.UTF8Encoding($false)
    $process=New-Object Diagnostics.Process
    $process.StartInfo=$info
    try {
        [void]$process.Start()
        [pscustomobject]@{Process=$process;Output=$process.StandardOutput.ReadToEndAsync();Errors=$process.StandardError.ReadToEndAsync();Budget=$Budget}
    } catch { $process.Dispose(); throw }
}

function Close-ProbeHttp($Probe) {
    if (-not $Probe.Process) { return }
    try {
        if (-not $Probe.Process.HasExited) {
            try { $Probe.Process.Kill() }
            catch [InvalidOperationException] { if (-not $Probe.Process.HasExited) { throw } }
        }
    } finally { $Probe.Process.Dispose(); $Probe.Process=$null }
}

function Receive-ProbeHttp($Probe,[switch]$AllowHttpError) {
    $process=$Probe.Process
    try {
        $remaining=[int][Math]::Max(0,60000-$Probe.Budget.ElapsedMilliseconds)
        if (-not $process.HasExited -and (-not $remaining -or -not $process.WaitForExit($remaining))) { throw '本轮检测时限已到（上限 60 秒），未完成的请求已停止。' }
        [void]$Probe.Errors.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw ('HTTPS 探测未完成（curl '+$process.ExitCode+'）；未修改网络设置。') }
        $raw=$Probe.Output.GetAwaiter().GetResult()
        if ($raw -notmatch '(?s)^(.*)\n(\d{3})$') { throw '探测服务未返回 HTTP 状态。' }
        $status=[int]$Matches[2]; $body=$Matches[1]
        if (-not $AllowHttpError -and ($status -lt 200 -or $status -ge 300)) { throw ('服务返回 HTTP '+$status+'；重定向、限流或访问挑战均未当作通过。') }
        [pscustomobject]@{ Body=$body; Status=$status; Milliseconds=[int]($process.ExitTime-$process.StartTime).TotalMilliseconds }
    } finally { Close-ProbeHttp $Probe }
}

function Invoke-ProbeHttp($Settings, [string]$Endpoint, [ValidateSet('Proxy','System','IPv4','IPv6')][string]$Route='Proxy', [Diagnostics.Stopwatch]$Budget=[Diagnostics.Stopwatch]::StartNew(), [int]$TimeoutMilliseconds=60000) {
    Receive-ProbeHttp (Start-ProbeHttp $Settings $Endpoint $Route $Budget $TimeoutMilliseconds)
}

function Invoke-AddressProbe($Settings, [bool]$ViaProxy, [bool]$IPv6, [string]$Endpoint='') {
    if (-not $Endpoint) { $Endpoint=if ($IPv6) {'https://api6.ipify.org'} else {'https://api.ipify.org'} }
    $route=if ($ViaProxy) {'Proxy'} elseif ($IPv6) {'IPv6'} else {'IPv4'}
    $response=Invoke-ProbeHttp $Settings $Endpoint $route
    $identity=Get-AddressIdentity $response.Body
    if (-not (Test-PublicAddress $identity.Address)) { throw '服务未返回有效的公网出口。' }
    if (($IPv6 -and $identity.Family -ne 'IPv6') -or (-not $IPv6 -and $identity.Family -ne 'IPv4')) { throw '服务返回的地址族与探测目标不一致。' }
    $identity
}

function Get-AddressNetwork($Settings, [string]$Address, [Diagnostics.Stopwatch]$Budget=[Diagnostics.Stopwatch]::StartNew()) {
    $identity=Get-AddressIdentity $Address
    if (-not (Test-PublicAddress $identity.Address)) { throw '不能查询非公网出口。' }
    $errors=New-Object System.Collections.Generic.List[string]
    # A failed lookup must not change the proxy route.
    foreach ($provider in @('ipinfo.io','ipwho.is')) {
        try {
            $endpoint=if ($provider -eq 'ipinfo.io') {'https://ipinfo.io/'+$identity.Address+'/json'} else {'https://ipwho.is/'+$identity.Address}
            $data=Read-ProbeJson (Invoke-ProbeHttp $Settings $endpoint 'Proxy' $Budget 8000).Body
            if ($data.error -or $data.success -eq $false -or -not $data.ip) { throw '归属服务未提供有效结果。' }
            if ((Get-AddressIdentity $data.ip).Hash -ne $identity.Hash) { throw '归属响应不属于所查询的出口，未采用。' }
            $number=''; $organization=''
            if ($provider -eq 'ipinfo.io') {
                if ([string]$data.org -match '^AS([1-9][0-9]{0,9})(?:\s|$)') { $number=$Matches[1] }
                $organization=Get-ProbeText $data.org
            } else {
                $number=[string]$data.connection.asn
                $organization=Get-ProbeText $data.connection.org
            }
            $asn=[uint32]0
            if ($number -notmatch '^[1-9][0-9]{0,9}$' -or -not [uint32]::TryParse($number,[ref]$asn)) { throw '归属响应缺少有效 ASN，未按组织名称推断。' }
            return [pscustomobject]@{Asn=$asn;Organization=$organization;Source=$provider;Hash=$identity.Hash}
        } catch { $errors.Add($provider+'：'+$_.Exception.Message) }
    }
    throw ('ASN 未核验（'+($errors -join '；')+'）。')
}

function Get-LaunchNetworkEvidence($Settings, [Diagnostics.Stopwatch]$Budget=[Diagnostics.Stopwatch]::StartNew()) {
    $rows=New-Object System.Collections.Generic.List[object]
    $observations=New-Object System.Collections.Generic.List[object]
    $networks=@{}
    $requests=New-Object System.Collections.Generic.List[object]
    $routeRows=New-Object System.Collections.Generic.List[object]
    $generated=$null
    try {
        foreach ($hostName in (Get-ClaudeDomains)) {
            foreach ($route in @('Proxy','System')) {
                $request=[pscustomobject]@{HostName=$hostName;Route=$route;Probe=$null;Error=''}
                $requests.Add($request)
                try { $request.Probe=Start-ProbeHttp $Settings ('https://'+$hostName+'/cdn-cgi/trace') $route $Budget }
                catch { $request.Error=$_.Exception.Message }
            }
        }
        foreach ($request in $requests) {
            $hostName=$request.HostName; $route=$request.Route
            $label=if ($route -eq 'Proxy') {'显式代理'} else {'系统 / TUN'}
            $name=$hostName+' · '+$label
            try {
                if ($request.Error) { throw $request.Error }
                $response=Receive-ProbeHttp $request.Probe -AllowHttpError
                if ($response.Status -eq 404 -and $hostName -notin @('claude.ai','claude.com','api.anthropic.com')) {
                    if ($null -eq $generated) {$generated=(Get-FlClashSnapshot).Generated}
                    $apiPolicy=Get-ClaudeDomainPolicy $generated 'api.anthropic.com'
                    $hostPolicy=Get-ClaudeDomainPolicy $generated $hostName
                    if (-not $apiPolicy -or $hostPolicy -ne $apiPolicy) {throw '服务不提供出口回显，且无法证明其分流规则与 API 相同。'}
                    $row=New-Check $name 'warn' '分流规则与 API 相同；该服务不提供出口回显，此路径未独立测得公网 IP。'
                    $rows.Add($row); $routeRows.Add($row)
                    continue
                }
                if ($response.Status -and ($response.Status -lt 200 -or $response.Status -ge 300)) {throw ('服务返回 HTTP '+$response.Status+'，出口未验证。')}
                $trace=Read-TraceResponse $response.Body
                $identity=$trace.Identity
                if (-not $networks.ContainsKey($identity.Hash)) {
                    try {$networks[$identity.Hash]=Get-AddressNetwork $Settings $identity.Address $Budget}
                    catch {$networks[$identity.Hash]=[pscustomobject]@{Error=$_.Exception.Message}}
                }
                $network=$networks[$identity.Hash]
                if ($network.Error) {throw $network.Error}
                $allowed=$network.Asn -eq 14593
                $detail='预期 AS14593；实际 AS'+$network.Asn+' · '+$trace.Country+' · '+$identity.Family+' · 摘要 '+$identity.Hash.Substring(0,12)
                $row=New-Check $name $(if ($allowed) {'ok'} else {'fail'}) $detail (-not $allowed)
                $row | Add-Member -NotePropertyMembers @{Source=$hostName+' / '+$network.Source;Evidence=$network.Organization+'；'+$response.Milliseconds+' ms。地区只作展示；IP 变化不影响 ASN 策略。'}
                $rows.Add($row)
                $observations.Add([pscustomobject]@{Type='Egress';Provider=$hostName;Route=$route;Family=$identity.Family;Hash=$identity.Hash;Country=$trace.Country;Asn=$network.Asn;Source=$network.Source;Milliseconds=$response.Milliseconds})
            } catch { $rows.Add((New-Check $name 'unknown' $_.Exception.Message $true)) }
        }
    } finally { foreach ($request in $requests) { if ($request.Probe) { Close-ProbeHttp $request.Probe } } }
    $anchors=@($observations | Where-Object {$_.Provider -in @('claude.ai','claude.com','api.anthropic.com') -and $_.Asn -eq 14593})
    if ($routeRows.Count -and $anchors.Count -ne 6) {
        foreach ($row in $routeRows) {$row.State='unknown'; $row.Blocking=$true; $row.Detail='网页 / API 的六条实测路径尚未全部通过，不能采用关联路由证据。'}
    }
    foreach ($family in @($observations | Group-Object Family)) {
        if (@($family.Group.Hash | Sort-Object -Unique).Count -gt 1) {
            $rows.Add((New-Check ('出口一致性 · '+$family.Name) 'fail' '同一轮核验中的域名或路径出口不一致；即使都属于星链也会提醒。不同轮次的 IP 变化另行观察。' $true))
        }
    }
    $state=if (@($rows | Where-Object State -eq 'fail').Count) {'fail'} elseif (@($rows | Where-Object State -eq 'unknown').Count) {'unknown'} else {'ok'}
    $detail=switch ($state) {
        'ok' {([string]$observations.Count)+' 条路径实测为 Starlink AS14593，'+$routeRows.Count+' 条仅核对了与 API 相同的分流规则；同地址族的实测出口一致。'}
        'fail' {'检测到非星链或同轮出口不一致，详见各路径结果。'}
        'unknown' {'本轮出口证据不完整；超时、限流和无效响应不等于已确认异常，也不计为通过。'}
    }
    [pscustomobject]@{State=$state;Detail=$detail;Checks=$rows.ToArray();Observations=$observations.ToArray();CheckedAt=[DateTime]::UtcNow.ToString('o')}
}

function Read-StunAddress([byte[]]$Packet, [byte[]]$Request) {
    if ($Packet.Length -lt 20 -or $Packet[0] -ne 1 -or $Packet[1] -ne 1) { throw 'STUN 响应头无效。' }
    $length=([int]$Packet[2] -shl 8) -bor [int]$Packet[3]
    if ($length % 4 -ne 0 -or $Packet.Length -ne 20+$length) { throw 'STUN 响应长度无效。' }
    for ($i=4;$i -lt 20;$i++) { if ($Packet[$i] -ne $Request[$i]) { throw 'STUN 事务标识不匹配。' } }
    $position=20
    while ($position+4 -le $Packet.Length) {
        $type=([int]$Packet[$position] -shl 8) -bor [int]$Packet[$position+1]
        $size=([int]$Packet[$position+2] -shl 8) -bor [int]$Packet[$position+3]
        $value=$position+4
        if ($value+$size -gt $Packet.Length) { throw 'STUN 属性越界。' }
        if ($type -eq 0x20) {
            if ($size -lt 8) { throw 'STUN 地址属性不完整。' }
            $count=switch ($Packet[$value+1]) { 1 {4} 2 {16} default {throw 'STUN 地址族不支持。'} }
            if ($size -ne 4+$count) { throw 'STUN 地址长度无效。' }
            $bytes=New-Object byte[] $count
            for ($i=0;$i -lt $count;$i++) { $bytes[$i]=$Packet[$value+4+$i] -bxor $Request[4+$i] }
            return (New-Object Net.IPAddress (,$bytes)).ToString()
        }
        $position=$value+$size+((4-$size%4)%4)
    }
    throw 'STUN 响应未包含映射地址。'
}

function Invoke-StunProbe([string]$Server, [int]$Port) {
    $lookup=[Net.Dns]::GetHostAddressesAsync($Server)
    if (-not $lookup.Wait(3000)) { throw 'STUN DNS 查询超时。' }
    $address=$lookup.Result | Where-Object AddressFamily -eq 'InterNetwork' | Select-Object -First 1
    if (-not $address) { throw 'STUN 服务未提供 IPv4 地址。' }
    $request=New-Object byte[] 20
    $request[1]=1; $request[4]=0x21; $request[5]=0x12; $request[6]=0xa4; $request[7]=0x42
    $random=[Security.Cryptography.RandomNumberGenerator]::Create()
    try { $transaction=New-Object byte[] 12; $random.GetBytes($transaction); [Array]::Copy($transaction,0,$request,8,12) }
    finally { $random.Dispose() }
    $socket=New-Object Net.Sockets.UdpClient
    try {
        $socket.Client.ReceiveTimeout=2500
        $socket.Connect($address,$Port)
        [void]$socket.Send($request,$request.Length)
        $sender=New-Object Net.IPEndPoint ([Net.IPAddress]::Any),0
        $packet=$socket.Receive([ref]$sender)
        Get-AddressIdentity (Read-StunAddress $packet $request)
    } finally { $socket.Dispose() }
}

function Compare-ProbeAddresses($Name, $Addresses, $References, [int]$Failures=0) {
    $public=@($Addresses | Where-Object { Test-PublicAddress $_ } | Select-Object -Unique)
    if (-not $public.Count) { return New-Check $Name 'unknown' '没有获取到可比较的公网地址；无响应、被阻断或仅有本地候选都不能证明没有泄漏。' }
    $unmatched=0; $missing=0
    foreach ($value in $public) {
        $identity=Get-AddressIdentity $value
        $reference=$References[$identity.Family]
        if (-not $reference) { $missing++ }
        elseif ($identity.Hash -ne $reference.Hash) { $unmatched++ }
    }
    if ($unmatched) { return New-Check $Name 'warn' ("发现 $unmatched 个地址与同地址族的代理出口不同。动态 IP、分流或绕行都可能造成差异；此项未核验 ASN，不能单凭地址变化判为非星链。") }
    if ($missing -or $Failures) { return New-Check $Name 'unknown' ("已取得 $($public.Count) 个公网地址；缺少 $missing 个对应基准，另有 $Failures 个未完成探测，暂不能完整判断。") }
    New-Check $Name 'ok' ("本次 $($public.Count) 个公网地址与对应的代理出口一致；仅代表这些探测路径。")
}

function Get-BrowserProbe([ValidateSet('WebRtc','Fingerprint')][string]$Mode='WebRtc', [string[]]$StunUrls=@('stun:stun.l.google.com:19302','stun:stun.cloudflare.com:3478')) {
    $edge=@((Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Microsoft/Edge/Application/msedge.exe'),(Join-Path $env:ProgramFiles 'Microsoft/Edge/Application/msedge.exe')) |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $edge) { throw '未找到 Microsoft Edge，无法进行独立浏览器检测。' }
    $listener=New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback),0
    $listener.Start()
    $port=$listener.LocalEndpoint.Port
    Clear-StaleProbeProfiles
    $nonce=[guid]::NewGuid().ToString('N')
    $profile=Join-Path ([IO.Path]::GetTempPath()) ('ClaudeProbe-'+$nonce)
    [void](New-Item -ItemType Directory -Path $profile)
    $configuration=@{ mode=$Mode; urls=@($StunUrls); callback=('/result/'+$nonce) } | ConvertTo-Json -Compress
    $html=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'probe/webrtc.html')).Replace('__CONFIG__',$configuration)
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$edge
    $info.Arguments='--headless=new --no-first-run --disable-background-networking --disable-component-update --disable-sync --disable-extensions --disable-default-apps --no-default-browser-check --user-data-dir="'+$profile+'" http://127.0.0.1:'+ $port +'/'+$nonce
    if ($Mode -eq 'Fingerprint') { $info.Arguments+=' --host-resolver-rules="MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"' }
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    $browser=New-Object Diagnostics.Process
    $browser.StartInfo=$info
    try {
        [void]$browser.Start()
        [void]$browser.StandardOutput.ReadToEndAsync()
        [void]$browser.StandardError.ReadToEndAsync()
        $deadline=[DateTime]::UtcNow.AddSeconds(25)
        $accept=$listener.BeginAcceptTcpClient($null,$null)
        while ([DateTime]::UtcNow -lt $deadline) {
            if (-not $accept.AsyncWaitHandle.WaitOne(100)) { continue }
            $client=$listener.EndAcceptTcpClient($accept)
            $accept.AsyncWaitHandle.Close()
            $accept=$listener.BeginAcceptTcpClient($null,$null)
            try {
                $stream=$client.GetStream(); $stream.ReadTimeout=2000; $stream.WriteTimeout=2000
                $headerBytes=New-Object System.Collections.Generic.List[byte]
                $crlf=[string][char]13+[char]10
                $emptyConnection=$false
                do {
                    $remaining=($deadline-[DateTime]::UtcNow).TotalMilliseconds
                    if ($remaining -le 0) { throw '浏览器检测未在 25 秒内回传结果。' }
                    $stream.ReadTimeout=[Math]::Max(1,[Math]::Min(2000,[int]$remaining))
                    try { $next=$stream.ReadByte() }
                    catch [IO.IOException] {
                        if ($headerBytes.Count) { throw }
                        $emptyConnection=$true; break
                    }
                    # Chromium can open and abandon a speculative connection without sending a request.
                    if ($next -lt 0 -and -not $headerBytes.Count) { $emptyConnection=$true; break }
                    if ($next -lt 0 -or $headerBytes.Count -ge 8192) { throw '浏览器 HTTP 请求头不完整。' }
                    $headerBytes.Add([byte]$next)
                    $header=[Text.Encoding]::ASCII.GetString($headerBytes.ToArray())
                } until ($header.EndsWith($crlf+$crlf))
                if ($emptyConnection) { continue }
                $lines=$header.Split(@($crlf),[StringSplitOptions]::None)
                $first=$lines[0]; $contentLength=0
                foreach ($line in $lines) { if ($line -match '^Content-Length:\s*(\d+)$') { $contentLength=[int]$Matches[1] } }
                if ($contentLength -gt 32768) { throw '浏览器检测结果超过预期大小。' }
                $result=$null; $status='404 Not Found'; $body=''; $contentType='text/plain'
                if ($first -eq "GET /$nonce HTTP/1.1") { $status='200 OK'; $body=$html; $contentType='text/html; charset=utf-8' }
                elseif ($first -eq "POST /result/$nonce HTTP/1.1") {
                    $payload=New-Object byte[] $contentLength; $read=0
                    while ($read -lt $contentLength) {
                        $remaining=($deadline-[DateTime]::UtcNow).TotalMilliseconds
                        if ($remaining -le 0) { throw '浏览器检测未在 25 秒内回传结果。' }
                        $stream.ReadTimeout=[Math]::Max(1,[Math]::Min(2000,[int]$remaining))
                        $count=$stream.Read($payload,$read,$contentLength-$read)
                        if ($count -eq 0) { throw '浏览器检测结果不完整。' }
                        $read+=$count
                    }
                    $result=[Text.Encoding]::UTF8.GetString($payload) | ConvertFrom-Json
                    $status='200 OK'; $body='OK'
                }
                $bytes=[Text.Encoding]::UTF8.GetBytes($body)
                $header=[Text.Encoding]::ASCII.GetBytes((@("HTTP/1.1 $status","Content-Type: $contentType","Content-Length: $($bytes.Length)",'Connection: close','Cache-Control: no-store','','') -join $crlf))
                $stream.Write($header,0,$header.Length); $stream.Write($bytes,0,$bytes.Length)
                if ($result) {
                    if ($result.Error) { throw ('浏览器检测失败：'+$result.Error) }
                    return $result
                }
            } finally { $client.Dispose() }
        }
        throw '浏览器检测未在 25 秒内回传结果。'
    } finally {
        $listener.Stop()
        if ($accept) { $accept.AsyncWaitHandle.Close() }
        # Edge may relaunch itself. Identify every owned process by its unique profile, not a process name or parent PID.
        $owned=@(Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" -ErrorAction Stop | Where-Object {
            $_.ExecutablePath -eq $edge -and $_.CommandLine.Contains($profile)
        } | Sort-Object { $_.CommandLine -match '--type=' })
        foreach ($entry in $owned) {
            $child=Get-Process -Id $entry.ProcessId -ErrorAction SilentlyContinue
            if (-not $child) { continue }
            try {
                if ($child.HasExited) { continue }
                $birth=$child.StartTime.ToUniversalTime().Ticks
                # CIM timestamps have microsecond precision; Process timestamps retain 100 ns ticks.
                if (($birth-($birth % 10)) -eq $entry.CreationDate.ToUniversalTime().Ticks) {
                    try { $child.Kill(); [void]$child.WaitForExit(2000) }
                    catch [InvalidOperationException] { if (-not $child.HasExited) { throw } }
                    catch [ComponentModel.Win32Exception] { if (-not $child.HasExited) { throw } }
                }
            } finally { $child.Dispose() }
        }
        $browser.Dispose()
        Remove-ProbeProfile $profile
    }
}

function Remove-ProbeProfile([string]$Path, [int]$Attempts=20) {
    # Edge can hold profile files for a moment after it exits; retry briefly, then leave it to the next sweep.
    # Directory.Delete removes links inside the folder without following them.
    for ($attempt=0; $attempt -lt $Attempts -and [IO.Directory]::Exists($Path); $attempt++) {
        try { [IO.Directory]::Delete($Path,$true) } catch { Start-Sleep -Milliseconds 250 }
    }
}

function Clear-StaleProbeProfiles {
    # Profiles left by an interrupted probe, or by releases that never removed them, are cleared after an hour.
    $limit=[DateTime]::UtcNow.AddHours(-1)
    foreach ($directory in @(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Directory -Filter 'ClaudeProbe-*' -ErrorAction SilentlyContinue)) {
        if ($directory.Name -cmatch '^ClaudeProbe-[0-9a-f]{32}$' -and $directory.CreationTimeUtc -lt $limit) { Remove-ProbeProfile $directory.FullName 1 }
    }
}

function Get-DeepCheck($Root) {
    $basic=Get-EnvironmentCheck $Root
    if (-not $basic.Ready) {
        return [pscustomobject]@{Ready=$false;Deep=$true;CheckedAt=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss');Checks=@($basic.Checks);Message='基础前提未通过，未发送深度探测；请查看本次阻止原因。'}
    }
    $settings=Get-Settings $Root
    $rows=New-Object System.Collections.Generic.List[object]
    $references=@{}
    foreach ($family in @('IPv4','IPv6')) {
        try {
            $references[$family]=Invoke-AddressProbe $settings $true ($family -eq 'IPv6')
            $rows.Add((New-Check ($family+' 代理基准') 'ok' '已取得该地址族的代理出口摘要，供本次检测比较。'))
        } catch { $rows.Add((New-Check ($family+' 代理基准') 'unknown' $_.Exception.Message)) }
    }
    foreach ($family in @('IPv4','IPv6')) {
        $name=if ($family -eq 'IPv6') {'IPv6 出站一致性'} else {'HTTPS 出站一致性'}
        try {
            $direct=Invoke-AddressProbe $settings $false ($family -eq 'IPv6')
            $rows.Add((Compare-ProbeAddresses $name @($direct.Address) $references))
        } catch { $rows.Add((New-Check $name 'unknown' ($_.Exception.Message+' 无响应可能是没有可用出站或服务不可达，不能据此宣称安全。'))) }
    }
    $udp=New-Object System.Collections.Generic.List[string]; $failed=0
    $udpDetails=New-Object System.Collections.Generic.List[string]
    foreach ($server in @(@{Host='stun.l.google.com';Port=19302},@{Host='stun.cloudflare.com';Port=3478})) {
        try {
            $observed=Invoke-StunProbe $server.Host $server.Port; $udp.Add($observed.Address)
            $udpDetails.Add($server.Host+':'+$server.Port+' → '+$observed.Family+' 摘要 '+$observed.Hash.Substring(0,12))
        } catch {$failed++;$udpDetails.Add($server.Host+':'+$server.Port+' → '+$_.Exception.Message)}
    }
    $udpRow=Compare-ProbeAddresses 'UDP / STUN（IPv4）' $udp.ToArray() $references $failed
    $rows.Add((New-InsightRow $udpRow.Name $udpRow.State $udpRow.Detail 'UDP / STUN' 'Google STUN / Cloudflare STUN' ($udpDetails -join "`n") '分别执行 STUN 事务校验；无响应可能来自 UDP 过滤或服务不可达，不等于没有泄漏。'))
    try {
        $web=Get-BrowserProbe
        $failures=@($web.Errors).Count
        if ($web.TimedOut) { $failures++ }
        $row=Compare-ProbeAddresses '浏览器 WebRTC' @($web.Candidates | ForEach-Object Address) $references $failures
        $candidates=@($web.Candidates)
        $public=@($candidates | Where-Object {Test-PublicAddress $_.Address})
        $mdns=@($candidates | Where-Object {$_.Address -like '*.local'}).Count
        $hostCount=@($candidates | Where-Object Type -eq 'host').Count
        $srflx=@($candidates | Where-Object Type -eq 'srflx').Count
        $relay=@($candidates | Where-Object Type -eq 'relay').Count
        $details='候选总数 '+$candidates.Count+'；host '+$hostCount+'；srflx '+$srflx+'；relay '+$relay+'；mDNS 名称 '+$mdns+'；公网候选 '+$public.Count+'；超时 '+$web.TimedOut+'。'
        foreach ($candidate in $public) {
            $id=Get-AddressIdentity $candidate.Address
            $details+="`n"+$candidate.Type+' / '+$candidate.Protocol+' / '+$id.Family+' #'+$id.Hash.Substring(0,12)
        }
        if (@($web.Errors).Count) {$details+="`nICE 错误码："+(($web.Errors | ForEach-Object Code) -join '、')}
        $rows.Add((New-InsightRow $row.Name $row.State $row.Detail '浏览器 WebRTC' '独立 Edge / Google 与 Cloudflare STUN' $details 'mDNS 只说明本地候选名称被遮蔽，不能证明公网地址不会暴露。未配置 TURN，不把没有 relay 候选当异常。'))
    } catch { $rows.Add((New-Check '浏览器 WebRTC' 'unknown' $_.Exception.Message)) }
    $rows.Add((New-Check '防护范围' 'info' '本次检查 HTTPS、IPv6、UDP 与独立 Edge WebRTC 路径；不修改网络，不关闭现有会话。全流量阻断和 Claude 内置浏览器不在此结果的保证范围内。'))
    [pscustomobject]@{
        Ready=(@($rows | Where-Object { $_.State -in @('fail','warn','unknown') }).Count -eq 0)
        Deep=$true; CheckedAt=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); Checks=$rows.ToArray()
        Message='检测完成。结果仅针对本次路径，不会关闭 Claude 或自动改变代理。'
    }
}
