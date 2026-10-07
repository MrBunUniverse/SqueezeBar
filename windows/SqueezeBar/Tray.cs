using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace SqueezeBar;

/// <summary>Notification-area icon through Shell_NotifyIcon; its messages arrive on the host window via a subclass.</summary>
static class Tray
{
    const uint TrayMessage = 0x8000 + 1, WM_LBUTTONUP = 0x0202, WM_RBUTTONUP = 0x0205, WM_DESTROY = 0x0002;
    const int NIM_ADD = 0, NIM_DELETE = 2, NIF_MESSAGE = 1, NIF_ICON = 2, NIF_TIP = 4;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct NOTIFYICONDATA
    {
        public int cbSize; public IntPtr hWnd; public uint uID; public int uFlags; public uint uCallbackMessage; public IntPtr hIcon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string szTip;
        public int dwState, dwStateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string szInfo;
        public int uVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string szInfoTitle;
        public int dwInfoFlags; public Guid guidItem; public IntPtr hBalloonIcon;
    }

    delegate IntPtr SubclassProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam, IntPtr id, IntPtr data);

    [DllImport("shell32", CharSet = CharSet.Unicode)] static extern bool Shell_NotifyIconW(int message, ref NOTIFYICONDATA data);
    [DllImport("comctl32")] static extern bool SetWindowSubclass(IntPtr hWnd, SubclassProc proc, IntPtr id, IntPtr data);
    [DllImport("comctl32")] static extern IntPtr DefSubclassProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32")] static extern IntPtr CreateIcon(IntPtr instance, int width, int height, byte planes, byte bitsPerPixel, byte[] andBits, byte[] xorBits);

    static SubclassProc? _proc; // keep the delegate alive for the lifetime of the window
    static NOTIFYICONDATA _data;

    public static void Add(IntPtr hwnd, string tip, Action onClick, Action onRightClick)
    {
        _proc = (h, msg, w, l, _, _) =>
        {
            if (msg == TrayMessage)
            {
                uint mouse = (uint)l.ToInt64() & 0xFFFF;
                if (mouse == WM_LBUTTONUP) onClick();
                if (mouse == WM_RBUTTONUP) onRightClick();
                return IntPtr.Zero;
            }
            if (msg == WM_DESTROY) Shell_NotifyIconW(NIM_DELETE, ref _data);
            return DefSubclassProc(h, msg, w, l);
        };
        SetWindowSubclass(hwnd, _proc, 1, IntPtr.Zero);
        _data = new NOTIFYICONDATA
        {
            cbSize = Marshal.SizeOf<NOTIFYICONDATA>(), hWnd = hwnd, uID = 1,
            uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP, uCallbackMessage = TrayMessage,
            hIcon = MarkIcon(32), szTip = tip, szInfo = "", szInfoTitle = "",
        };
        Shell_NotifyIconW(NIM_ADD, ref _data);
        _ = Task.Run(Promote);
    }

    /// <summary>Windows 11 files a new tray icon in the overflow flyout; show ours on the taskbar the first time only, so the user's own hide/show choice sticks.</summary>
    static void Promote()
    {
        try
        {
            for (int attempt = 0; attempt < 10; attempt++)
            {
                Thread.Sleep(500); // Explorer registers the icon asynchronously
                using var all = Registry.CurrentUser.OpenSubKey(@"Control Panel\NotifyIconSettings");
                if (all is null) return;
                foreach (var name in all.GetSubKeyNames())
                {
                    using var key = all.OpenSubKey(name, writable: true);
                    if (key?.GetValue("ExecutablePath") is string path && path.Equals(Environment.ProcessPath, StringComparison.OrdinalIgnoreCase))
                    {
                        if (key.GetValue("IsPromoted") is null) key.SetValue("IsPromoted", 1, RegistryValueKind.DWord);
                        return;
                    }
                }
            }
        }
        catch { } // taskbar placement is cosmetic; never break startup over it
    }

    /// <summary>The S mark (same bar geometry as the Mac app icon), white on a dark taskbar and black on a light one.</summary>
    static IntPtr MarkIcon(int size)
    {
        bool lightTaskbar = Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "SystemUsesLightTheme", 0) is 1;
        byte tone = lightTaskbar ? (byte)0 : (byte)255;
        (double X0, double X1, double Y)[] bars = [(290, 800, 170), (224, 484, 312), (224, 800, 454), (540, 800, 596), (224, 734, 738)];
        const double barHeight = 116, radius = 58, designWidth = 576, designHeight = 684, samples = 4;
        double scale = size / designHeight, offsetX = (size - designWidth * scale) / 2;

        var bgra = new byte[size * size * 4];
        for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++)
            {
                int hits = 0;
                for (int sy = 0; sy < samples; sy++)
                    for (int sx = 0; sx < samples; sx++)
                    {
                        double dx = (x + (sx + 0.5) / samples - offsetX) / scale + 224, dy = (y + (sy + 0.5) / samples) / scale + 170;
                        foreach (var (x0, x1, top) in bars)
                        {
                            // Distance to the bar's centre line segment gives the rounded ends.
                            double cx = Math.Clamp(dx, x0 + radius, x1 - radius), cy = top + barHeight / 2;
                            if ((dx - cx) * (dx - cx) + (dy - cy) * (dy - cy) <= radius * radius) { hits++; break; }
                        }
                    }
                byte alpha = (byte)(hits * 255 / (samples * samples));
                byte value = (byte)(tone * alpha / 255); // premultiplied
                int i = (y * size + x) * 4;
                bgra[i] = bgra[i + 1] = bgra[i + 2] = value;
                bgra[i + 3] = alpha;
            }
        return CreateIcon(IntPtr.Zero, size, size, 1, 32, new byte[size * size / 8], bgra);
    }
}
