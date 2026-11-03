// =====================================================================
//  Anh 7 Dock — các hàm gọi Windows (C#, được PowerShell biên dịch lúc chạy)
//  - Liệt kê cửa sổ ứng dụng đang mở (giống thanh tác vụ)
//  - Bật/thu nhỏ cửa sổ, gửi phím tắt Windows (Start, Tìm kiếm...)
//  - Ẩn/hiện thanh tác vụ Windows, đăng ký Dock là "AppBar" để cửa sổ phóng to không che Dock
// =====================================================================
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Threading;
using System.Runtime.InteropServices;
using System.Text;

namespace Anh7Dock
{
    public class WinInfo
    {
        public IntPtr Handle;
        public string Title;
        public int Pid;
        public string Path;
        public bool Minimized;
    }

    public static class Native
    {
        // ---------------- user32 / dwmapi / kernel32 ----------------
        delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
        [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hWnd);
        [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr hWnd, uint cmd);
        [DllImport("user32.dll", EntryPoint = "GetWindowLongW")] static extern int GetWindowLong(IntPtr hWnd, int index);
        [DllImport("user32.dll", EntryPoint = "SetWindowLongW")] static extern int SetWindowLong(IntPtr hWnd, int index, int value);
        [DllImport("user32.dll")] static extern bool PostMessageW(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowTextW(IntPtr hWnd, StringBuilder sb, int max);
        [DllImport("user32.dll")] static extern int GetWindowTextLengthW(IntPtr hWnd);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassNameW(IntPtr hWnd, StringBuilder sb, int max);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out int pid);
        [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int cmd);
        [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindowW(string cls, string title);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindowExW(IntPtr parent, IntPtr after, string cls, string title);
        [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
        [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr hWnd, int attr, out int value, int size);
        [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool QueryFullProcessImageNameW(IntPtr h, int flags, StringBuilder sb, ref int size);

        const uint GW_OWNER = 4;
        const int GWL_EXSTYLE = -20;
        const int WS_EX_TOOLWINDOW = 0x80;
        const int WS_EX_NOACTIVATE = 0x08000000;
        const int DWMWA_CLOAKED = 14;
        const int SW_HIDE = 0, SW_SHOWNA = 8, SW_MINIMIZE = 6, SW_RESTORE = 9;
        const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
        const uint KEYEVENTF_KEYUP = 2;

        static string Text(IntPtr h)
        {
            int n = GetWindowTextLengthW(h);
            if (n <= 0) return "";
            var sb = new StringBuilder(n + 1);
            GetWindowTextW(h, sb, sb.Capacity);
            return sb.ToString();
        }

        static string ClassName(IntPtr h)
        {
            var sb = new StringBuilder(256);
            GetClassNameW(h, sb, sb.Capacity);
            return sb.ToString();
        }

        public static string ProcessPath(int pid)
        {
            IntPtr h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
            if (h == IntPtr.Zero) return "";
            try
            {
                var sb = new StringBuilder(1024);
                int size = sb.Capacity;
                return QueryFullProcessImageNameW(h, 0, sb, ref size) ? sb.ToString() : "";
            }
            finally { CloseHandle(h); }
        }

        // Cửa sổ ứng dụng giống những gì thanh tác vụ Windows hiển thị
        public static List<WinInfo> AppWindows(int skipPid)
        {
            var list = new List<WinInfo>();
            EnumWindows(delegate (IntPtr h, IntPtr l)
            {
                if (!IsWindowVisible(h)) return true;
                if (GetWindow(h, GW_OWNER) != IntPtr.Zero) return true;
                int ex = GetWindowLong(h, GWL_EXSTYLE);
                if ((ex & WS_EX_TOOLWINDOW) != 0 || (ex & WS_EX_NOACTIVATE) != 0) return true;
                int cloaked;
                if (DwmGetWindowAttribute(h, DWMWA_CLOAKED, out cloaked, 4) == 0 && cloaked != 0) return true;
                string title = Text(h);
                if (title.Length == 0) return true;
                string cls = ClassName(h);
                if (cls == "Progman" || cls == "WorkerW" || cls == "Shell_TrayWnd" || cls == "Shell_SecondaryTrayWnd") return true;
                int pid;
                GetWindowThreadProcessId(h, out pid);
                if (pid == skipPid) return true;
                list.Add(new WinInfo { Handle = h, Title = title, Pid = pid, Path = ProcessPath(pid), Minimized = IsIconic(h) });
                return true;
            }, IntPtr.Zero);
            return list;
        }

        // Bấm vào app trên Dock: đang ở trước -> thu nhỏ; còn lại -> đưa lên trước
        public static void ToggleWindow(IntPtr h)
        {
            if (GetForegroundWindow() == h && !IsIconic(h)) { ShowWindow(h, SW_MINIMIZE); return; }
            if (IsIconic(h)) ShowWindow(h, SW_RESTORE);
            // Mẹo nhấn-nhả Alt để Windows cho phép đổi cửa sổ trước
            keybd_event(0x12, 0, 0, UIntPtr.Zero);
            keybd_event(0x12, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            SetForegroundWindow(h);
        }

        // Đưa cửa sổ lên trước (không thu nhỏ nếu nó đang ở trước)
        public static void BringToFront(IntPtr h)
        {
            if (IsIconic(h)) ShowWindow(h, SW_RESTORE);
            keybd_event(0x12, 0, 0, UIntPtr.Zero);
            keybd_event(0x12, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            SetForegroundWindow(h);
        }

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern int SHEmptyRecycleBinW(IntPtr hwnd, string root, uint flags);
        // Dọn sạch Thùng rác mọi ổ (không hỏi lại: Tệp Anh 7 đã hỏi trước)
        public static int EmptyRecycleBin(IntPtr owner) { return SHEmptyRecycleBinW(owner, null, 1 | 2); }

        // Đóng cửa sổ như bấm nút X (app vẫn có thể hỏi lưu file)
        public static void CloseWindow(IntPtr h) { PostMessageW(h, 0x0010, IntPtr.Zero, IntPtr.Zero); }

        // Dock không "cướp" focus khi bấm, không hiện trong Alt+Tab
        public static void MakeDockWindow(IntPtr h)
        {
            int ex = GetWindowLong(h, GWL_EXSTYLE);
            SetWindowLong(h, GWL_EXSTYLE, ex | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW);
        }

        // Gửi tổ hợp phím, vd Keys(0x5B) = phím Windows, Keys(0x5B, 0x53) = Win+S
        public static void Keys(params byte[] vks)
        {
            foreach (var k in vks) keybd_event(k, 0, 0, UIntPtr.Zero);
            for (int i = vks.Length - 1; i >= 0; i--) keybd_event(vks[i], 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
        }

        // ---------------- Thanh tác vụ Windows ----------------
        [StructLayout(LayoutKind.Sequential)]
        public struct RECT { public int Left, Top, Right, Bottom; }

        [StructLayout(LayoutKind.Sequential)]
        struct APPBARDATA
        {
            public int cbSize;
            public IntPtr hWnd;
            public uint uCallbackMessage;
            public uint uEdge;
            public RECT rc;
            public IntPtr lParam;
        }
        [DllImport("shell32.dll")] static extern UIntPtr SHAppBarMessage(uint msg, ref APPBARDATA data);
        const uint ABM_NEW = 0, ABM_REMOVE = 1, ABM_QUERYPOS = 2, ABM_SETPOS = 3, ABM_GETSTATE = 4, ABM_SETSTATE = 10;
        const uint ABE_BOTTOM = 3;
        const int ABS_AUTOHIDE = 1, ABS_ALWAYSONTOP = 2;

        static List<IntPtr> TaskbarWindows()
        {
            var list = new List<IntPtr>();
            IntPtr main = FindWindowW("Shell_TrayWnd", null);
            if (main != IntPtr.Zero) list.Add(main);
            IntPtr sec = IntPtr.Zero;
            while ((sec = FindWindowExW(IntPtr.Zero, sec, "Shell_SecondaryTrayWnd", null)) != IntPtr.Zero) list.Add(sec);
            return list;
        }

        public static int GetTaskbarState()
        {
            var d = new APPBARDATA();
            d.cbSize = Marshal.SizeOf(typeof(APPBARDATA));
            return (int)SHAppBarMessage(ABM_GETSTATE, ref d).ToUInt32();
        }

        public static void SetTaskbarAutoHide(bool on)
        {
            var d = new APPBARDATA();
            d.cbSize = Marshal.SizeOf(typeof(APPBARDATA));
            d.hWnd = FindWindowW("Shell_TrayWnd", null);
            d.lParam = (IntPtr)(on ? ABS_AUTOHIDE : ABS_ALWAYSONTOP);
            SHAppBarMessage(ABM_SETSTATE, ref d);
        }

        // Ẩn thanh tác vụ Windows (trả về true nếu nó đang hiện và vừa bị ẩn)
        public static bool HideTaskbar()
        {
            bool changed = false;
            foreach (var h in TaskbarWindows())
                if (IsWindowVisible(h)) { ShowWindow(h, SW_HIDE); changed = true; }
            return changed;
        }

        public static void ShowTaskbar()
        {
            foreach (var h in TaskbarWindows()) ShowWindow(h, SW_SHOWNA);
        }

        // Menu Start / Tìm kiếm của Windows đang mở? (khi đó không ẩn thanh tác vụ)
        public static bool ShellPopupOpen()
        {
            IntPtr fg = GetForegroundWindow();
            if (fg == IntPtr.Zero) return false;
            int pid;
            GetWindowThreadProcessId(fg, out pid);
            string p = ProcessPath(pid).ToLowerInvariant();
            return p.EndsWith("startmenuexperiencehost.exe") || p.EndsWith("searchhost.exe")
                || p.EndsWith("searchapp.exe") || p.EndsWith("shellexperiencehost.exe");
        }

        // ---------------- Dock là AppBar ở cạnh dưới ----------------
        public static void RegisterAppBar(IntPtr dock, uint callbackMsg)
        {
            var d = new APPBARDATA();
            d.cbSize = Marshal.SizeOf(typeof(APPBARDATA));
            d.hWnd = dock;
            d.uCallbackMessage = callbackMsg;
            SHAppBarMessage(ABM_NEW, ref d);
        }

        // Giữ một dải cao "height" pixel ở đáy màn hình chính; trả về vị trí Windows cấp cho Dock
        public static RECT PlaceAppBar(IntPtr dock, int screenW, int screenH, int height)
        {
            var d = new APPBARDATA();
            d.cbSize = Marshal.SizeOf(typeof(APPBARDATA));
            d.hWnd = dock;
            d.uEdge = ABE_BOTTOM;
            d.rc.Left = 0; d.rc.Right = screenW; d.rc.Top = screenH - height; d.rc.Bottom = screenH;
            SHAppBarMessage(ABM_QUERYPOS, ref d);
            d.rc.Top = d.rc.Bottom - height;
            SHAppBarMessage(ABM_SETPOS, ref d);
            return d.rc;
        }

        public static void RemoveAppBar(IntPtr dock)
        {
            var d = new APPBARDATA();
            d.cbSize = Marshal.SizeOf(typeof(APPBARDATA));
            d.hWnd = dock;
            SHAppBarMessage(ABM_REMOVE, ref d);
        }
    }

    // =================================================================
    //  TỆP ANH 7: một mục file/thư mục để hiển thị (tự báo giao diện khi đổi icon)
    // =================================================================
    public class FileItem : INotifyPropertyChanged
    {
        public string Name { get; set; }
        public string Path { get; set; }
        public bool IsDir { get; set; }
        public string Kind { get; set; }
        public string SizeText { get; set; }
        public string DateText { get; set; }
        public long Size { get; set; }
        public DateTime Modified { get; set; }
        object icon;
        public object Icon
        {
            get { return icon; }
            set { icon = value; if (PropertyChanged != null) PropertyChanged(this, new PropertyChangedEventArgs("Icon")); }
        }
        public event PropertyChangedEventHandler PropertyChanged;
    }

    // Ảnh thu nhỏ / icon của file do Windows tạo (giống Explorer), trả về điểm ảnh BGRA đã nhân alpha
    public static class Thumbs
    {
        [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IShellItemImageFactory
        {
            [PreserveSig] int GetImage(SIZE size, int flags, out IntPtr phbm);
        }
        [StructLayout(LayoutKind.Sequential)] struct SIZE { public int cx; public int cy; }

        [StructLayout(LayoutKind.Sequential)]
        struct BITMAP { public int bmType, bmWidth, bmHeight, bmWidthBytes; public ushort bmPlanes, bmBitsPixel; public IntPtr bmBits; }
        [StructLayout(LayoutKind.Sequential)]
        struct BITMAPINFOHEADER { public int biSize, biWidth, biHeight; public short biPlanes, biBitCount; public int biCompression, biSizeImage, biXPelsPerMeter, biYPelsPerMeter, biClrUsed, biClrImportant; }
        [StructLayout(LayoutKind.Sequential)]
        struct DIBSECTION { public BITMAP dsBm; public BITMAPINFOHEADER dsBmih; public int b0, b1, b2; public IntPtr dshSection; public int dsOffset; }

        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
        static extern int SHCreateItemFromParsingName(string path, IntPtr pbc, ref Guid riid, out IShellItemImageFactory ppv);
        [DllImport("gdi32.dll")] static extern int GetObject(IntPtr h, int size, ref DIBSECTION ds);
        [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr h);

        // flags: 0 = ảnh thu nhỏ nếu có, 4 = chỉ icon (nhanh)
        public static byte[] Get(string path, int size, int flags, out int width, out int height)
        {
            width = 0; height = 0;
            IShellItemImageFactory f = null;
            IntPtr hbm = IntPtr.Zero;
            try
            {
                Guid iid = typeof(IShellItemImageFactory).GUID;
                if (SHCreateItemFromParsingName(path, IntPtr.Zero, ref iid, out f) != 0 || f == null) return null;
                SIZE sz; sz.cx = size; sz.cy = size;
                if (f.GetImage(sz, flags, out hbm) != 0 || hbm == IntPtr.Zero) return null;
                var ds = new DIBSECTION();
                if (GetObject(hbm, Marshal.SizeOf(typeof(DIBSECTION)), ref ds) == 0 || ds.dsBm.bmBits == IntPtr.Zero || ds.dsBm.bmBitsPixel != 32) return null;
                int w = ds.dsBm.bmWidth, h = ds.dsBm.bmHeight, stride = w * 4;
                var raw = new byte[stride * h];
                Marshal.Copy(ds.dsBm.bmBits, raw, 0, raw.Length);
                // DIB thường lưu từ dưới lên -> lật lại cho đúng chiều
                if (ds.dsBmih.biHeight > 0)
                {
                    var flipped = new byte[raw.Length];
                    for (int y = 0; y < h; y++) Buffer.BlockCopy(raw, (h - 1 - y) * stride, flipped, y * stride, stride);
                    raw = flipped;
                }
                width = w; height = h;
                return raw;
            }
            catch { return null; }
            finally
            {
                if (hbm != IntPtr.Zero) DeleteObject(hbm);
                if (f != null) Marshal.ReleaseComObject(f);
            }
        }
    }

    // =================================================================
    //  PHÍM WINDOWS -> mở Start của Anh 7
    //  Chạy trên luồng riêng có vòng nhận tin nhắn riêng, nên Dock bận cũng không làm gõ phím bị chậm.
    //  - Bấm-nhả phím Windows một mình: chặn lại, tăng Taps (Dock đọc Taps để mở Start Anh 7)
    //  - Phím Windows + phím khác (Win+E, Win+D, Win+Shift+S...): phát lại nguyên tổ hợp cho Windows
    //  - Win+L: khóa máy như bình thường
    // =================================================================
    public static class WinKey
    {
        delegate IntPtr HookProc(int code, IntPtr wParam, IntPtr lParam);
        [StructLayout(LayoutKind.Sequential)]
        struct KBDLLHOOKSTRUCT { public uint vkCode, scanCode, flags, time; public IntPtr extra; }
        [StructLayout(LayoutKind.Sequential)]
        struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam, lParam; public uint time; public int x, y; }
        [DllImport("user32.dll", SetLastError = true)] static extern IntPtr SetWindowsHookEx(int id, HookProc fn, IntPtr mod, uint thread);
        [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr h);
        [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr h, int code, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll")] static extern int GetMessage(out MSG m, IntPtr hwnd, uint min, uint max);
        [DllImport("user32.dll")] static extern bool PostThreadMessage(uint thread, uint msg, IntPtr w, IntPtr l);
        [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
        [DllImport("user32.dll")] static extern bool LockWorkStation();
        [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandle(string name);

        static IntPtr hook = IntPtr.Zero;
        static HookProc proc;
        static Thread thread;
        static uint threadId;
        static bool winDown, combo;
        public static volatile int Taps;
        public static volatile bool Enabled = true;

        public static void Start()
        {
            if (thread != null) return;
            thread = new Thread(Run);
            thread.IsBackground = true;
            thread.Start();
        }

        public static void Stop()
        {
            if (thread == null) return;
            PostThreadMessage(threadId, 0x0012, IntPtr.Zero, IntPtr.Zero);   // WM_QUIT
            thread = null;
        }

        static void Run()
        {
            threadId = GetCurrentThreadId();
            proc = Hook;
            hook = SetWindowsHookEx(13, proc, GetModuleHandle(null), 0);     // WH_KEYBOARD_LL
            MSG m;
            while (GetMessage(out m, IntPtr.Zero, 0, 0) > 0) { }
            if (hook != IntPtr.Zero) UnhookWindowsHookEx(hook);
            hook = IntPtr.Zero;
        }

        static IntPtr Hook(int code, IntPtr wParam, IntPtr lParam)
        {
            if (code >= 0 && Enabled)
            {
                var k = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(KBDLLHOOKSTRUCT));
                bool injected = (k.flags & 0x10) != 0;
                int msg = (int)wParam;
                bool down = msg == 0x100 || msg == 0x104;
                bool up = msg == 0x101 || msg == 0x105;
                bool isWin = k.vkCode == 0x5B || k.vkCode == 0x5C;
                if (!injected)
                {
                    if (isWin && down)
                    {
                        if (!winDown) { winDown = true; combo = false; }
                        if (!combo) return (IntPtr)1;            // giữ lại, chưa biết bấm một mình hay tổ hợp
                    }
                    else if (isWin && up)
                    {
                        winDown = false;
                        if (!combo) { Taps++; return (IntPtr)1; } // bấm một mình -> Start Anh 7
                        // tổ hợp: để phím nhả đi qua, khớp với phím Windows đã phát lại
                    }
                    else if (winDown && down && !combo)
                    {
                        combo = true;
                        if (k.vkCode == 0x4C) { LockWorkStation(); return (IntPtr)1; }   // Win+L
                        uint ext = (k.flags & 1) != 0 ? 1u : 0u;
                        keybd_event(0x5B, 0, 0, UIntPtr.Zero);
                        keybd_event((byte)k.vkCode, (byte)k.scanCode, ext, UIntPtr.Zero);
                        return (IntPtr)1;
                    }
                }
            }
            return CallNextHookEx(hook, code, wParam, lParam);
        }
    }
}
