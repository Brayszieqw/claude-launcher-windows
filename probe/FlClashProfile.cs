using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

public static class FlClashProfile
{
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_open_v2(byte[] path, out IntPtr db, int flags, IntPtr vfs);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_prepare_v2(IntPtr db, byte[] sql, int length, out IntPtr statement, IntPtr tail);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_bind_int64(IntPtr statement, int index, long value);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_step(IntPtr statement);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr sqlite3_column_text(IntPtr statement, int index);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_finalize(IntPtr statement);
    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_close(IntPtr db);

    public static string[] Read(string path, long profileId)
    {
        if (!File.Exists(path)) throw new IOException("FlClash profile database is unavailable.");
        IntPtr db = IntPtr.Zero, statement = IntPtr.Zero;
        try
        {
            // SQLITE_OPEN_READONLY: never migrate or change the user's profile database.
            Check(sqlite3_open_v2(Encoding.UTF8.GetBytes(path + "\0"), out db, 1, IntPtr.Zero));
            byte[] sql = Encoding.UTF8.GetBytes("SELECT extend_type, CAST(script_id AS TEXT), " +
                "CASE WHEN EXISTS(SELECT 1 FROM scripts WHERE scripts.id=profiles.script_id) THEN '1' ELSE '0' END " +
                "FROM profiles WHERE id=?\0");
            Check(sqlite3_prepare_v2(db, sql, sql.Length, out statement, IntPtr.Zero));
            Check(sqlite3_bind_int64(statement, 1, profileId));
            int result = sqlite3_step(statement);
            if (result == 101) throw new IOException("The selected FlClash profile was not found.");
            if (result != 100) throw new IOException("FlClash profile query is unavailable (" + result + ").");
            // These columns contain only enum names, decimal IDs and a boolean, never subscription credentials.
            return new[] { Marshal.PtrToStringAnsi(sqlite3_column_text(statement, 0)),
                Marshal.PtrToStringAnsi(sqlite3_column_text(statement, 1)),
                Marshal.PtrToStringAnsi(sqlite3_column_text(statement, 2)) };
        }
        finally
        {
            if (statement != IntPtr.Zero) sqlite3_finalize(statement);
            if (db != IntPtr.Zero) sqlite3_close(db);
        }
    }

    private static void Check(int result)
    {
        if (result != 0) throw new IOException("FlClash profile read is unavailable (" + result + ").");
    }
}
