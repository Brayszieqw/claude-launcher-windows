param(
    [string]$Package = (Split-Path -Parent $PSScriptRoot),
    [string]$WorkRoot = (Join-Path $env:TEMP ('ClaudeWindowTests-'+[guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference='Stop'
[void](New-Item -ItemType Directory -Path $WorkRoot -Force)
$before=@(Get-Process -Name Claude,FlClash,FlClashCore -ErrorAction SilentlyContinue | ForEach-Object Id)
$text=[IO.File]::ReadAllText((Join-Path $Package 'SwitcherUI.ps1'))
$text=$text -replace '(?m)^\[void\]\$window\.ShowDialog\(\)\s*$',''
# Exercise a real HWND without startup reads, network probes or the user's state directory.
$text=$text -replace '(?ms)^\$window\.Add_ContentRendered\(\{.*?^\}\)\r?\n',''
$text=$text.Replace('$PSScriptRoot', ("'"+$Package.Replace("'","''")+"'"))
. ([scriptblock]::Create($text)) -StateRoot (Join-Path $WorkRoot 'state')
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class WindowSmokeNative {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hwnd, int index);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hwnd);
}
'@
$results=New-Object System.Collections.Generic.List[object]
function Assert($Condition,$Message) {if (-not $Condition) {throw $Message}}
function Test-Case($Name,[scriptblock]$Body) {
    try {& $Body;$results.Add([pscustomobject]@{Name=$Name;Status='PASS';Detail=''})}
    catch {$results.Add([pscustomobject]@{Name=$Name;Status='FAIL';Detail=$_.Exception.Message})}
}
function Pump-Window {
    $frame=New-Object Windows.Threading.DispatcherFrame
    [void]$window.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::ApplicationIdle,[Action]{$frame.Continue=$false})
    [Windows.Threading.Dispatcher]::PushFrame($frame)
}
function Wait-WindowState($State) {
    $deadline=[DateTime]::UtcNow.AddSeconds(3)
    do {Pump-Window} while ($window.WindowState -ne $State -and [DateTime]::UtcNow -lt $deadline)
    Assert ($window.WindowState -eq $State) ('Window state did not become '+$State)
}
function Get-WindowRect {
    $rect=New-Object WindowSmokeNative+RECT
    Assert ([WindowSmokeNative]::GetWindowRect($handle,[ref]$rect)) 'Cannot read test window bounds'
    $rect
}
try {
    $window.ShowActivated=$false
    $window.ShowInTaskbar=$false
    $window.Show()
    Pump-Window
    $handle=(New-Object Windows.Interop.WindowInteropHelper $window).Handle
    $area=[Windows.Forms.Screen]::FromHandle($handle).WorkingArea
    $initial=Get-WindowRect
    $normalWidth=$window.Width;$normalHeight=$window.Height
    Test-Case 'Overview is visible on first render without navigation' {
        $overview=$window.FindName('PageOverview')
        Assert ([object]::ReferenceEquals($window.FindName('MainTabs').SelectedContent,$overview)) 'Fresh window did not select the overview'
        Assert ($overview.IsVisible -and $overview.ActualWidth -gt 0 -and $overview.ActualHeight -gt 0) 'Initial overview has no visible content area'
    }
    Test-Case 'Title bar and entire initial window fit the monitor work area' {
        Assert ($initial.Top -ge $area.Top -and $initial.Left -ge $area.Left -and $initial.Right -le $area.Right -and $initial.Bottom -le $area.Bottom) ('Window bounds '+($initial | ConvertTo-Json -Compress)+' exceed work area '+$area)
    }
    Test-Case 'Native minimize, maximize, close and resize frame are enabled' {
        $style=[WindowSmokeNative]::GetWindowLong($handle,-16)
        foreach ($flag in @(0xC00000,0x80000,0x20000,0x10000,0x40000)) {Assert (($style -band $flag) -eq $flag) ('Missing native window style '+$flag)}
    }
    Test-Case 'Native minimize and restore retain normal size' {
        [Windows.SystemCommands]::MinimizeWindow($window)
        Wait-WindowState Minimized
        [Windows.SystemCommands]::RestoreWindow($window)
        Wait-WindowState Normal
        Assert ([Math]::Abs($window.ActualWidth-$normalWidth) -lt 2 -and [Math]::Abs($window.ActualHeight-$normalHeight) -lt 2) 'Restore lost normal size'
    }
    Test-Case 'Native maximize fills the work area and restores' {
        [Windows.SystemCommands]::MaximizeWindow($window)
        Wait-WindowState Maximized
        $maximized=Get-WindowRect
        $edge=20*[WindowSmokeNative]::GetDpiForWindow($handle)/96
        Assert ([Math]::Abs($maximized.Top-$area.Top) -le $edge -and [Math]::Abs($maximized.Bottom-$area.Bottom) -le $edge) 'Maximize ignored monitor work area'
        [Windows.SystemCommands]::RestoreWindow($window)
        Wait-WindowState Normal
        Assert ([Math]::Abs($window.Width-$normalWidth) -lt 2 -and [Math]::Abs($window.Height-$normalHeight) -lt 2) 'Maximize/restore changed normal bounds'
    }
    Test-Case 'Normal window can move and resize without losing the title bar' {
        $oldLeft=$window.Left;$oldTop=$window.Top
        $window.Width-=32;$window.Height=[Math]::Max($window.MinHeight,$window.Height-32)
        $window.Left+=8;$window.Top+=8
        Pump-Window
        Assert ([Math]::Abs($window.ActualWidth-($normalWidth-32)) -lt 2) 'Resize did not change native width'
        Assert ($window.Left -gt $oldLeft -and $window.Top -gt $oldTop) 'Window position cannot change'
        $rect=Get-WindowRect
        Assert ($rect.Top -ge $area.Top -and $rect.Bottom -le $area.Bottom) 'Moved window lost visible title bar or overlapped the taskbar'
    }
    Test-Case 'Close waits while a protected operation is active' {
        $script:operation=[pscustomobject]@{Test=$true}
        [Windows.SystemCommands]::CloseWindow($window)
        Pump-Window
        Assert ($window.IsVisible -and $window.FindName('Hint').Text -match '操作尚未完成') 'Close interrupted the active operation'
        $script:operation=$null
    }
    Test-Case 'Tray close keeps the window and guard UI alive; reopen restores it' {
        function Set-GuardAutostart {$script:startupRegistered=$true}
        Initialize-GuardTray
        Assert ($script:startupRegistered -and $script:tray.Visible) 'Tray or startup registration missing'
        $script:operation=$null
        [Windows.SystemCommands]::CloseWindow($window)
        Pump-Window
        Assert ($window.WindowState -eq 'Minimized' -and -not $window.ShowInTaskbar) 'Close did not minimize to tray'
        Show-GuardWindow
        Pump-Window
        Assert ($window.WindowState -eq 'Normal' -and $window.ShowInTaskbar) 'Tray reopen failed'
    }
    Test-Case 'Fourth network entry, overview and tray open the same monitor panel' {
        $entry=$window.FindName('BtnGuardMonitor')
        Assert ($entry.Parent.Children[3] -eq $entry) 'Monitor is not the fourth network entry'
        $window.FindName('BtnHomeGuard').RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
        Pump-Window
        Assert ($window.FindName('MainTabs').SelectedIndex -eq 2 -and $window.FindName('GuardPanel').IsVisible) 'Overview monitor entry did not open the panel'
        $window.FindName('BtnGuardClose').RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
        Assert ($window.FindName('GuardPanel').Visibility -eq 'Collapsed') 'Monitor did not collapse'
        $entry.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
        Assert ($window.FindName('GuardPanel').Visibility -eq 'Visible') 'Network monitor entry did not open'
        Show-Page 0
        $script:tray.ContextMenuStrip.Items[1].PerformClick()
        Assert ($window.FindName('MainTabs').SelectedIndex -eq 2) 'Tray monitor entry did not navigate'
    }
    Test-Case 'Monitor shows warnings and recovery without lock controls' {
        $state=[pscustomobject]@{Phase='警报';AlertKind='Network';Reason='fixture network warning';CheckedAt=[DateTime]::UtcNow.ToString('o');Revision='fixture'}
        Show-GuardState $state '全时段守护 · 警报'
        Assert ($window.FindName('GuardTitle').Text -match '提醒' -and $window.FindName('BtnGuardCheck').Content -eq '立即重新检查') 'Warning or recheck action missing'
        Assert ($window.FindName('GuardSummary').Text -eq $state.Reason -and $window.FindName('BtnStart').IsEnabled) 'Warning hid its cause or locked launch'
        $state.Phase='重新检查'
        Show-GuardState $state '全时段守护 · 重新检查'
        Assert (-not $window.FindName('BtnGuardCheck').IsEnabled) 'Checking allowed duplicate manual requests'
        $state.Phase='守护中';$state.AlertKind=''
        Show-GuardState $state '全时段守护 · 守护中'
        Assert ($window.FindName('GuardTitle').Text -eq '监测正常' -and $window.FindName('BtnGuardCheck').IsEnabled) 'Healthy state not restored'
        Show-GuardState $state '全时段守护状态不可读'
        Assert (-not $window.FindName('BtnGuardCheck').IsEnabled -and $window.FindName('GuardTitle').Text -ne '监测正常') 'Unreadable state displayed as healthy'
    }
    Test-Case 'Alert is a single nonmodal window that does not activate Claude or the main page' {
        $page=$window.FindName('MainTabs').SelectedIndex
        $active=$window.IsActive
        Show-GuardAlert '界面测试：网络提醒，当前 Claude 保持运行。'
        Pump-Window
        $first=$script:guardAlert
        Assert ($first.IsVisible -and -not $first.ShowActivated -and $first.Topmost -and -not $first.ShowInTaskbar) 'Alert visibility or focus policy is wrong'
        Assert ($window.IsActive -eq $active -and $window.FindName('MainTabs').SelectedIndex -eq $page) 'Alert took focus or changed the current page'
        Show-GuardAlert '界面测试：持续异常，再次提醒。'
        Assert ([object]::ReferenceEquals($first,$script:guardAlert)) 'Repeated warning stacked another window'
        $script:guardAlert.FindName('AlertLater').RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
        Assert (-not $script:guardAlert -and ($script:nextGuardAlert-[DateTime]::UtcNow).TotalSeconds -gt 58) 'Dismissal did not defer the next reminder by one minute'
    }
    $previewState=[pscustomobject]@{Phase='警报';AlertKind='Network';Reason='演示状态：代理连接中断，只作提醒，Claude 继续运行。';CheckedAt=[DateTime]::UtcNow.ToString('o');Revision='fixture'}
    Show-GuardState $previewState '全时段守护 · 警报'
    $window.UpdateLayout()
    $visual=$window.Content
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$visual.ActualWidth,[int]$visual.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $preview=Join-Path $WorkRoot 'guard-ui.png'
    $stream=[IO.File]::Create($preview)
    try {$encoder.Save($stream)} finally {$stream.Dispose()}
    Test-Case 'Explicit interface exit closes an idle window' {
        $script:operation=$null
        $script:exitInterface=$true
        [Windows.SystemCommands]::CloseWindow($window)
        Pump-Window
        Assert (-not $window.IsVisible) 'Native close left the window open'
    }
    Test-Case 'Window checks preserve Claude, FlClash and user state' {
        $after=@(Get-Process -Name Claude,FlClash,FlClashCore -ErrorAction SilentlyContinue | ForEach-Object Id)
        Assert (@($before | Where-Object {$_ -notin $after}).Count -eq 0) 'An existing application process exited'
        Assert (-not (Test-Path (Join-Path $WorkRoot 'state'))) 'Window checks wrote application state'
    }
    [pscustomobject]@{InitialBounds=$initial;WorkArea=$area;Tests=$results.ToArray();GuardPreview=$preview} | ConvertTo-Json -Depth 5
    if (@($results | Where-Object Status -eq 'FAIL').Count) {exit 1}
} finally {
    $script:operation=$null
    $script:exitInterface=$true
    $timer.Stop()
    if ($window.IsVisible) {$window.Close()}
}
