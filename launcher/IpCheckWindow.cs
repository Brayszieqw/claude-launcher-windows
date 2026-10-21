using System;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

public sealed class IpCheckWindow : Window
{
    private static IpCheckWindow current;
    private readonly WebView2 browser;
    private readonly TextBlock status;
    private bool closed;

    public static IpCheckWindow Open(Window owner, string stateRoot, string packageRoot)
    {
        if (current != null)
        {
            if (current.WindowState == WindowState.Minimized) current.WindowState = WindowState.Normal;
            current.Activate();
            return current;
        }
        current = new IpCheckWindow(owner, stateRoot, packageRoot);
        current.Show();
        return current;
    }

    private IpCheckWindow(Window owner, string stateRoot, string packageRoot)
    {
        Owner = owner;
        Icon = owner.Icon;
        Title = "Claude 启动助手 · IPCheck 深度 DNS";
        Width = Math.Min(1200, SystemParameters.WorkArea.Width);
        Height = Math.Min(860, SystemParameters.WorkArea.Height);
        MinWidth = 760;
        MinHeight = 560;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = new SolidColorBrush(Color.FromRgb(43, 31, 26));
        Foreground = new SolidColorBrush(Color.FromRgb(255, 241, 219));
        FontFamily = new FontFamily("Microsoft YaHei UI");
        var layout = new DockPanel();
        var header = new DockPanel { Margin = new Thickness(20, 12, 20, 12) };
        var refresh = new Button { Content = "重新加载", Padding = new Thickness(14, 6, 14, 6), Margin = new Thickness(16, 0, 0, 0) };
        refresh.Style = owner.TryFindResource("GhostButton") as Style;
        DockPanel.SetDock(refresh, Dock.Right);
        header.Children.Add(refresh);
        var labels = new StackPanel();
        labels.Children.Add(new TextBlock { Text = "IPCheck 深度 DNS", FontSize = 17, FontWeight = FontWeights.SemiBold });
        status = new TextBlock { Text = "正在加载 ipcheck.ing…", Margin = new Thickness(0, 5, 0, 0), Foreground = new SolidColorBrush(Color.FromRgb(205, 179, 155)), TextWrapping = TextWrapping.Wrap };
        labels.Children.Add(status);
        header.Children.Add(labels);
        DockPanel.SetDock(header, Dock.Top);
        layout.Children.Add(header);
        browser = new WebView2 { Name = "IpCheckBrowser", DefaultBackgroundColor = System.Drawing.Color.FromArgb(255, 43, 31, 26) };
        NameScope.SetNameScope(this, new NameScope());
        RegisterName(browser.Name, browser);
        RegisterName("IpCheckStatus", status);
        layout.Children.Add(browser);
        Content = layout;
        refresh.Click += delegate { if (browser.CoreWebView2 != null) browser.Reload(); };
        Loaded += async delegate { await Initialize(stateRoot, packageRoot); };
        Closed += delegate { closed = true; browser.Dispose(); current = null; };
    }

    private async Task Initialize(string stateRoot, string packageRoot)
    {
        try
        {
            var environment = await CoreWebView2Environment.CreateAsync(null, Path.Combine(stateRoot, "ipcheck-webview"));
            if (closed) return;
            await browser.EnsureCoreWebView2Async(environment);
            if (closed) return;
            browser.CoreWebView2.Settings.AreHostObjectsAllowed = false;
            browser.CoreWebView2.Settings.IsWebMessageEnabled = false;
            string artwork = Path.Combine(packageRoot, "assets", "hug");
            if (Directory.Exists(artwork))
                browser.CoreWebView2.SetVirtualHostNameToFolderMapping("claude-assets.local", artwork, CoreWebView2HostResourceAccessKind.DenyCors);
            await browser.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(File.ReadAllText(Path.Combine(packageRoot, "probe", "ipcheck-theme.js")));
            if (closed) return;
            browser.NavigationCompleted += delegate(object sender, CoreWebView2NavigationCompletedEventArgs e)
            {
                status.Text = e.IsSuccess
                    ? "原站 ipcheck.ing · 首次使用请在页面内登录 · 此处测量助手内嵌浏览器的 DNS 路径"
                    : "页面加载失败：" + e.WebErrorStatus + "。请检查网络后点击重新加载。";
            };
            browser.CoreWebView2.Navigate("https://ipcheck.ing/tools/enhanceddnsleaktest");
        }
        catch (Exception error)
        {
            if (!closed) status.Text = "内嵌页面无法启动：" + error.Message + "。关闭此窗口后重试。";
        }
    }
}
