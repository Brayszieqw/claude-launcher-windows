param([string]$WorkRoot=(Join-Path $env:TEMP ('ClaudeSourcePackage-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$package=Split-Path -Parent $PSScriptRoot
function Assert($Condition,$Message) {if (-not $Condition) {throw $Message}}
Assert (-not (Test-Path -LiteralPath (Join-Path $package 'assets'))) 'Run this test on the source-only package without artwork'
$text=[IO.File]::ReadAllText((Join-Path $package 'SwitcherUI.ps1'))
$text=$text -replace '(?m)^\[void\]\$window\.ShowDialog\(\)\s*$',''
$text=$text.Replace('$PSScriptRoot',("'"+$package.Replace("'","''")+"'"))
. ([scriptblock]::Create($text)) -StateRoot $WorkRoot
try {
    Assert ($window.FindName('BtnStart').IsEnabled -and $window.Icon) 'Source build did not initialize its window and generated icon'
    Assert (-not $window.FindName('HugIdle').Source -and -not $hugMotion.Source) 'Source build unexpectedly contains artwork'
    Start-HugEffect
    Assert (-not $script:hugPlaying -and $window.FindName('HugCard').IsEnabled -and -not $script:operation) 'Missing media disabled controls or started another operation'
    $sdk=Join-Path $package 'lib\WebView2'
    $core=Join-Path $sdk 'Microsoft.Web.WebView2.Core.dll'
    $wpf=Join-Path $sdk 'Microsoft.Web.WebView2.Wpf.dll'
    Add-Type -Path $core,$wpf
    $references=@($core,$wpf,'System.dll','System.Core.dll','System.Drawing.dll','System.Xaml.dll',[Windows.Window].Assembly.Location,[Windows.Media.Visual].Assembly.Location,[Windows.Threading.Dispatcher].Assembly.Location)
    Add-Type -Path (Join-Path $package 'launcher\IpCheckWindow.cs') -ReferencedAssemblies $references
    Assert (-not (Test-Path -LiteralPath $WorkRoot)) 'Loading the source-only interface wrote runtime state'
    [pscustomobject]@{Status='PASS';ArtworkRequired=$false;WindowInitialized=$true;MissingMediaPreservesControls=$true;IpCheckCompiled=$true;RuntimeStateUntouched=$true} | ConvertTo-Json
} finally {$timer.Stop();$guardTimer.Stop();$sceneTimer.Stop();$hugTimer.Stop();$hugMotion.Close();$window.Close()}
