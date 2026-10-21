param([string]$WorkRoot=(Join-Path $env:TEMP ('ClaudeHugPlayback-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$package=Split-Path -Parent $PSScriptRoot
$text=[IO.File]::ReadAllText((Join-Path $package 'SwitcherUI.ps1'))
$text=$text -replace '(?m)^\[void\]\$window\.ShowDialog\(\)\s*$',''
$text=$text -replace '(?ms)^\$window\.Add_ContentRendered\(\{.*?^\}\)\r?\n',''
$text=$text.Replace('$PSScriptRoot',("'"+$package.Replace("'","''")+"'"))
. ([scriptblock]::Create($text)) -StateRoot $WorkRoot
$script:opened=$false;$script:ended=$false;$script:mediaError=''
$hugMotion.Add_MediaOpened({$script:opened=$true})
$hugMotion.Add_MediaEnded({$script:ended=$true})
$hugMotion.Add_MediaFailed({$script:mediaError=$args[1].ErrorException.Message})
$watch=[Diagnostics.Stopwatch]::StartNew()
$positions=New-Object System.Collections.Generic.HashSet[int]
try {
    $window.ShowActivated=$false;$window.ShowInTaskbar=$false;$window.Show()
    Open-HugMotion
    $started=$false
    while ($watch.Elapsed.TotalSeconds -lt 20) {
        $frame=New-Object Windows.Threading.DispatcherFrame
        [void]$window.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background,[Action]{$frame.Continue=$false})
        [Windows.Threading.Dispatcher]::PushFrame($frame)
        if ($script:mediaError) {throw $script:mediaError}
        if ($script:opened -and -not $started) {Start-HugEffect;$started=$true}
        [void]$positions.Add([int]($hugMotion.Position.TotalSeconds*30))
        if ($started -and -not $script:hugPlaying) {break}
        Start-Sleep -Milliseconds 10
    }
    if (-not $script:opened -or -not $script:ended -or $script:hugPlaying) {throw 'Native playback did not reach MediaEnded and settle'}
    if ($positions.Count -lt 180) {throw 'Playback did not advance continuously through the clip'}
    if ($hugMotion.NaturalVideoWidth -ne 1586 -or $hugMotion.NaturalVideoHeight -ne 992) {throw 'Playback resolution changed'}
    if (-not $window.FindName('HugCard').IsEnabled -or $script:operation) {throw 'Animation changed the launch gate or left controls disabled'}
    [pscustomobject]@{Status='PASS';MediaOpened=$script:opened;MediaEnded=$script:ended;Duration=$hugMotion.NaturalDuration.TimeSpan.TotalSeconds;PositionSamples=$positions.Count;Elapsed=$watch.Elapsed.TotalSeconds;NoBackendOperation=$true;ControlsRestored=$true} | ConvertTo-Json
} finally {$hugTimer.Stop();$timer.Stop();$guardTimer.Stop();$sceneTimer.Stop();$hugMotion.Close();$window.Close()}
