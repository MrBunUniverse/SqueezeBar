using System.Diagnostics;
using System.Numerics;
using System.Runtime.InteropServices;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Shapes;
using SqueezeBar.Core;
using SqueezeBar.Media;
using Windows.ApplicationModel.DataTransfer;
using Windows.Graphics;
using Windows.Storage.Pickers;
using Windows.UI;

namespace SqueezeBar;

public sealed partial class MainWindow : Window
{
    [DllImport("user32")] static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32")] static extern bool SetForegroundWindow(IntPtr hwnd);
    [StructLayout(LayoutKind.Sequential)] struct CursorPoint { public int X, Y; }
    [DllImport("user32")] static extern bool GetCursorPos(out CursorPoint point);
    bool _dragging;
    CursorPoint _dragCursor;
    PointInt32 _dragWindow;

    static Color Accent => Ui.Accent;
    static readonly Color Green = Color.FromArgb(255, 82, 209, 107);
    static readonly Color Red = Color.FromArgb(255, 242, 71, 71);

    readonly AppState _state = AppState.Shared;
    readonly Dictionary<Guid, JobRow> _jobs = [];
    readonly FormatDeck _deck;
    readonly QueueView _queue;
    readonly GlassBackdrop _glass = new();
    readonly FolderWatch _watch = new();
    bool _settingsOpen;
    public IntPtr Handle { get; }
    bool _pinned, _dialogOpen, _dropTargeted;
    DateTime _hiddenAt;
    int _runningJobs;
    Storyboard _headerSweep = null!;
    bool _headerSweeping = true;
    Rectangle[] _headerBars = [];

    sealed record JobRow(Border Card, ProgressBar Bar, TextBlock Status, Button Action, string FileName);

    public MainWindow()
    {
        InitializeComponent();
        Handle = WinRT.Interop.WindowNative.GetWindowHandle(this);
        Title = "SqueezeBar";
        SystemBackdrop = _glass;
        Ui.SetAccent(_state.Prefs);
        ExtendsContentIntoTitleBar = true;

        var presenter = OverlappedPresenter.Create();
        presenter.IsResizable = presenter.IsMaximizable = presenter.IsMinimizable = false;
        presenter.IsAlwaysOnTop = true;
        presenter.SetBorderAndTitleBar(true, false);
        AppWindow.SetPresenter(presenter);
        AppWindow.IsShownInSwitchers = false;
        // Closing (Alt+F4) only hides; Quit is the way out, like a menu-bar app.
        AppWindow.Closing += (_, e) => { e.Cancel = true; HideFlyout(); };
        Activated += (_, e) =>
        {
            if (e.WindowActivationState == WindowActivationState.Deactivated && !_pinned && !_dialogOpen) HideFlyout();
        };

        var engine = _state.Engine;
        engine.JobAdded += (id, path, type) => DispatcherQueue.TryEnqueue(() => AddJob(id, path));
        engine.JobProgress += (id, progress) => DispatcherQueue.TryEnqueue(() => UpdateJob(id, progress));
        engine.JobFinished += (id, result, error) => DispatcherQueue.TryEnqueue(() => FinishJob(id, result, error));
        _ = Task.Run(Compressors.ProbeAsync);

        _deck = new FormatDeck(TilesRow, Drawer, _state);
        _queue = new QueueView(QueueHost, _state, this);
        BuildMark(MarkCanvas);
        (_headerBars, _headerSweep) = BuildMark(HeaderMarkCanvas);
        SelectTab(settings: false);
        ApplyAppearance(rebuild: true);
        RestartWatchFolder();
    }

    // MARK: - Window

    public void Toggle()
    {
        // Clicking the tray icon deactivates (and hides) the flyout first; don't reopen it on that same click.
        if (AppWindow.IsVisible || DateTime.UtcNow - _hiddenAt < TimeSpan.FromMilliseconds(250)) HideFlyout();
        else ShowFlyout();
    }

    public void ShowFlyout()
    {
        if (!_pinned)
        {
            var (width, height) = PixelSize();
            var work = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary).WorkArea;
            int margin = (int)(12 * GetDpiForWindow(Handle) / 96.0);
            AppWindow.MoveAndResize(new RectInt32(work.X + work.Width - width - margin, work.Y + work.Height - height - margin, width, height));
        }
        AppWindow.Show();
        SetForegroundWindow(Handle);
    }

    /// <summary>Window size in pixels for the chosen interface scale on this display.</summary>
    (int Width, int Height) PixelSize()
    {
        double scale = GetDpiForWindow(Handle) / 96.0 * _state.Prefs.ScaleFactor;
        return ((int)(490 * scale), (int)(660 * scale));
    }

    /// <summary>Applies accent and interface scale. <paramref name="rebuild"/> redraws everything built in code;
    /// pass false to only update the accent.</summary>
    internal void ApplyAppearance(bool rebuild)
    {
        var prefs = _state.Prefs;
        Ui.SetAccent(prefs);
        if (!rebuild) return;

        var (width, height) = PixelSize();
        if (_pinned) AppWindow.Resize(new SizeInt32(width, height));
        else if (AppWindow.IsVisible) ShowFlyout();
        PaintPin();
        _deck.Refresh();
        _queue.Refresh();
        RefreshHistory();
        SelectTab(_settingsOpen);
    }

    internal void RestartWatchFolder()
    {
        var prefs = _state.Prefs;
        if (prefs.WatchFolderEnabled && !string.IsNullOrEmpty(prefs.WatchFolder))
            _watch.Start(prefs.WatchFolder, () => MediaCompressionEngine.OutputSuffix(_state.Config.Suffix), path => Squeeze([path]));
        else _watch.Stop();
    }

    /// <summary>Arguments handed over by a second launch (Explorer's right-click menu starts one per file).</summary>
    public void HandleArguments(string[] arguments) => DispatcherQueue.TryEnqueue(() =>
    {
        var files = arguments.Where(a => !a.StartsWith("--")).ToList();
        if (files.Count == 0 || !arguments.Contains("--background")) ShowFlyout();
        Open(files, queue: arguments.Contains("--queue"));
    });

    /// <summary>Files from the command line: squeezed at once, or with "--queue" staged for per-file review.</summary>
    public void Open(IReadOnlyList<string> files, bool queue)
    {
        if (files.Count == 0) return;
        if (queue) _queue.Add(files);
        else Squeeze(files);
    }

    void HideFlyout()
    {
        if (!AppWindow.IsVisible) return;
        _hiddenAt = DateTime.UtcNow;
        AppWindow.Hide();
    }

    void OnPin(object sender, RoutedEventArgs e) => TogglePin();

    public void TogglePin()
    {
        _pinned = !_pinned;
        PaintPin();
        if (!_pinned) ShowFlyout();
    }

    void PaintPin()
    {
        PinIcon.Glyph = _pinned ? "" : "";
        PinButton.Background = new SolidColorBrush(_pinned ? Color.FromArgb(90, Accent.R, Accent.G, Accent.B) : Color.FromArgb(20, 255, 255, 255));
        ToolTipService.SetToolTip(PinButton, _pinned ? "Dock back to the taskbar corner" : "Keep open as a floating window");
    }

    void OnHeaderPressed(object sender, PointerRoutedEventArgs e)
    {
        if (!_pinned || !e.GetCurrentPoint(Header).Properties.IsLeftButtonPressed) return;
        // Moved by hand: Windows' own caption drag (WM_NCLBUTTONDOWN) never saw the button release
        // because XAML held the pointer, so the window stayed glued to the cursor.
        GetCursorPos(out _dragCursor);
        _dragWindow = AppWindow.Position;
        _dragging = Header.CapturePointer(e.Pointer);
    }

    void OnHeaderMoved(object sender, PointerRoutedEventArgs e)
    {
        if (!_dragging) return;
        if (!e.GetCurrentPoint(Header).Properties.IsLeftButtonPressed) { EndHeaderDrag(e); return; }
        GetCursorPos(out var now);
        AppWindow.Move(new PointInt32(_dragWindow.X + now.X - _dragCursor.X, _dragWindow.Y + now.Y - _dragCursor.Y));
    }

    void OnHeaderCaptureLost(object sender, PointerRoutedEventArgs e) => _dragging = false;

    void OnHeaderReleased(object sender, PointerRoutedEventArgs e) => EndHeaderDrag(e);

    void EndHeaderDrag(PointerRoutedEventArgs e)
    {
        _dragging = false;
        Header.ReleasePointerCapture(e.Pointer);
    }

    void OnQuit(object sender, RoutedEventArgs e)
    {
        _state.Engine.CancelAll();
        Application.Current.Exit();
    }

    // MARK: - Tabs

    void OnActivityTab(object sender, RoutedEventArgs e) => SelectTab(settings: false);
    void OnSettingsTab(object sender, RoutedEventArgs e) => SelectTab(settings: true);

    void SelectTab(bool settings)
    {
        ActivityView.Visibility = settings ? Visibility.Collapsed : Visibility.Visible;
        SettingsScroll.Visibility = settings ? Visibility.Visible : Visibility.Collapsed;
        _settingsOpen = settings;
        if (settings) SettingsView.Build(SettingsPanel, _state, this);
        Paint(ActivityTab, !settings);
        Paint(SettingsTab, settings);

        static void Paint(Button tab, bool selected)
        {
            tab.Background = new SolidColorBrush(selected ? Color.FromArgb(41, 255, 255, 255) : Colors.Transparent);
            tab.BorderBrush = new SolidColorBrush(selected ? Color.FromArgb(56, 255, 255, 255) : Colors.Transparent);
            tab.Foreground = new SolidColorBrush(selected ? Colors.White : Color.FromArgb(153, 255, 255, 255));
            tab.FontWeight = selected ? Microsoft.UI.Text.FontWeights.SemiBold : Microsoft.UI.Text.FontWeights.Medium;
        }
    }

    // MARK: - Inputs (drop, picker, clipboard, command line)

    /// <summary>Every input path ends here so they all behave the same.</summary>
    public void Squeeze(IReadOnlyList<string> paths)
    {
        var config = _state.Config;
        _ = Task.Run(async () =>
        {
            if (MediaCompressionEngine.GatherMediaFiles(paths).Count == 0)
            {
                DispatcherQueue.TryEnqueue(() => Hint("No supported files found. Use images, video, audio or PDF."));
                return;
            }
            await _state.Engine.ProcessDroppedAsync(paths, config);
        });
    }

    async void Hint(string message)
    {
        ZoneDetail.Text = message;
        await Task.Delay(4000);
        ZoneDetail.Text = "Compresses immediately with your current presets";
    }

    async void OnChooseFiles(object sender, RoutedEventArgs e)
    {
        if (await PickFilesAsync() is { Count: > 0 } files) Squeeze(files);
    }

    internal async Task<IReadOnlyList<string>> PickFilesAsync()
    {
        var picker = new FileOpenPicker { SuggestedStartLocation = PickerLocationId.PicturesLibrary };
        picker.FileTypeFilter.Add("*");
        WinRT.Interop.InitializeWithWindow.Initialize(picker, Handle);
        _dialogOpen = true;
        try { return (await picker.PickMultipleFilesAsync()).Select(f => f.Path).ToList(); }
        finally { _dialogOpen = false; SetForegroundWindow(Handle); }
    }

    internal async Task<string?> PickFolderAsync()
    {
        var picker = new FolderPicker { SuggestedStartLocation = PickerLocationId.Downloads };
        picker.FileTypeFilter.Add("*");
        WinRT.Interop.InitializeWithWindow.Initialize(picker, Handle);
        _dialogOpen = true;
        try { return (await picker.PickSingleFolderAsync())?.Path; }
        finally { _dialogOpen = false; SetForegroundWindow(Handle); }
    }

    void OnSqueezeClipboard(object sender, RoutedEventArgs e) => SqueezeClipboard();
    void OnPasteAccelerator(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs e)
    {
        if (FocusManager.GetFocusedElement(Content.XamlRoot) is TextBox or NumberBox) return; // let text fields paste text
        e.Handled = true;
        SqueezeClipboard();
    }

    async void SqueezeClipboard()
    {
        var content = Clipboard.GetContent();
        if (!content.Contains(StandardDataFormats.StorageItems)) { Hint("The clipboard has no files. Copy files in Explorer first."); return; }
        Squeeze((await content.GetStorageItemsAsync()).Select(i => i.Path).ToList());
    }

    void OnDragOver(object sender, DragEventArgs e)
    {
        if (!e.DataView.Contains(StandardDataFormats.StorageItems)) return;
        e.AcceptedOperation = DataPackageOperation.Copy;
        e.DragUIOverride.Caption = "Squeeze";
        SetDropTargeted(true);
    }

    void OnDragLeave(object sender, DragEventArgs e) => SetDropTargeted(false);

    async void OnDrop(object sender, DragEventArgs e)
    {
        SetDropTargeted(false);
        if (!e.DataView.Contains(StandardDataFormats.StorageItems)) return;
        Squeeze((await e.DataView.GetStorageItemsAsync()).Select(i => i.Path).ToList());
    }

    internal void SetDropTargeted(bool targeted)
    {
        if (targeted == _dropTargeted) return; // DragOver fires on every pointer move
        _dropTargeted = targeted;
        if (targeted) SelectTab(settings: false);
        ZoneTitle.Text = targeted ? "Release to Squeeze" : "Drop files to squeeze";
        ZoneOutline.StrokeDashArray = targeted ? null : [4, 4];
        ZoneOutline.StrokeThickness = targeted ? 1.5 : 1;
        ZoneOutline.Stroke = new SolidColorBrush(targeted ? Color.FromArgb(179, Accent.R, Accent.G, Accent.B) : Color.FromArgb(31, 255, 255, 255));
        ZoneOutline.Fill = new SolidColorBrush(targeted ? Color.FromArgb(26, Accent.R, Accent.G, Accent.B) : Color.FromArgb(5, 255, 255, 255));
        Spring(Mark, targeted ? 1.12f : 1f);
    }

    // MARK: - Jobs

    void AddJob(Guid id, string path)
    {
        var name = System.IO.Path.GetFileName(path);
        var title = Ui.Text(name, 12, semibold: true);
        title.TextTrimming = TextTrimming.CharacterEllipsis;
        var status = Ui.Text("Queued", 10.5, secondary: true);
        var bar = new ProgressBar { Maximum = 1, Value = 0, Margin = new Thickness(0, 8, 0, 0), Foreground = new SolidColorBrush(Accent) };
        var action = Ui.IconButton("", "Cancel");
        action.Click += (_, _) => { if (_jobs.ContainsKey(id)) _state.Engine.Cancel(id); };

        var top = new Grid { ColumnSpacing = 8 };
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        top.Children.Add(title);
        Grid.SetColumn(status, 1); top.Children.Add(status);
        Grid.SetColumn(action, 2); top.Children.Add(action);

        var card = Ui.Card(new StackPanel { Children = { top, bar } });
        _jobs[id] = new JobRow(card, bar, status, action, name);
        JobsPanel.Children.Insert(0, card);
        _runningJobs++;
        RefreshStatus(completed: false);
    }

    void UpdateJob(Guid id, double progress)
    {
        if (!_jobs.TryGetValue(id, out var row)) return;
        row.Bar.Value = progress;
        row.Status.Text = $"{(int)(progress * 100)}%";
        UpdateHeaderMark();
    }

    void FinishJob(Guid id, CompressionResult? result, string? error)
    {
        if (!_jobs.Remove(id, out var row)) return;
        _runningJobs--;
        if (result is not null)
        {
            JobsPanel.Children.Remove(row.Card);
            _state.AddResult(result);
            RefreshHistory();
        }
        else if (error == MediaCompressionEngine.Cancelled) JobsPanel.Children.Remove(row.Card);
        else
        {
            // Failed jobs stay visible until dismissed so the reason isn't lost.
            row.Bar.Visibility = Visibility.Collapsed;
            row.Status.Text = "Failed";
            row.Status.Foreground = new SolidColorBrush(Red);
            var reason = Ui.Text(error ?? "Unknown error", 10.5, secondary: true);
            reason.TextWrapping = TextWrapping.Wrap;
            reason.Margin = new Thickness(0, 6, 0, 0);
            ((StackPanel)row.Card.Child).Children.Add(reason);
            ToolTipService.SetToolTip(row.Action, "Dismiss");
            row.Action.Click += (_, _) => { JobsPanel.Children.Remove(row.Card); RefreshStatus(completed: false); };
        }
        RefreshStatus(completed: _runningJobs == 0 && result is not null);
    }

    async void RefreshStatus(bool completed)
    {
        JobsPanel.Visibility = JobsPanel.Children.Count > 0 ? Visibility.Visible : Visibility.Collapsed; // an empty panel would still add a gap
        bool busy = _runningJobs > 0;
        StatusBadge.Visibility = busy || completed ? Visibility.Visible : Visibility.Collapsed;
        var tone = busy ? Accent : Green;
        StatusBadge.Background = new SolidColorBrush(Color.FromArgb(31, tone.R, tone.G, tone.B));
        StatusText.Foreground = StatusCheck.Foreground = new SolidColorBrush(tone);
        StatusText.Text = busy ? "Optimizing..." : "Complete";
        StatusRing.Visibility = CancelAllButton.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
        StatusCheck.Visibility = busy ? Visibility.Collapsed : Visibility.Visible;
        UpdateHeaderMark();
        if (!completed) return;
        if (_state.Prefs.SoundEnabled) Sounds.Play(_state.Prefs.SoundTheme);
        await Task.Delay(3000);
        if (_runningJobs == 0) StatusBadge.Visibility = Visibility.Collapsed;
    }

    /// <summary>Header S: the idle light sweep, or while jobs run the bars light one after another with overall progress (as on the Mac).</summary>
    void UpdateHeaderMark()
    {
        bool idle = _jobs.Count == 0;
        if (idle != _headerSweeping) { _headerSweeping = idle; if (idle) _headerSweep.Begin(); else _headerSweep.Stop(); }
        if (idle) return;
        double p = Math.Clamp(_jobs.Values.Average(r => r.Bar.Value), 0.04, 1);
        for (int i = 0; i < _headerBars.Length; i++)
            _headerBars[i].Opacity = 0.28 + 0.72 * Math.Clamp(p * _headerBars.Length - i, 0, 1);
    }

    void OnCancelAll(object sender, RoutedEventArgs e) => _state.Engine.CancelAll();

    // MARK: - History

    void OnClearHistory(object sender, RoutedEventArgs e)
    {
        _state.ClearHistory();
        RefreshHistory();
    }

    // ponytail: rebuilds every row on each change; fine while history is capped at 50.
    internal void RefreshHistory()
    {
        HistoryPanel.Children.Clear();
        // With history the drop zone shrinks to a strip so results stay in view, as on the Mac.
        bool empty = _state.History.Count == 0;
        ZoneGrid.MinHeight = empty ? 218 : 76;
        Mark.Visibility = ZoneHint.Visibility = ClipboardButton.Visibility = empty ? Visibility.Visible : Visibility.Collapsed;
        ClearHistoryItem.IsEnabled = !empty;
        long saved = _state.Prefs.TotalBytesSaved;
        Subtitle.Text = saved > 0 ? $"Saved {Ui.Bytes(saved)} so far" : "Universal Media Optimizer";

        foreach (var result in _state.History)
        {
            bool exists = File.Exists(result.OutputPath);
            var name = Ui.Text(System.IO.Path.GetFileName(result.OutputPath), 12, semibold: true);
            name.TextTrimming = TextTrimming.CharacterEllipsis;
            var sizes = Ui.Text($"{Ui.Bytes(result.OriginalSize)}  →  {Ui.Bytes(result.CompressedSize)}", 10.5, secondary: true);
            var labels = new StackPanel { Spacing = 2, Children = { name, sizes } };

            bool smaller = result.CompressedSize < result.OriginalSize;
            var tone = smaller ? Green : Color.FromArgb(255, 250, 199, 31);
            var percent = Ui.Text(smaller ? $"−{result.PercentSaved:0}%" : "No gain", 10.5, semibold: true);
            percent.Foreground = new SolidColorBrush(tone);
            var badge = new Border
            {
                Child = percent, CornerRadius = new CornerRadius(8), Padding = new Thickness(7, 2, 7, 2), VerticalAlignment = VerticalAlignment.Center,
                Background = new SolidColorBrush(Color.FromArgb(31, tone.R, tone.G, tone.B)),
            };
            var reveal = Ui.IconButton("", "Show in folder");
            reveal.IsEnabled = exists;
            reveal.Click += (_, _) => Process.Start(System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe"), $"/select,\"{result.OutputPath}\""); // full path: a bare name would also search the current folder
            var remove = Ui.IconButton("", "Remove from history");
            remove.Click += (_, _) => { _state.RemoveResult(result); RefreshHistory(); };

            var row = new Grid { ColumnSpacing = 8 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            for (int i = 0; i < 3; i++) row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.Children.Add(labels);
            Grid.SetColumn(badge, 1); row.Children.Add(badge);
            Grid.SetColumn(reveal, 2); row.Children.Add(reveal);
            Grid.SetColumn(remove, 3); row.Children.Add(remove);

            var card = Ui.Card(row);
            card.Opacity = exists ? 1 : 0.5;
            HistoryPanel.Children.Add(card);
        }
    }

    // MARK: - S mark and motion

    /// <summary>Five rounded bars on the Mac app's 1024 design grid, with the same slow top-to-bottom light sweep.</summary>
    static (Rectangle[] Bars, Storyboard Sweep) BuildMark(Canvas canvas)
    {
        var rects = new Rectangle[5];
        (double X0, double X1, double Y)[] bars = [(290, 800, 170), (224, 484, 312), (224, 800, 454), (540, 800, 596), (224, 734, 738)];
        var sweep = new Storyboard { RepeatBehavior = RepeatBehavior.Forever };
        for (int i = 0; i < bars.Length; i++)
        {
            var bar = new Rectangle
            {
                Width = bars[i].X1 - bars[i].X0, Height = 116, RadiusX = 58, RadiusY = 58,
                Fill = new SolidColorBrush(Colors.White), Opacity = 0.20,
            };
            Canvas.SetLeft(bar, bars[i].X0 - 224);
            Canvas.SetTop(bar, bars[i].Y - 170);
            canvas.Children.Add(bar);
            rects[i] = bar;

            double peak = (i + 1) * 0.75, half = 0.975;
            var frames = new DoubleAnimationUsingKeyFrames();
            void Key(double seconds, double value) => frames.KeyFrames.Add(new EasingDoubleKeyFrame
            {
                KeyTime = KeyTime.FromTimeSpan(TimeSpan.FromSeconds(Math.Max(0, seconds))), Value = value,
                EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut },
            });
            Key(peak - half, 0.20); Key(peak, 0.50); Key(peak + half, 0.20); Key(6.0, 0.20);
            Storyboard.SetTarget(frames, bar);
            Storyboard.SetTargetProperty(frames, "Opacity");
            sweep.Children.Add(frames);
        }
        sweep.Begin();
        return (rects, sweep);
    }

    /// <summary>Counterpart of SwiftUI's <c>.spring(response:dampingFraction:)</c>.</summary>
    static void Spring(FrameworkElement element, float scale, double response = 0.28, float damping = 0.72f)
    {
        var visual = ElementCompositionPreview.GetElementVisual(element);
        visual.CenterPoint = new Vector3((float)element.ActualWidth / 2, (float)element.ActualHeight / 2, 0);
        var spring = visual.Compositor.CreateSpringVector3Animation();
        spring.FinalValue = new Vector3(scale);
        spring.DampingRatio = damping;
        spring.Period = TimeSpan.FromSeconds(response);
        visual.StartAnimation("Scale", spring);
    }
}
