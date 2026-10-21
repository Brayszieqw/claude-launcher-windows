using System;
using System.IO;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("Claude 启动助手")]
[assembly: AssemblyDescription("Windows · FlClash · Claude Desktop")]
[assembly: AssemblyProduct("Claude 启动助手")]
[assembly: AssemblyVersion("1.1.0.0")]
[assembly: AssemblyFileVersion("1.1.0.0")]

public static class Launcher
{
    private static EventWaitHandle showRequest;
    public static bool ConsumeShowRequest() { return showRequest != null && showRequest.WaitOne(0); }

    [STAThread]
    private static int Main(string[] args)
    {
        bool created;
        string mutexName = @"Local\ClaudeLauncherWindows-" + WindowsIdentity.GetCurrent().User.Value;
        showRequest = new EventWaitHandle(false, EventResetMode.AutoReset, mutexName + "-Show");
        using (var mutex = new Mutex(true, mutexName, out created))
        {
            if (!created)
            {
                showRequest.Set();
                return 0;
            }
            try
            {
                TaskbarIdentity.InitializeProcess();
                string directory = AppDomain.CurrentDomain.BaseDirectory;
                string script = Path.Combine(directory, "SwitcherUI.ps1");
                if (!File.Exists(script))
                    throw new FileNotFoundException("缺少界面文件，请完整解压程序目录。", script);

                Environment.CurrentDirectory = directory;
                var initialState = InitialSessionState.CreateDefault();
                // Only this application's runspace accepts the bundled scripts.
                initialState.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
                using (var runspace = RunspaceFactory.CreateRunspace(initialState))
                using (var shell = PowerShell.Create())
                {
                    runspace.ApartmentState = ApartmentState.STA;
                    runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
                    runspace.Open();
                    shell.Runspace = runspace;
                    shell.AddCommand(script);
                    if (args.Contains("--tray")) shell.AddParameter("StartHidden");
                    shell.Invoke();
                    // HadErrors is also true for cmdlet errors the script caught or silenced, which leave the error
                    // stream empty; that used to show a blank box. Only real records count, and the window has closed.
                    if (shell.Streams.Error.Count > 0)
                        WriteErrorLog(shell.Streams.Error.Select(error => error.ToString()).ToArray());
                }
                return 0;
            }
            catch (Exception error)
            {
                MessageBox.Show("启动助手未能运行：" + Environment.NewLine + error.Message,
                    "Claude 启动助手", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
            finally
            {
                mutex.ReleaseMutex();
                showRequest.Dispose();
            }
        }
    }

    private static void WriteErrorLog(string[] errors)
    {
        try
        {
            // Same state folder as SwitcherUI.ps1, which also follows %LOCALAPPDATA%.
            string root = Environment.GetEnvironmentVariable("LOCALAPPDATA");
            if (string.IsNullOrEmpty(root))
                root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string directory = Path.Combine(root, "ClaudeSwitcherWindows");
            Directory.CreateDirectory(directory);
            File.AppendAllText(Path.Combine(directory, "launcher-errors.log"),
                DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + Environment.NewLine +
                string.Join(Environment.NewLine, errors) + Environment.NewLine + Environment.NewLine,
                new UTF8Encoding(true));
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
}
