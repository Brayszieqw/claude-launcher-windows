using System;
using System.Runtime.InteropServices;

public static class TaskbarProbe
{
    [StructLayout(LayoutKind.Sequential)]
    private struct Key { public Guid Format; public uint Id; }
    [StructLayout(LayoutKind.Sequential)]
    private struct Value { public ushort Type, Reserved1, Reserved2, Reserved3; public IntPtr Pointer; public int Tail; }
    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface Store
    {
        void GetCount(out uint count);
        void GetAt(uint index, out Key key);
        void GetValue(ref Key key, out Value value);
    }
    [DllImport("shell32.dll")]
    private static extern int SHGetPropertyStoreForWindow(IntPtr window, ref Guid iid, out Store store);
    [DllImport("shell32.dll")]
    private static extern int GetCurrentProcessExplicitAppUserModelID(out IntPtr value);
    [DllImport("ole32.dll")]
    private static extern int PropVariantClear(ref Value value);

    public static string ReadWindow(IntPtr window, uint id)
    {
        Guid iid = typeof(Store).GUID;
        Store store;
        Marshal.ThrowExceptionForHR(SHGetPropertyStoreForWindow(window, ref iid, out store));
        try
        {
            var key = new Key { Format = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), Id = id };
            Value value;
            store.GetValue(ref key, out value);
            try
            {
                if (value.Type == 0) return "";
                if (value.Type != 31) throw new InvalidOperationException("Expected a string property");
                return Marshal.PtrToStringUni(value.Pointer);
            }
            finally { Marshal.ThrowExceptionForHR(PropVariantClear(ref value)); }
        }
        finally { Marshal.ReleaseComObject(store); }
    }

    public static string ReadProcess()
    {
        IntPtr value;
        int result = GetCurrentProcessExplicitAppUserModelID(out value);
        if (result == unchecked((int)0x80004005)) return "";
        Marshal.ThrowExceptionForHR(result);
        try { return Marshal.PtrToStringUni(value); }
        finally { Marshal.FreeCoTaskMem(value); }
    }
}
