// =====================================================================
//  Anh 7 Dock — các hàm gọi Windows (C#, được PowerShell biên dịch lúc chạy)
//  - Liệt kê cửa sổ ứng dụng đang mở (giống thanh tác vụ)
//  - Bật/thu nhỏ cửa sổ, gửi phím tắt Windows (Start, Tìm kiếm...)
//  - Ẩn/hiện thanh tác vụ Windows, đăng ký Dock là "AppBar" để cửa sổ phóng to không che Dock
// =====================================================================
using System;
using System.Collections.Generic;
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
}
