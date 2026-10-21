$ErrorActionPreference='Stop'
Add-Type -Path (Join-Path $PSScriptRoot 'LoopbackFixtures.cs')
$path=Join-Path (Split-Path -Parent $PSScriptRoot) 'network-probes.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$null,[ref]$null)
$function=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-BrowserProbe'},$true)
# Exercise the actual parser loops with a real slow socket, without starting Edge.
$header=$function.Find({param($n) $n -is [Management.Automation.Language.DoUntilStatementAst] -and $n.Extent.Text.Contains('$stream.ReadByte()')},$true)
$body=$function.Find({param($n) $n -is [Management.Automation.Language.WhileStatementAst] -and $n.Condition.Extent.Text -eq '$read -lt $contentLength'},$true)
$results=@(foreach($case in @(@('Header',$header),@('Body',$body))) {
    if (-not $case[1]) {throw ('Parser loop not found: '+$case[0])}
    $server=[LoopbackFixture]::Drip(75,20)
    $client=New-Object Net.Sockets.TcpClient
    try {
        $client.Connect('127.0.0.1',$server.Port)
        $stream=$client.GetStream();$stream.ReadTimeout=2000
        $headerBytes=New-Object System.Collections.Generic.List[byte]
        $crlf=[string][char]13+[char]10
        $emptyConnection=$false
        $contentLength=100;$payload=New-Object byte[] $contentLength;$read=0
        $deadline=[DateTime]::UtcNow.AddMilliseconds(450)
        $watch=[Diagnostics.Stopwatch]::StartNew()
        $caught=$false
        try {& ([scriptblock]::Create($case[1].Extent.Text))} catch {$caught=$true}
        $watch.Stop()
        $passed=$caught -and $watch.ElapsedMilliseconds -ge 300 -and $watch.ElapsedMilliseconds -lt 1000 -and -not $server.Failure
        [pscustomobject]@{Name=($case[0]+' absolute deadline');Status=$(if($passed){'PASS'}else{'FAIL'});ElapsedMilliseconds=$watch.ElapsedMilliseconds}
    } finally {$client.Dispose();$server.Dispose()}
})
$results | ConvertTo-Json
if (@($results | Where-Object Status -eq 'FAIL').Count) {exit 1}
