using System.IO.Pipes;
using System.Runtime.InteropServices;
using Microsoft.UI.Composition;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Microsoft.Win32;
using SqueezeBar.Core;
using Windows.UI;

namespace SqueezeBar;

/// <summary>"Launch at system startup": a per-user Run entry, so no admin rights are needed.</summary>
static class StartupEntry
{
    const string Key = @"Software\Microsoft\Windows\CurrentVersion\Run", Name = "SqueezeBar";

    public static bool IsEnabled => Registry.CurrentUser.OpenSubKey(Key)?.GetValue(Name) is not null;

    public static void Set(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(Key);
        if (enabled) key.SetValue(Name, $"\"{Environment.ProcessPath}\" --background");
        else key.DeleteValue(Name, throwOnMissingValue: false);
    }
}

/// <summary>
/// "Squeeze with SqueezeBar" in Explorer's right-click menu for files and folders (per user).
/// ponytail: classic menu entry, so on Windows 11 it sits under "Show more options"; the top-level
/// menu needs a packaged (MSIX) app.
/// </summary>
static class ExplorerMenu
{
    static readonly string[] Roots = [@"Software\Classes\*\shell\SqueezeBar", @"Software\Classes\Directory\shell\SqueezeBar"];

    public static bool IsEnabled => Registry.CurrentUser.OpenSubKey(Roots[0]) is not null;

    public static void Set(bool enabled)
    {
        foreach (var root in Roots)
        {
            if (!enabled) { Registry.CurrentUser.DeleteSubKeyTree(root, throwOnMissingSubKey: false); continue; }
            using var key = Registry.CurrentUser.CreateSubKey(root);
            key.SetValue("MUIVerb", "Squeeze with SqueezeBar");
            key.SetValue("Icon", $"\"{Environment.ProcessPath}\"");
            using var command = key.CreateSubKey("command");
            command.SetValue("", $"\"{Environment.ProcessPath}\" \"%1\"");
        }
    }

    /// <summary>Both entries store the exe path; refresh them if the app folder was moved.</summary>
    public static void RepairPaths()
    {
        if (IsEnabled) Set(true);
        if (StartupEntry.IsEnabled) StartupEntry.Set(true);
    }
}

/// <summary>
/// One running copy per user. A second launch (Explorer starts one per selected file) hands its
/// arguments to the first over a named pipe and exits.
/// </summary>
static class SingleInstance
{
    // The mutex is per session, so the pipe name carries the session too (same user signed in twice, e.g. over Remote Desktop).
    static readonly string Name = $"SqueezeBar.{Environment.UserName}.{System.Diagnostics.Process.GetCurrentProcess().SessionId}";
    static Mutex? _mutex;

    public static bool TryBecomePrimary(Action<string[]> onArguments)
    {
        _mutex = new Mutex(true, Name, out bool created);
        if (!created) return false;
        new Thread(() =>
        {
            while (true)
            {
                try
                {
                    using var pipe = new NamedPipeServerStream(Name, PipeDirection.In, 1, PipeTransmissionMode.Byte, PipeOptions.CurrentUserOnly);
                    pipe.WaitForConnection();
                    using var reader = new StreamReader(pipe);
                    onArguments(reader.ReadToEnd().Split('\n', StringSplitOptions.RemoveEmptyEntries));
                }
                // A client vanished mid-send, or the pipe name is taken (possibly by another account): keep trying, without spinning.
                catch (Exception e) when (e is IOException or UnauthorizedAccessException) { Thread.Sleep(500); }
            }
        }) { IsBackground = true }.Start();
        return true;
    }

    public static void Forward(IEnumerable<string> arguments)
    {
        try
        {
            using var pipe = new NamedPipeClientStream(".", Name, PipeDirection.Out, PipeOptions.CurrentUserOnly);
            pipe.Connect(10000); // Explorer starts one copy per selected file; they queue here
            using var writer = new StreamWriter(pipe);
            writer.Write(string.Join('\n', arguments));
        }
        catch (Exception e) when (e is IOException or TimeoutException or UnauthorizedAccessException) { } // primary is busy or exiting; nothing more to do
    }
}

/// <summary>Completion chimes. The Mac themes are macOS system sounds, so each maps to a sound that ships with Windows.</summary>
static class Sounds
{
    public static readonly (string Name, string File)[] Themes =
    [
        ("Crystal", "chimes.wav"), ("8-Bit", "Windows Notify Messaging.wav"), ("Bubble", "Windows Balloon.wav"),
        ("Hydraulic", "Windows Unlock.wav"), ("Sci-Fi", "Speech On.wav"), ("Hero", "tada.wav"),
    ];

    [DllImport("winmm", CharSet = CharSet.Unicode)] static extern bool PlaySoundW(string? sound, IntPtr module, uint flags);

    public static void Play(string theme)
    {
        var file = Themes.FirstOrDefault(t => t.Name == theme).File ?? Themes[0].File;
        var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "Media", file);
        if (File.Exists(path)) PlaySoundW(path, IntPtr.Zero, 0x00020000 /* SND_FILENAME */ | 0x0001 /* SND_ASYNC */ | 0x0002 /* SND_NODEFAULT */);
    }
}

/// <summary>
/// Dark acrylic.
/// Stays translucent while the window is unfocused, which a pinned floating window needs.
/// </summary>
sealed class GlassBackdrop : SystemBackdrop
{
    DesktopAcrylicController? _controller;
    protected override void OnTargetConnected(ICompositionSupportsSystemBackdrop target, XamlRoot root)
    {
        base.OnTargetConnected(target, root);
        _controller = new DesktopAcrylicController();
        _controller.AddSystemBackdropTarget(target);
        _controller.SetSystemBackdropConfiguration(new SystemBackdropConfiguration { IsInputActive = true, Theme = SystemBackdropTheme.Dark });
        _controller.TintColor = Color.FromArgb(255, 28, 28, 30);
        _controller.TintOpacity = 0.9f;
        _controller.LuminosityOpacity = 0.5f;
    }

    protected override void OnTargetDisconnected(ICompositionSupportsSystemBackdrop target)
    {
        base.OnTargetDisconnected(target);
        _controller?.RemoveSystemBackdropTarget(target);
        _controller?.Dispose();
        _controller = null;
    }
}
