using Microsoft.UI.Xaml;

namespace SqueezeBar;

public partial class App : Application
{
    MainWindow? _window;
    readonly List<string[]> _early = []; // forwarded by other copies before the window existed

    public App() => InitializeComponent();

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        // Files on the command line (Explorer's right-click menu) are squeezed straight away.
        // "--pin" starts as a floating window; "--background" (used at login) starts hidden in the tray;
        // "--queue" stages the files for per-file review instead of squeezing them.
        var arguments = Environment.GetCommandLineArgs().Skip(1).ToArray();
        if (!SingleInstance.TryBecomePrimary(a =>
            {
                lock (_early) { if (_window is null) { _early.Add(a); return; } }
                _window.HandleArguments(a);
            }))
        {
            SingleInstance.Forward(arguments);
            Environment.Exit(0);
        }

        ExplorerMenu.RepairPaths();
        var window = new MainWindow();
        string[][] early;
        lock (_early) { _window = window; early = [.. _early]; }
        foreach (var forwarded in early) window.HandleArguments(forwarded);
        Tray.Add(_window.Handle, "SqueezeBar", onClick: _window.Toggle, onRightClick: _window.ShowFlyout);
        if (!arguments.Contains("--background")) _window.ShowFlyout();
        if (arguments.Contains("--pin")) _window.TogglePin();
        var files = arguments.Where(a => !a.StartsWith("--")).ToList();
        _window.Open(files, queue: arguments.Contains("--queue"));
    }
}
