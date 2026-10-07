using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using SqueezeBar.Core;
using SqueezeBar.Media;
using Windows.ApplicationModel.DataTransfer;
using Windows.UI;

namespace SqueezeBar;

/// <summary>
/// "Review settings first": files dropped here wait in a queue where each one can get its own
/// settings before squeezing. Quick drops elsewhere use one settings snapshot for the whole batch.
/// </summary>
sealed class QueueView
{
    readonly StackPanel _host;
    readonly AppState _state;
    readonly MainWindow _window;
    readonly List<StagedQueueItem> _items = [];
    bool _targeted;

    public QueueView(StackPanel host, AppState state, MainWindow window)
    {
        (_host, _state, _window) = (host, state, window);
        // The window's own drop handler squeezes immediately, so drops on the queue are handled here and stop there.
        host.AllowDrop = true;
        host.DragOver += (_, e) =>
        {
            if (!e.DataView.Contains(StandardDataFormats.StorageItems)) return;
            e.AcceptedOperation = DataPackageOperation.Copy;
            e.DragUIOverride.Caption = "Add to queue";
            e.Handled = true;
            _window.SetDropTargeted(false);
            SetTargeted(true);
        };
        host.DragLeave += (_, _) => SetTargeted(false);
        host.Drop += async (_, e) =>
        {
            e.Handled = true;
            SetTargeted(false);
            if (!e.DataView.Contains(StandardDataFormats.StorageItems)) return;
            Add((await e.DataView.GetStorageItemsAsync()).Select(i => i.Path).ToList());
        };
        Refresh();
    }

    void SetTargeted(bool targeted)
    {
        if (_targeted == targeted) return;
        _targeted = targeted;
        Refresh();
    }

    public void Add(IReadOnlyList<string> paths)
    {
        var config = _state.Config;
        _ = Task.Run(() =>
        {
            var items = MediaCompressionEngine.GatherMediaFiles(paths)
                .Select(p => new StagedQueueItem(p, new FileInfo(p).Length, MediaTypes.Classify(p), config)).ToList();
            _host.DispatcherQueue.TryEnqueue(() =>
            {
                // The same file dropped twice stays one entry.
                _items.AddRange(items.Where(n => !_items.Any(o => string.Equals(o.FilePath, n.FilePath, StringComparison.OrdinalIgnoreCase))));
                Refresh();
            });
        });
    }

    /// <summary>Rebuilds the queue area; also called when the accent colour changes.</summary>
    public void Refresh()
    {
        _host.Children.Clear();
        _host.Children.Add(_items.Count == 0 ? EmptyRow() : QueueCard());
    }

    UIElement EmptyRow()
    {
        var detail = Ui.Text("Drop files here to set options per file before squeezing", 10.5, secondary: true);
        detail.TextWrapping = TextWrapping.Wrap;
        var content = new StackPanel
        {
            Orientation = Orientation.Horizontal, Spacing = 10,
            Children =
            {
                Ui.Icon(_targeted ? "" : "", 13, _targeted ? Ui.AccentBrush : Ui.Secondary),
                new StackPanel { Spacing = 2, Children = { Ui.Text(_targeted ? "Drop to Add to Queue" : "Review settings first", 12, semibold: true), detail } },
            },
        };
        var row = new Button
        {
            Style = (Style)Application.Current.Resources["Plain"], Content = content, CornerRadius = new CornerRadius(10), Padding = new Thickness(12, 10, 12, 10),
            HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Left, BorderThickness = new Thickness(1.5),
            Background = new SolidColorBrush(_targeted ? Color.FromArgb(31, Ui.Accent.R, Ui.Accent.G, Ui.Accent.B) : Color.FromArgb(10, 255, 255, 255)),
            BorderBrush = new SolidColorBrush(_targeted ? Color.FromArgb(204, Ui.Accent.R, Ui.Accent.G, Ui.Accent.B) : Microsoft.UI.Colors.Transparent),
        };
        AutomationProperties.SetName(row, "Review settings first");
        ToolTipService.SetToolTip(row, "Drop files here, or click to choose files to review before squeezing");
        row.Click += async (_, _) => { if (await _window.PickFilesAsync() is { Count: > 0 } files) Add(files); };
        return row;
    }

    UIElement QueueCard()
    {
        var squeeze = new Button
        {
            Style = (Style)Application.Current.Resources["Plain"], Content = Ui.Text($"Squeeze {_items.Count}", 11, semibold: true),
            Background = Ui.AccentBrush, Foreground = Ui.OnAccent, CornerRadius = new CornerRadius(11), Padding = new Thickness(10, 3, 10, 3),
        };
        ((TextBlock)squeeze.Content).Foreground = Ui.OnAccent;
        AutomationProperties.SetName(squeeze, "Squeeze queue");
        squeeze.Click += (_, _) =>
        {
            var batch = _items.ToList();
            var config = _state.Config;
            _items.Clear();
            Refresh();
            _ = Task.Run(() => _state.Engine.ProcessStagedAsync(batch, config));
        };
        var clear = new Button { Style = (Style)Application.Current.Resources["Plain"], Content = Ui.Text("Clear", 11, secondary: true), Padding = new Thickness(6, 3, 6, 3), CornerRadius = new CornerRadius(6) };
        AutomationProperties.SetName(clear, "Clear queue");
        clear.Click += (_, _) => { _items.Clear(); Refresh(); };

        var header = new Grid();
        header.Children.Add(Ui.Text($"Queue · {_items.Count} {(_items.Count == 1 ? "file" : "files")}", 12, semibold: true));
        header.Children.Add(new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, HorizontalAlignment = HorizontalAlignment.Right, Children = { clear, squeeze } });

        var list = new StackPanel { Spacing = 6, Children = { header } };
        foreach (var item in _items)
        {
            var name = Ui.Text(System.IO.Path.GetFileName(item.FilePath), 12, semibold: true);
            name.TextTrimming = TextTrimming.CharacterEllipsis;
            var summary = Ui.Text(Summary(item), 10.5, secondary: true);
            var settings = Ui.IconButton("", "File settings");
            settings.Flyout = new Flyout { Content = SettingsPanel(item, () => summary.Text = Summary(item)), Placement = FlyoutPlacementMode.BottomEdgeAlignedRight };
            var remove = Ui.IconButton("", "Remove from queue");
            remove.Click += (_, _) => { _items.Remove(item); Refresh(); };

            var row = new Grid { ColumnSpacing = 8 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.Children.Add(new StackPanel { Spacing = 2, Children = { name, summary } });
            Grid.SetColumn(settings, 1); row.Children.Add(settings);
            Grid.SetColumn(remove, 2); row.Children.Add(remove);
            list.Children.Add(new Border { Child = row, Padding = new Thickness(10, 7, 6, 7), CornerRadius = new CornerRadius(8), Background = new SolidColorBrush(Color.FromArgb(10, 255, 255, 255)) });
        }
        var card = Ui.Card(list);
        if (_targeted) card.BorderBrush = Ui.AccentBrush;
        return card;
    }

    static string Summary(StagedQueueItem item)
    {
        string size = Ui.Bytes(item.OriginalSize);
        if (item.CustomTargetSizeMode != TargetSizeMode.Off)
            size += $"  ·  ≤ {new CompressionConfiguration { TargetSizeMode = item.CustomTargetSizeMode, CustomTargetSizeMB = item.CustomTargetSizeMB }.EffectiveTargetSizeMB:0} MB";
        return item.MediaType switch
        {
            MediaType.Image => $"{size}  ·  {item.CustomQuality * 100:0}% quality",
            MediaType.Video => $"{size}  ·  {(item.CustomVideoCodec == VideoCodecPreference.H264 ? "H.264" : item.CustomVideoCodec == VideoCodecPreference.Gif ? "GIF" : "HEVC")}  ·  {item.CustomQuality * 100:0}%",
            MediaType.Audio => $"{size}  ·  {(int)item.CustomAudioBitrate / 1000} kbps",
            _ => $"{size}  ·  {(int)item.CustomPdfDpi} DPI",
        };
    }

    /// <summary>The per-file controls shown from a queue row's gear button.</summary>
    static StackPanel SettingsPanel(StagedQueueItem item, Action changed)
    {
        var panel = new StackPanel { Spacing = 12, Width = 340 };
        void Pills<T>(string title, IReadOnlyList<(T, string)> options, Func<T> get, Action<T> set)
        {
            panel.Children.Add(new StackPanel
            {
                Spacing = 6,
                Children = { Ui.Text(title, 11, semibold: true), new Ui.PillBar<T>(options, v => EqualityComparer<T>.Default.Equals(get(), v), v => { set(v); changed(); }).View },
            });
        }
        void Percent(string title, double minimum, Func<double> get, Action<double> set)
        {
            var value = Ui.Text($"{get() * 100:0}%", 10.5, semibold: true);
            value.Foreground = Ui.AccentBrush;
            value.HorizontalAlignment = HorizontalAlignment.Right;
            var slider = new Slider { Minimum = minimum * 100, Maximum = 100, StepFrequency = 5, Value = get() * 100, Foreground = Ui.AccentBrush, IsThumbToolTipEnabled = false };
            AutomationProperties.SetName(slider, title);
            slider.ValueChanged += (_, e) => { set(e.NewValue / 100); value.Text = $"{e.NewValue:0}%"; changed(); };
            var header = new Grid();
            header.Children.Add(Ui.Text(title, 11, semibold: true));
            header.Children.Add(value);
            panel.Children.Add(new StackPanel { Children = { header, slider } });
        }
        void Switch(string title, Func<bool> get, Action<bool> set)
        {
            var row = new Grid();
            row.Children.Add(Ui.Text(title, 12));
            var toggle = Ui.Toggle(get(), v => { set(v); changed(); }, title);
            toggle.HorizontalAlignment = HorizontalAlignment.Right;
            row.Children.Add(toggle);
            panel.Children.Add(row);
        }

        Pills("Target size", [(TargetSizeMode.Off, "Manual"), (TargetSizeMode.Discord50, "50 MB"), (TargetSizeMode.Discord25, "25 MB"), (TargetSizeMode.Email10, "10 MB"), (TargetSizeMode.Web2, "2 MB")],
            () => item.CustomTargetSizeMode, v => item.CustomTargetSizeMode = v);
        switch (item.MediaType)
        {
            case MediaType.Image:
                Percent("Quality", 0.30, () => item.CustomQuality, v => item.CustomQuality = v);
                Percent("Resolution", 0.25, () => item.CustomResolutionScale, v => item.CustomResolutionScale = v);
                var formats = new List<(ImageFormatPolicy, string)> { (ImageFormatPolicy.PreserveOriginal, "Original"), (ImageFormatPolicy.JpegStandard, "JPEG"), (ImageFormatPolicy.PngLossless, "PNG") };
                if (Compressors.CanEncodeImage("webp")) formats.Add((ImageFormatPolicy.WebpModern, "WebP"));
                if (Compressors.CanEncodeImage("avif")) formats.Add((ImageFormatPolicy.AvifModern, "AVIF"));
                if (Compressors.CanEncodeImage("heic")) formats.Insert(1, (ImageFormatPolicy.HeicModern, "HEIC"));
                Pills("Format", formats, () => item.CustomImageFormat, v => item.CustomImageFormat = v);
                Switch("Strip EXIF / metadata", () => item.StripMetadata, v => item.StripMetadata = v);
                break;
            case MediaType.Video:
                Percent("Quality", 0.30, () => item.CustomQuality, v => item.CustomQuality = v);
                Percent("Resolution", 0.25, () => item.CustomResolutionScale, v => item.CustomResolutionScale = v);
                var codecs = new List<(VideoCodecPreference, string)> { (VideoCodecPreference.Hevc, "HEVC"), (VideoCodecPreference.H264, "H.264") };
                if (Ffmpeg.IsAvailable) codecs.Add((VideoCodecPreference.Gif, "GIF"));
                Pills("Codec", codecs, () => item.CustomVideoCodec, v => item.CustomVideoCodec = v);
                Pills("Framerate", [(VideoFramerateOption.Original, "Original"), (VideoFramerateOption.Fps60, "60"), (VideoFramerateOption.Fps30, "30"), (VideoFramerateOption.Fps24, "24"), (VideoFramerateOption.Fps15, "15")],
                    () => item.CustomVideoFramerate, v => item.CustomVideoFramerate = v);
                Switch("Mute / remove audio", () => item.CustomVideoRemoveAudio, v => item.CustomVideoRemoveAudio = v);
                break;
            case MediaType.Audio:
                Pills("Bitrate (kbps)", Enum.GetValues<AudioBitratePreference>().Select(b => (b, $"{(int)b / 1000}")).ToList(), () => item.CustomAudioBitrate, v => item.CustomAudioBitrate = v);
                break;
            case MediaType.Pdf:
                Pills("Resolution (DPI)", [(PdfDpiOption.Dpi72, "72"), (PdfDpiOption.Dpi150, "150"), (PdfDpiOption.Dpi200, "200"), (PdfDpiOption.Dpi300, "300")], () => item.CustomPdfDpi, v => item.CustomPdfDpi = v);
                Percent("Image quality", 0.30, () => item.CustomPdfImageQuality, v => item.CustomPdfImageQuality = v);
                Switch("Grayscale", () => item.CustomPdfGrayscale, v => item.CustomPdfGrayscale = v);
                break;
        }
        return panel;
    }
}
