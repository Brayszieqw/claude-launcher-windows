param([string]$WorkRoot = (Join-Path $env:TEMP ('ClaudeDnsTests-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$package=Split-Path -Parent $PSScriptRoot
[void](New-Item -ItemType Directory -Path $WorkRoot -Force)
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
. (Join-Path $package 'flclash-checks.ps1')
function Assert($Condition,$Message) {if (-not $Condition) {throw $Message}}
function Wait-Ui($Condition,[int]$Seconds=45) {
    $deadline=[DateTime]::UtcNow.AddSeconds($Seconds)
    while (-not (& $Condition)) {
        if ([DateTime]::UtcNow -ge $deadline) {throw 'Embedded browser timed out'}
        $frame=New-Object Windows.Threading.DispatcherFrame
        [void][Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background,[Action]{$frame.Continue=$false})
        [Windows.Threading.Dispatcher]::PushFrame($frame)
        Start-Sleep -Milliseconds 25
    }
}
$owner=New-Object Windows.Window
$owner.Title='DNS integration test'
$owner.ShowInTaskbar=$false
$owner.Show()
try {
    $state=Join-Path $WorkRoot 'state'
    $view=Open-DnsTestPage IPCheck -Owner $owner -StateRoot $state
    Assert ([object]::ReferenceEquals($view,(Open-DnsTestPage IPCheck -Owner $owner -StateRoot $state))) 'Repeated open created another browser'
    $browser=$view.FindName('IpCheckBrowser')
    $status=$view.FindName('IpCheckStatus')
    Wait-Ui { $status.Text -notlike '正在加载*' }
    Assert ($status.Text -like '原站*') $status.Text
    Assert ($browser.Source.AbsoluteUri -eq 'https://ipcheck.ing/tools/enhanceddnsleaktest') 'Unexpected navigation destination'
    Assert ($browser.CoreWebView2.Environment.UserDataFolder -eq $state+'\ipcheck-webview') 'Browser did not use the isolated state folder'
    Assert (-not $browser.CoreWebView2.Settings.AreHostObjectsAllowed -and -not $browser.CoreWebView2.Settings.IsWebMessageEnabled) 'Remote page has an unnecessary host bridge'
    $script:dom=$null
    Wait-Ui {
        $task=$browser.ExecuteScriptAsync("JSON.stringify({theme:!!document.getElementById('claude-launcher-theme'),background:getComputedStyle(document.documentElement).getPropertyValue('--background').trim(),image:getComputedStyle(document.body).backgroundImage,buttons:document.querySelectorAll('button').length,title:document.title})")
        Wait-Ui { $task.IsCompleted } 5
        $script:dom=($task.GetAwaiter().GetResult() | ConvertFrom-Json) | ConvertFrom-Json
        $script:dom.theme -and $script:dom.buttons -gt 0
    }
    Assert ($dom.background -eq '#2b1f1a' -and $dom.image -like '*claude-assets.local/background.png*') 'Launcher theme was not applied'
    $task=$browser.ExecuteScriptAsync("window.claudeThemeImageTest=new Image(); window.claudeThemeImageTest.src='https://claude-assets.local/background.png';")
    Wait-Ui {$task.IsCompleted} 5
    [void]$task.GetAwaiter().GetResult()
    Wait-Ui {
        $task=$browser.ExecuteScriptAsync('window.claudeThemeImageTest.complete && window.claudeThemeImageTest.naturalWidth > 0')
        Wait-Ui {$task.IsCompleted} 5
        $task.GetAwaiter().GetResult() -eq 'true'
    } 15
    $view.Close()
    $reopened=Open-DnsTestPage IPCheck -Owner $owner -StateRoot $state
    Assert (-not [object]::ReferenceEquals($view,$reopened)) 'Closed browser was reused'
    $owner.Close()
    Assert (-not $reopened.IsVisible) 'Closing the assistant left its embedded window open'
    [pscustomobject]@{Name='Original IPCheck page, launcher theme, isolated profile and window lifecycle';Status='PASS';Title=$dom.title;Profile=$state+'\ipcheck-webview'} | ConvertTo-Json
} finally {if ($owner.IsVisible) {$owner.Close()}}
