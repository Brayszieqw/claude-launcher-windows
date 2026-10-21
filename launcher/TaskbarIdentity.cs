using System;
using System.IO;
using System.Runtime.InteropServices;

public static class TaskbarIdentity
{
    private const string AppId = "Local.ClaudeStartupAssistant";
    private static readonly Guid PropertyFormat = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");

    [StructLayout(LayoutKind.Sequential)]
    private struct PropertyKey { public Guid Format; public uint Id; }
    [StructLayout(LayoutKind.Sequential)]
    private struct PropertyValue
    {
        public ushort Type, Reserved1, Reserved2, Reserved3;
        public IntPtr Pointer;
        public int Tail;
    }
    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IPropertyStore
    {
        void GetCount(out uint count);
        void GetAt(uint index, out PropertyKey key);
        void GetValue(ref PropertyKey key, out PropertyValue value);
        void SetValue(ref PropertyKey key, ref PropertyValue value);
        void Commit();
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
    [DllImport("shell32.dll")]
    private static extern int SHGetPropertyStoreForWindow(IntPtr window, ref Guid iid, out IPropertyStore store);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int SHGetPropertyStoreFromParsingName(string path, IntPtr context, uint flags,
        ref Guid iid, out IPropertyStore store);

    public static void InitializeProcess()
    {
        Marshal.ThrowExceptionForHR(SetCurrentProcessExplicitAppUserModelID(AppId));
    }

    public static void ConfigureWindow(IntPtr window, string directory)
    {
        Guid iid = typeof(IPropertyStore).GUID;
        IPropertyStore store;
        Marshal.ThrowExceptionForHR(SHGetPropertyStoreForWindow(window, ref iid, out store));
        try
        {
            SetString(store, 2, "\"" + Path.Combine(directory, "ClaudeLauncher.exe") + "\"");
            SetString(store, 3, Path.Combine(directory, "launcher.ico") + ",0");
            SetString(store, 4, "Claude 启动助手");
            // Set the identity last: this notifies the taskbar to refresh the relaunch properties.
            SetString(store, 5, AppId);
        }
        finally { Marshal.ReleaseComObject(store); }
    }

    public static void ClearWindow(IntPtr window)
    {
        Guid iid = typeof(IPropertyStore).GUID;
        IPropertyStore store;
        Marshal.ThrowExceptionForHR(SHGetPropertyStoreForWindow(window, ref iid, out store));
        try
        {
            // Window property storage must be released before the native window is destroyed.
            for (uint id = 2; id <= 5; id++) SetString(store, id, null);
        }
        finally { Marshal.ReleaseComObject(store); }
    }

    public static void ConfigureShortcut(string path)
    {
        Guid iid = typeof(IPropertyStore).GUID;
        IPropertyStore store;
        Marshal.ThrowExceptionForHR(SHGetPropertyStoreFromParsingName(path, IntPtr.Zero, 2, ref iid, out store));
        try
        {
            SetString(store, 5, AppId);
            store.Commit();
        }
        finally { Marshal.ReleaseComObject(store); }
    }

    private static void SetString(IPropertyStore store, uint id, string text)
    {
        var key = new PropertyKey { Format = PropertyFormat, Id = id };
        var value = new PropertyValue();
        if (text != null)
        {
            value.Type = 31;
            value.Pointer = Marshal.StringToCoTaskMemUni(text);
        }
        try { store.SetValue(ref key, ref value); }
        finally { Marshal.FreeCoTaskMem(value.Pointer); }
    }
}
