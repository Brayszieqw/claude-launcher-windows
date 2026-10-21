param([string]$WorkRoot = (Join-Path $env:TEMP ('ClaudeUiTests-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$package=Split-Path -Parent $PSScriptRoot
[void](New-Item -ItemType Directory -Path $WorkRoot -Force)
$before=@(Get-Process -Name Claude,FlClash,FlClashCore -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,StartTime,MainWindowTitle)
$before | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $WorkRoot 'processes-before.json') -Encoding UTF8
$text=[IO.File]::ReadAllText((Join-Path $package 'SwitcherUI.ps1'))
# Build the real controls and handlers without showing a modal window or invoking its startup event.
$text=$text -replace '(?m)^\[void\]\$window\.ShowDialog\(\)\s*$',''
# An in-memory script has no script directory; retain the original file's relative resource paths.
$text=$text.Replace('$PSScriptRoot', ("'"+$package.Replace("'","''")+"'"))
. ([scriptblock]::Create($text)) -StateRoot (Join-Path $WorkRoot 'state')
function Assert($Condition,$Message) { if (-not $Condition) { throw $Message } }
function Wait-UiAction {
    $deadline=[DateTime]::UtcNow.AddSeconds(40)
    while ($script:operation -and [DateTime]::UtcNow -lt $deadline) {
        $frame=New-Object Windows.Threading.DispatcherFrame
        [void]$window.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background,[Action]{$frame.Continue=$false})
        [Windows.Threading.Dispatcher]::PushFrame($frame)
        Start-Sleep -Milliseconds 20
    }
    Assert (-not $script:operation) 'UI action timed out'
    Assert ($window.FindName('StatusText').Text -ne '操作未完成') $window.FindName('Hint').Text
}
function Click-LocalButton($Name) {
    if ($Name -notin @('BtnAdd','BtnRename','BtnRefresh','BtnFingerprint','BtnFingerprintSave','BtnEnvironmentRead','BtnFlClash')) { throw 'Only local buttons are allowed in this smoke test' }
    $window.FindName($Name).RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
    Assert (-not $window.FindName('BtnStart').IsEnabled) 'Launch button was enabled during an operation'
    Wait-UiAction
}
try {
    Assert ([object]::ReferenceEquals($window.FindName('MainTabs').SelectedContent,$window.FindName('PageOverview'))) 'Fresh window did not select the overview'
    Assert $window.FindName('BtnStart').IsEnabled 'Fresh window still locked launch'
    foreach ($name in @('NavNetwork','NavFingerprint','NavAccounts','NavReports','NavEnvironment','NavAbout','NavOverview')) {
        $window.FindName($name).IsChecked=$true
        Assert ($window.FindName('MainTabs').SelectedIndex -eq $navIndexes[$name]) ('Navigation did not select '+$name)
    }
    Update-Narrow 760
    Assert ($window.FindName('NavOverviewText').Visibility -eq 'Collapsed' -and $window.FindName('BrandText').Visibility -eq 'Collapsed' -and $window.Resources['PanelMargin'].Right -eq 22) 'Narrow navigation not applied'
    Update-Narrow 1180
    Assert ($window.FindName('NavOverviewText').Visibility -eq 'Visible' -and $window.Resources['PanelMargin'].Right -gt 22) 'Full navigation not restored'
    # 1.0: 「拥抱一下」 comes first and replaces 「检查环境」; 「启动 Claude」 follows and remains independent of network results.
    Assert ($window.FindName('BtnCheck').Content -eq '拥抱一下' -and $window.FindName('BtnStart').Content -eq '启动 Claude') 'Hug and launch buttons were not renamed'
    Assert ([Windows.Controls.Grid]::GetColumn($window.FindName('BtnCheck')) -lt [Windows.Controls.Grid]::GetColumn($window.FindName('BtnStart'))) 'Hug button is not before the launch button'
    $window.FindName('BtnDetails').RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
    Assert ($window.FindName('DetailsPanel').Visibility -eq 'Visible') 'Check details did not open'
    $window.FindName('BtnDetailsClose').RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
    Assert ($window.FindName('DetailsPanel').Visibility -eq 'Collapsed') 'Check details did not close'
    Open-AccountDialog 'add'
    Save-AccountDialog
    Assert ($window.FindName('DialogError').Visibility -eq 'Visible' -and -not $script:operation) 'Empty account name was dispatched'
    Close-AccountDialog
    Assert ($window.FindName('DialogHost').Visibility -eq 'Collapsed' -and $window.FindName('MainContent').IsEnabled) 'Cancel left the main page disabled'
    Click-LocalButton 'BtnRefresh'
    Assert ($window.FindName('AccountList').Items.Count -eq 1) 'Initial account row missing'
    $window.FindName('BtnShowAdd').RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
    Assert ($window.FindName('DialogHost').Visibility -eq 'Visible') 'Add button did not open the dialog'
    $window.FindName('AccountName').Text='工作 "中文" & 测试'
    Click-LocalButton 'BtnAdd'
    $selected=$window.FindName('AccountList').SelectedItem
    Assert ($selected.Name -eq '工作 "中文" & 测试' -and -not $selected.IsCurrent) 'Unicode account name was not transferred correctly'
    $id=$selected.Id
    Show-Page 1
    $window.Content.Measure([Windows.Size]::new(1040,800));$window.Content.Arrange([Windows.Rect]::new(0,0,1040,800));$window.Content.UpdateLayout()
    function Find-RenameButton($Node) {
        if ($Node -is [Windows.Controls.Button] -and $Node.Tag -eq 'RenameAccount' -and $Node.DataContext.Id -eq $id) {return $Node}
        for ($i=0;$i -lt [Windows.Media.VisualTreeHelper]::GetChildrenCount($Node);$i++) {Find-RenameButton ([Windows.Media.VisualTreeHelper]::GetChild($Node,$i))}
    }
    $renameButton=@(Find-RenameButton $window.FindName('AccountList'))[0]
    Assert ($null -ne $renameButton) 'Per-card rename button was not rendered'
    $renameButton.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
    Assert ($script:renameId -eq $id -and $window.FindName('DialogHost').Visibility -eq 'Visible') 'Per-card rename opened the wrong profile'
    $window.FindName('AccountName').Text='常用账号'
    Click-LocalButton 'BtnRename'
    Assert ($window.FindName('AccountList').SelectedItem.Id -eq $id) 'Rename changed the selection ID'
    Assert ($window.FindName('AccountList').SelectedItem.Name -eq '常用账号') 'Rename callback did not refresh the card'
    Open-AccountDialog 'add'
    $window.FindName('AccountName').Text='学习账号'
    Click-LocalButton 'BtnAdd'
    Assert ($window.FindName('AccountList').Items.Count -eq 3) 'Third profile card missing'
    $tabs=$window.FindName('MainTabs')
    $tabs.SelectedIndex=1
    Update-Narrow 760
    $grid=$window.Content
    $grid.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#F4F6FA')
    $grid.Measure([Windows.Size]::new(760,760))
    $grid.Arrange([Windows.Rect]::new(0,0,760,760))
    $grid.UpdateLayout()
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(1140,1140,144,144,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($grid)
    $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $outputPath=Join-Path $WorkRoot 'accounts-ui-150.png'
    $stream=[IO.File]::Create($outputPath)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
    $tabs.SelectedIndex=3
    Click-LocalButton 'BtnFingerprintSave'
    Assert (Test-Path -LiteralPath (Join-Path $WorkRoot 'state\fingerprint-baseline.json')) 'Fingerprint button did not save to the temporary state'
    Click-LocalButton 'BtnFingerprint'
    Assert (@($window.FindName('FingerprintGroups').ItemsSource | ForEach-Object Items).Count -eq 26) 'Fingerprint result rows missing'
    Assert ($window.FindName('FingerprintTitle').Text -match '设备特征') 'Insights callback did not update the UI'
    $grid.Measure([Windows.Size]::new(760,760))
    $grid.Arrange([Windows.Rect]::new(0,0,760,760))
    $grid.UpdateLayout()
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(1140,1140,144,144,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($grid)
    $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $insightsPreview=Join-Path $WorkRoot 'insights-ui-150.png'
    $stream=[IO.File]::Create($insightsPreview)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
    Assert ($window.FindName('RegionalChecks').Items.Count -eq 4) 'Regional information not displayed'
    $fingerprintTitle=$window.FindName('FingerprintTitle').Text
    $fixtureChecks=@(
        [pscustomobject]@{Name='网络保留测试';State='ok';Detail='fixture';Group='出口';Source='fixture';Evidence='Route-Evidence';Advice='fixture'}
        [pscustomobject]@{Name='差异';State='fail';Detail='需核对路径';Group='出口'}
        [pscustomobject]@{Name='提醒';State='warn';Detail='需人工核对';Group='出口'}
        [pscustomobject]@{Name='超时';State='unknown';Detail='未完成';Group='DNS'}
        [pscustomobject]@{Name='范围';State='info';Detail='说明';Group='DNS'}
    )
    Show-Insights ([pscustomobject]@{Kind='Network';CheckedAt='fixture';Checks=$fixtureChecks;Message='fixture'})
    Assert ((@($window.FindName('InsightMetrics').ItemsSource | ForEach-Object Count) -join ',') -eq '5,1,2,1') 'Summary counts do not match the measured states'
    $window.FindName('InsightSearch').Text='rOuTe-eViDeNcE'
    Assert (@($window.FindName('InsightGroups').ItemsSource | ForEach-Object Items).Count -eq 1) 'Search failed on evidence or case folding'
    $window.FindName('InsightAttention').IsChecked=$true
    Assert ($window.FindName('InsightGroups').Items.Count -eq 0 -and $window.FindName('InsightEmpty').Visibility -eq 'Visible') 'Empty filtered state was not shown'
    $window.FindName('InsightSearch').Clear()
    Assert (@($window.FindName('InsightGroups').ItemsSource | ForEach-Object Items).Count -eq 3) 'Attention filter must include fail, warn and unknown only'
    $window.FindName('InsightAttention').IsChecked=$false
    Assert (@($window.FindName('InsightGroups').ItemsSource | ForEach-Object Items).Count -eq 5) 'Clearing filters did not restore all rows'
    Assert ($window.FindName('InsightEmpty').Visibility -eq 'Collapsed') 'Nonempty results retained the empty-state panel'
    Assert ($window.FindName('FingerprintTitle').Text -eq $fingerprintTitle) 'Network result overwrote fingerprint'
    Assert ($window.FindName('ReportList').Items.Count -eq 2) 'Reports did not load after callbacks'
    $entry=$window.FindName('ReportList').SelectedItem.Entry
    Assert ($entry.Report.Kind -eq 'Fingerprint') 'Report selection missing'
    $export=Join-Path $WorkRoot 'ui-export.md'
    Export-DiagnosticReport $entry.Report $export
    Assert (Test-Path -LiteralPath $export) 'UI selected report not exportable'
    Load-LatestReports
    Assert (@($window.FindName('FingerprintGroups').ItemsSource | ForEach-Object Items).Count -eq 26) 'Latest saved results did not reload'

    Show-Check ([pscustomobject]@{Deep=$true;CheckedAt='fixture';Checks=@([pscustomobject]@{Name='浏览器 WebRTC';State='unknown';Detail='没有候选地址，不能判为安全。'})})
    Assert ($window.FindName('WebRtcSummary').Text -match '^未验证' -and $window.FindName('BtnStart').IsEnabled) 'Empty WebRTC result was treated as safe or unlocked launch'
    $passed=[pscustomobject]@{Ready=$true;CheckedAt='2026-10-18 12:34:56';Checks=@([pscustomobject]@{Name='代理 HTTPS 出口';State='ok';Detail='fixture';Blocking=$false})}
    Show-Check $passed
    Assert ($window.FindName('BasicStamp').Text -eq $passed.CheckedAt) 'Measurement timestamp was replaced by display time'
    Assert $window.FindName('BtnStart').IsEnabled 'Current successful basic check did not unlock launch'
    Assert ($window.FindName('CardSummary').Text -match '已核对' -and @($window.FindName('TileDots').ItemsSource).Count -eq 1) 'Card summary did not follow the check result'
    Set-Busy $true
    Assert (-not $window.FindName('BtnStart').IsEnabled) 'Busy operation left launch enabled'
    Set-Busy $false
    Assert $window.FindName('BtnStart').IsEnabled 'Completed unrelated operation lost a valid gate'
    Show-Check ([pscustomobject]@{Ready=$false;Checks=@([pscustomobject]@{Name='代理';State='fail';Detail='fixture';Blocking=$true})})
    Assert $window.FindName('BtnStart').IsEnabled 'Read-only checks or notices locked launch: Failed check unlocked launch'
    Show-Check ([pscustomobject]@{Ready=$false;Checks=@([pscustomobject]@{Name='出口';State='unknown';Detail='fixture';Blocking=$true})})
    Assert $window.FindName('BtnStart').IsEnabled 'Read-only checks or notices locked launch: Unverified required check unlocked launch'
    Show-Check ([pscustomobject]@{Ready=$true;Checks=@()})
    Assert $window.FindName('BtnStart').IsEnabled 'Read-only checks or notices locked launch: Empty result unlocked launch'
    Show-Check $passed
    Show-Accounts ([pscustomobject]@{Current=$id;CurrentName='常用账号';Profiles=@($window.FindName('AccountList').ItemsSource)})
    Assert $window.FindName('BtnStart').IsEnabled 'Read-only checks or notices locked launch: Changed current account retained launch permission'
    Show-Check $passed
    . (Join-Path $package 'claude-switch.ps1') -StateRoot $StateRoot
    Save-DiagnosticReport $StateRoot $passed Basic | Out-Null
    Load-LatestReports
    Assert $window.FindName('BtnStart').IsEnabled 'Read-only checks or notices locked launch: Historical success unlocked launch'
    Assert ($window.FindName('BasicStamp').Text -match '历史记录') 'Historical basic result appeared current'
    $observations=@(
        [pscustomobject]@{Type='Egress';Provider='claude.ai';Route='Proxy';Family='IPv4';Hash=('a'*64);Address='8.8.8.8';Country='US';Milliseconds=10}
        [pscustomobject]@{Type='DNS';Provider='Fixture';Route='System';Family='IPv6';Hash=('b'*64);Address='2001:4860:4860::8888';Country='US';Geo='Fixture City';Organization='Fixture Org';Ecs=$true}
    )
    Show-Insights ([pscustomobject]@{Kind='Network';CheckedAt='fixture live';Checks=$fixtureChecks;Observations=@();LiveDetails=$observations})
    Assert (@($window.FindName('ClaudeEndpoints').ItemsSource | Where-Object Address -eq '8.8.8.8').Count -eq 1) 'Live domain address missing'
    Assert ($window.FindName('DnsResolvers').ItemsSource[0].Address -eq '2001:4860:4860::8888') 'IPv6 DNS address missing'
    Assert ($window.FindName('DnsResolvers').ItemsSource[0].Detail -match 'Fixture City' -and $window.FindName('DnsResolvers').ItemsSource[0].Label -eq '含 ECS') 'DNS geography or ECS indication lost'
    Show-Insights ([pscustomobject]@{Kind='Network';CheckedAt='fixture history';Checks=$fixtureChecks;Observations=@($observations | Select-Object Type,Provider,Route,Family,Hash,Country,Geo,Organization,Milliseconds,Ecs)})
    Assert (@($window.FindName('ClaudeEndpoints').ItemsSource | Where-Object Address -match '^摘要 ').Count -eq 1) 'Historical address shown as live'
    Assert ($window.FindName('AddressStamp').Text -match '历史记录') 'Historical network timestamp not labeled'


    # A loopback listener owned by this test fails the proxy-owner prerequisite. No real proxy is changed.
    $listener=New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback),0
    $listener.Start()
    try {
        Write-JsonAtomic (Join-Path $StateRoot 'settings.json') @{ProxyPort=$listener.LocalEndpoint.Port}
        Show-Check $passed
        $window.FindName('BtnCheck').RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
        Assert (-not $window.FindName('BtnStart').IsEnabled) 'Recheck did not immediately revoke launch'
        Wait-UiAction
        Assert ($window.FindName('BtnStart').ReadLocalValue([Windows.UIElement]::IsEnabledProperty)) 'Failed check retained a network launch lock'
        $animationDeadline=[DateTime]::UtcNow.AddSeconds(20)
        while ($script:hugPlaying -and [DateTime]::UtcNow -lt $animationDeadline) {
            $frame=New-Object Windows.Threading.DispatcherFrame
            [void]$window.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Background,[Action]{$frame.Continue=$false})
            [Windows.Threading.Dispatcher]::PushFrame($frame)
            Start-Sleep -Milliseconds 20
        }
        Assert (-not $script:hugPlaying -and $window.FindName('BtnStart').IsEnabled) 'Animation completion did not restore launch after a network warning'
        Assert ($window.FindName('StatusText').Text -match '仅作提醒') 'Real failed-check callback was not shown'
        Assert (@($window.FindName('Checks').ItemsSource | Where-Object {$_.Name -eq '代理 HTTPS 出口' -and $_.Detail -match '未发送外部请求'}).Count -eq 1) 'Isolated failure unexpectedly sent an external request'
        Assert ($script:hugPlaying -or $window.FindName('HugFinal').Opacity -eq 1) 'The hug did not start together with the check'
    } finally {$listener.Stop()}

    Click-LocalButton 'BtnEnvironmentRead'
    Assert ($window.FindName('TimezoneChoice').Items.Count -gt 1 -and $window.FindName('FormatChoice').Items.Count -gt 1) 'Real Windows choices did not load'
    foreach ($kind in @('Timezone','Format','Language')) {
        Assert (-not $window.FindName('Btn'+$kind+'Apply').IsEnabled) 'Unchanged setting can be applied'
    }
    $choice=$window.FindName('TimezoneChoice');$originalZone=$choice.SelectedValue
    $choice.SelectedIndex=if ($choice.SelectedIndex -eq 0) {1} else {0}
    Assert $window.FindName('BtnTimezoneApply').IsEnabled 'Changed choice cannot be applied'
    Assert ((Get-TimeZone).Id -eq $originalZone) 'Selecting a choice changed Windows without applying'
    Set-Busy $true
    Assert (-not $window.FindName('BtnTimezoneApply').IsEnabled) 'Busy state left environment apply enabled'
    Set-Busy $false
    $choice.SelectedValue=$originalZone
    Assert (-not (Test-Path (Join-Path $StateRoot 'environment-settings'))) 'Read or selection wrote a system-settings backup'
    $dnsPass=[pscustomobject]@{Kind='FlClash';CheckedAt='fixture current';Checks=@([pscustomobject]@{Name='严格路由';State='ok';Detail='fixture';Blocking=$false})}
    Show-FlClashCheck $dnsPass
    Assert $window.FindName('BtnStart').IsEnabled 'Read-only checks or notices locked launch: DNS-only pass unlocked launch'
    Show-Check $passed
    Show-FlClashCheck ([pscustomobject]@{Kind='FlClash';CheckedAt='fixture';Checks=@([pscustomobject]@{Name='严格路由';State='fail';Detail='fixture';Blocking=$true})})
    Assert $window.FindName('BtnStart').IsEnabled 'Read-only checks or notices locked launch: DNS blocker did not revoke readiness'
    Show-FlClashCheck $dnsPass $true
    Assert ($window.FindName('FlClashSummary').Text -match '^历史记录' -and $window.FindName('BtnStart').IsEnabled) 'History appeared current or unlocked launch'
    Click-LocalButton 'BtnFlClash'
    Assert ($window.FindName('FlClashChecks').Items.Count -gt 0 -and $window.FindName('FlClashSummary').Text -match '^本次检查') 'Real local-check callback missing'
    Assert (@($script:reports|Where-Object Kind -eq 'FlClash').Count -eq 1) 'DNS report did not use its own history kind'
    $script:browserRequests=@()
    function Open-DnsTestPage($Provider,$Owner,$StateRoot) {
        if ($Provider -eq 'IPCheck') {Assert ([object]::ReferenceEquals($Owner,$window) -and $StateRoot -eq (Join-Path $WorkRoot 'state')) 'IPCheck did not receive its owner and isolated state path'}
        $script:browserRequests+=$Provider
    }
    foreach ($button in @('BtnIpCheck','BtnDnsBrowserLeaks')) {$window.FindName($button).RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))}
    Assert (($script:browserRequests -join ',') -eq 'IPCheck,BrowserLeaks') 'Browser test buttons were not wired'
    Assert $window.FindName('BtnStart').IsEnabled 'Read-only checks or notices locked launch: Opening test links unlocked launch'
    $script:chromeRequests=@()
    function Open-ChromePage($Page) {$script:chromeRequests+=$Page}
    foreach ($button in @('BtnChromeLanguages','BtnChromeFonts','BtnChromeIpPure')) {
        Set-Busy $true
        Assert (-not $window.FindName($button).IsEnabled) 'Chrome settings stayed enabled during an operation'
        Set-Busy $false
        $window.FindName($button).RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
    }
    Assert (($script:chromeRequests -join ',') -eq 'Languages,Fonts,IpPure') 'Chrome settings buttons were not wired to their destinations'
    Assert $window.FindName('BtnStart').IsEnabled 'Read-only checks or notices locked launch: Opening Chrome settings unlocked launch'
    function Open-ChromePage($Page) {throw 'fixture: Chrome unavailable'}
    $window.FindName('BtnChromeFonts').RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
    Assert ($window.FindName('ChromeEnvironmentFeedback').Text -eq 'fixture: Chrome unavailable') 'Chrome launch failure was hidden'
    $china=[pscustomobject]@{Type='DNS';Provider='Fixture';Route='System';Family='IPv4';Hash=('c'*64);Address='8.8.8.8';Country='CN';Geo='Fixture';Organization='Fixture';Ecs=$false}
    Show-NetworkAddresses ([pscustomobject]@{CheckedAt='fixture';Checks=@();LiveDetails=@($china);Observations=@()})
    Assert ($window.FindName('DnsHeadline').Text -match '中国 1 个' -and $window.FindName('DnsResolvers').ItemsSource[0].Label -eq '中国 · 请核对') 'CN DNS observation was not visible'
    Show-Page 2
    $window.Content.Measure([Windows.Size]::new(1040,800));$window.Content.Arrange([Windows.Rect]::new(0,0,1040,800));$window.Content.UpdateLayout()
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(1560,1200,144,144,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($window.Content)
    $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream=[IO.File]::Create((Join-Path $WorkRoot 'flclash-ui-150.png'))
    try {$encoder.Save($stream)} finally {$stream.Dispose()}
    $script:hugPlaying=$true
    $script:hugMediaReady=$true
    $script:hugEndedAt=$null
    $hugMotion.Pause();$hugMotion.Position=[TimeSpan]::Zero;$hugClock.Reset()
    $script:hugLastPosition=0.0;$script:hugLastProgress=-6.0
    Set-HugUi 0
    Update-HugFrame
    Assert (-not $script:hugPlaying -and $window.FindName('HugCard').IsEnabled -and $window.FindName('HugFinal').Opacity -eq 1) 'Stalled video left the controls disabled'
    Assert ($window.FindName('Hint').Text -match '停滞') 'Stalled video did not explain the final-pose fallback'
    $remaining=@(Get-Process -Name Claude,FlClash,FlClashCore -ErrorAction SilentlyContinue | ForEach-Object Id)
    $lost=@($before | Where-Object { $_.Id -notin $remaining })
    Assert ($lost.Count -eq 0) ('A pre-existing Claude or proxy process exited: '+($lost.Id -join ', '))
    Assert (-not (Test-Path -LiteralPath (Join-Path $WorkRoot 'state\accounts'))) 'UI metadata actions copied account data'
    Assert (-not (Test-Path -LiteralPath (Join-Path $WorkRoot 'state\guard.json'))) 'UI metadata actions started a guard'
    [pscustomobject]@{Status='PASS';NetworkNoticesDoNotLockLaunch=$true;EnvironmentReadAndSelection=$true;ChromeSettingsAndRetest=$true;RegionalInformationIgnored=$true;RealFailedCheckCallback=$true;HistoryDoesNotLockLaunch=$true;AccountSelectionDoesNotLockLaunch=$true;SidebarNavigation=$true;NarrowLayout=$true;AccountModal=$true;LiveAddressAndRedactedHistory=$true;ProfileCount=3;UnicodeNames=$true;Rename=$true;CallbackRefresh=$true;FingerprintButtons=$true;SearchAndFilters=$true;SummaryCounts=$true;ExistingProcessesPreserved=$true;Preview=$outputPath;InsightsPreview=$insightsPreview} | ConvertTo-Json
} finally {
    $timer.Stop()
    $window.Close()
}
