using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using SqueezeBar.Core;
using SqueezeBar.Media;
using Windows.UI;

namespace SqueezeBar;

enum FormatCategory { Images, Video, Audio, Pdf }

/// <summary>
/// The Activity tab's quick settings, mirroring the Mac app: four profile tiles that always show the
/// current presets, and a drawer under them with the controls for whichever tile is open.
/// </summary>
sealed class FormatDeck(Grid tiles, Border drawer, AppState state)
{
    FormatCategory? _open;

    CompressionConfiguration Config => state.Config;
    bool TargetMode => Config.TargetSizeMode != TargetSizeMode.Off;

    static (string Icon, string Title) Info(FormatCategory category) => category switch
    {
        FormatCategory.Images => ("", "Images"),
        FormatCategory.Video => ("", "Video"),
        FormatCategory.Audio => ("", "Audio"),
        _ => ("", "PDF"),
    };

    public void Refresh()
    {
        BuildTiles();
        BuildDrawer();
    }

    void Set(Func<CompressionConfiguration, CompressionConfiguration> change)
    {
        state.Update(change);
        BuildTiles();
    }

    // MARK: - Tiles

    void BuildTiles()
    {
        var c = Config;
        string Quality(double q) => $"{q * 100:0}% quality";
        (FormatCategory, string, string)[] summaries =
        [
            (FormatCategory.Images, ImageFormatName(c.ImageFormatPolicy),
                c.ImageResolutionScale < 1 ? $"{c.ImageQuality * 100:0}% · {c.ImageResolutionScale * 100:0}% size" : Quality(c.ImageQuality)),
            (FormatCategory.Video, c.VideoCodec switch { VideoCodecPreference.H264 => "H.264", VideoCodecPreference.Gif => "GIF", _ => "HEVC" },
                c.VideoFramerate == VideoFramerateOption.Original ? Quality(c.VideoQuality) : $"{(int)c.VideoFramerate} FPS · {c.VideoQuality * 100:0}%"),
            (FormatCategory.Audio, $"{(int)c.AudioBitrate / 1000} kbps", "AAC · M4A"),
            (FormatCategory.Pdf, $"{(int)c.PdfDpi} DPI", Quality(c.PdfImageQuality) + (c.PdfGrayscale ? " · Grayscale" : "")),
        ];

        tiles.Children.Clear();
        for (int i = 0; i < summaries.Length; i++)
        {
            var (category, primary, secondary) = summaries[i];
            var (icon, title) = Info(category);
            bool open = _open == category;

            var heading = new Grid { Height = 16, ColumnSpacing = 4 };
            heading.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            heading.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            heading.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var name = Ui.Text(title, 11, semibold: true, secondary: !open);
            var chevron = Ui.Icon(open ? "" : "", 7, open ? null : Ui.Secondary);
            heading.Children.Add(Ui.Icon(icon, 10.5));
            Grid.SetColumn(name, 1); heading.Children.Add(name);
            Grid.SetColumn(chevron, 2); heading.Children.Add(chevron);

            var value = Ui.Text(primary, 12, semibold: true);
            var detail = Ui.Text(secondary, 10.5, secondary: true);
            detail.TextTrimming = TextTrimming.CharacterEllipsis;

            var tile = new Button
            {
                Style = (Style)Application.Current.Resources["Plain"],
                // Long values ("Preserve Original") shrink to fit instead of being cut off, like the Mac tiles.
                Content = new StackPanel { Spacing = 4, Children = { heading, new Viewbox { Child = value, StretchDirection = StretchDirection.DownOnly, HorizontalAlignment = HorizontalAlignment.Left, Height = 17 }, detail } },
                MinHeight = 72, CornerRadius = new CornerRadius(10), Padding = new Thickness(9, 8, 9, 8),
                HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Stretch,
                VerticalContentAlignment = VerticalAlignment.Top, BorderThickness = new Thickness(1),
                Background = new SolidColorBrush(Color.FromArgb(open ? (byte)36 : (byte)12, 255, 255, 255)),
                BorderBrush = new SolidColorBrush(Color.FromArgb(open ? (byte)70 : (byte)18, 255, 255, 255)),
            };
            AutomationProperties.SetName(tile, $"{title} settings");
            ToolTipService.SetToolTip(tile, $"Click to toggle {title} compression settings");
            tile.Click += (_, _) => { _open = open ? null : category; Refresh(); };
            Grid.SetColumn(tile, i);
            tiles.Children.Add(tile);
        }
    }

    static string ImageFormatName(ImageFormatPolicy policy) => policy switch
    {
        ImageFormatPolicy.HeicModern => "HEIC",
        ImageFormatPolicy.PngLossless => "PNG",
        ImageFormatPolicy.JpegStandard => "JPEG",
        ImageFormatPolicy.WebpModern => "WebP",
        ImageFormatPolicy.AvifModern => "AVIF",
        _ => "Preserve Original",
    };

    // MARK: - Drawer

    void BuildDrawer()
    {
        if (_open is not FormatCategory category) { drawer.Visibility = Visibility.Collapsed; drawer.Child = null; return; }
        var (icon, title) = Info(category);

        var done = new Button
        {
            Style = (Style)Application.Current.Resources["Plain"],
            Content = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4, Children = { Ui.Text("Done", 11, semibold: true), Ui.Icon("", 8) } },
            CornerRadius = new CornerRadius(11), Padding = new Thickness(8, 3, 8, 3), BorderThickness = new Thickness(1), HorizontalAlignment = HorizontalAlignment.Right,
            Background = new SolidColorBrush(Color.FromArgb(26, 255, 255, 255)), BorderBrush = new SolidColorBrush(Color.FromArgb(46, 255, 255, 255)),
        };
        AutomationProperties.SetName(done, "Done");
        done.Click += (_, _) => { _open = null; Refresh(); };
        var header = new Grid { Margin = new Thickness(2, 0, 2, 2) };
        header.Children.Add(new StackPanel
        {
            Orientation = Orientation.Horizontal, Spacing = 5,
            Children = { Ui.Icon(icon, 10.5, Ui.AccentBrush), Ui.Text($"{title} Settings", 13, semibold: true) },
        });
        header.Children.Add(done);

        var sections = new List<UIElement> { TargetSection(category) };
        switch (category)
        {
            case FormatCategory.Images:
                sections.Add(SliderSection("", "Image Quality", Config.ImageQuality, 0.30, QualityPresets, v => Set(c => c with { ImageQuality = v }), lockedBy: "quality"));
                sections.Add(SliderSection("", "Resolution Scale", Config.ImageResolutionScale, 0.25, ScalePresets, v => Set(c => c with { ImageResolutionScale = v }), scale: true));
                var formats = new List<(ImageFormatPolicy, string)> { (ImageFormatPolicy.PreserveOriginal, "Original"), (ImageFormatPolicy.JpegStandard, "JPEG"), (ImageFormatPolicy.PngLossless, "PNG") };
                // WebP and AVIF come from the bundled FFmpeg; HEIC needs an HEVC encoder on this machine.
                if (Compressors.CanEncodeImage("webp")) formats.Add((ImageFormatPolicy.WebpModern, "WebP"));
                if (Compressors.CanEncodeImage("avif")) formats.Add((ImageFormatPolicy.AvifModern, "AVIF"));
                if (Compressors.CanEncodeImage("heic")) formats.Insert(1, (ImageFormatPolicy.HeicModern, "HEIC"));
                sections.Add(PillSection("", "Format Target", ImageFormatName(Config.ImageFormatPolicy), formats,
                    v => Config.ImageFormatPolicy == v, v => Set(c => c with { ImageFormatPolicy = v })));
                break;

            case FormatCategory.Video:
                sections.Add(SliderSection("", "Video Quality", Config.VideoQuality, 0.30, QualityPresets, v => Set(c => c with { VideoQuality = v }), lockedBy: "bitrate"));
                sections.Add(SliderSection("", "Resolution Scale", Config.VideoResolutionScale, 0.25, ScalePresets, v => Set(c => c with { VideoResolutionScale = v }), scale: true));
                sections.Add(PillSection("", "Framerate (FPS)", null,
                    [(VideoFramerateOption.Original, "Original"), (VideoFramerateOption.Fps60, "60"), (VideoFramerateOption.Fps50, "50"), (VideoFramerateOption.Fps30, "30"),
                     (VideoFramerateOption.Fps25, "25"), (VideoFramerateOption.Fps24, "24"), (VideoFramerateOption.Fps15, "15"), (VideoFramerateOption.Fps12, "12")],
                    v => Config.VideoFramerate == v, v => Set(c => c with { VideoFramerate = v })));
                var codecs = new List<(VideoCodecPreference, string)> { (VideoCodecPreference.Hevc, "HEVC / H.265"), (VideoCodecPreference.H264, "H.264 / AVC") };
                if (Ffmpeg.IsAvailable) codecs.Add((VideoCodecPreference.Gif, "Animated GIF"));
                sections.Add(PillSection("", "Format / Codec", null, codecs,
                    v => Config.VideoCodec == v, v => { Set(c => c with { VideoCodec = v }); BuildDrawer(); }));
                if (Config.VideoCodec == VideoCodecPreference.Gif)
                    sections.Add(PillSection("", "GIF Framerate", "Long edge capped at 640 px",
                        [(GifFramerateOption.Full, "Full FPS"), (GifFramerateOption.Smooth24, "24 FPS"), (GifFramerateOption.Half15, "15 FPS"), (GifFramerateOption.Compact10, "10 FPS")],
                        v => Config.GifFramerate == v, v => Set(c => c with { GifFramerate = v })));
                sections.Add(ToggleRow("Mute / Remove Audio Track", "Drops the sound for a smaller file", Config.VideoRemoveAudio, v => Set(c => c with { VideoRemoveAudio = v })));
                break;

            case FormatCategory.Audio:
                var bitrate = PillSection("", "Audio Bitrate", $"{(int)Config.AudioBitrate / 1000} kbps",
                    Enum.GetValues<AudioBitratePreference>().Select(b => (b, $"{(int)b / 1000}")).ToList(),
                    v => Config.AudioBitrate == v, v => { Set(c => c with { AudioBitrate = v }); BuildDrawer(); });
                sections.Add(Locked(bitrate, "bitrate"));
                break;

            case FormatCategory.Pdf:
                sections.Add(PillSection("", "Resolution", $"{(int)Config.PdfDpi} DPI",
                    [(PdfDpiOption.Dpi72, "72 Compact"), (PdfDpiOption.Dpi150, "150 Screen"), (PdfDpiOption.Dpi200, "200 Standard"), (PdfDpiOption.Dpi300, "300 Print")],
                    v => Config.PdfDpi == v, v => { Set(c => c with { PdfDpi = v }); BuildDrawer(); }));
                sections.Add(SliderSection("", "Image Quality", Config.PdfImageQuality, 0.30, QualityPresets, v => Set(c => c with { PdfImageQuality = v })));
                sections.Add(ToggleRow("Convert to Grayscale (B&W)", "Converts scans & images to monochrome for extra reduction", Config.PdfGrayscale, v => Set(c => c with { PdfGrayscale = v })));
                break;
        }

        // Sections share one surface, separated by hairlines rather than nested cards.
        var body = new StackPanel { Children = { header } };
        foreach (var section in sections)
        {
            body.Children.Add(new Border { Height = 1, Margin = new Thickness(0, 9, 0, 9), Background = new SolidColorBrush(Color.FromArgb(18, 255, 255, 255)) });
            body.Children.Add(section);
        }
        drawer.Child = body;
        drawer.Visibility = Visibility.Visible;
    }

    static readonly (double, string)[] QualityPresets = [(0.50, "Max Compression"), (0.75, "Balanced"), (0.90, "Visually Lossless")];
    static readonly (double, string)[] ScalePresets = [(0.25, "25%"), (0.50, "50%"), (0.75, "75%"), (1.0, "Original")];

    UIElement TargetSection(FormatCategory category)
    {
        var mode = Config.TargetSizeMode;
        var limit = Config.EffectiveTargetSizeMB;
        var value = Ui.Text(limit is double mb ? $"≤ {mb:0} MB" : "Manual Quality", 10.5, semibold: limit is not null, secondary: limit is null);
        if (limit is not null) value.Foreground = Ui.AccentBrush;

        var panel = new StackPanel { Spacing = 7, Children = { SectionHeader("", "Target Size Limit", value) } };
        panel.Children.Add(new Ui.PillBar<TargetSizeMode>(
            [(TargetSizeMode.Off, "Manual"), (TargetSizeMode.Discord50, "50 MB"), (TargetSizeMode.Discord25, "25 MB"),
             (TargetSizeMode.Email10, "10 MB"), (TargetSizeMode.Web2, "2 MB"), (TargetSizeMode.Custom, "Custom")],
            v => Config.TargetSizeMode == v,
            v => { Set(c => c with { TargetSizeMode = v }); BuildDrawer(); }).View);

        if (mode == TargetSizeMode.Custom)
        {
            var slider = new Slider { Minimum = 1, Maximum = 200, StepFrequency = 1, Value = Config.CustomTargetSizeMB, Foreground = Ui.AccentBrush, IsThumbToolTipEnabled = false };
            AutomationProperties.SetName(slider, "Custom Max Size");
            slider.ValueChanged += (_, e) => { Set(c => c with { CustomTargetSizeMB = e.NewValue }); value.Text = $"≤ {e.NewValue:0} MB"; };
            panel.Children.Add(slider);
        }
        if (mode == TargetSizeMode.Off) return panel;

        var note = Ui.Text(category switch
        {
            FormatCategory.Images => "Image quality is chosen automatically to fit the limit.",
            FormatCategory.Video => "Video bitrate is chosen automatically to fit the limit.",
            FormatCategory.Audio => "Audio bitrate is chosen automatically to fit the limit.",
            _ => "DPI and image quality act as upper limits; they're lowered only if needed.",
        }, 10.5, secondary: true);
        note.TextWrapping = TextWrapping.Wrap;
        panel.Children.Add(note);

        if (category is FormatCategory.Images or FormatCategory.Video)
            panel.Children.Add(ToggleRow("Keep original resolution", "Lowers quality instead of shrinking the picture",
                Config.PreserveResolutionInTargetMode, v => Set(c => c with { PreserveResolutionInTargetMode = v })));
        if (category is FormatCategory.Video)
            panel.Children.Add(ToggleRow("Keep audio at 128 kbps", "Otherwise audio drops to 48–96 kbps to leave room for video",
                Config.PreserveAudioQualityInTargetMode, v => Set(c => c with { PreserveAudioQualityInTargetMode = v })));
        return panel;
    }

    static Grid SectionHeader(string icon, string title, TextBlock? value)
    {
        var header = new Grid();
        header.Children.Add(new StackPanel { Orientation = Orientation.Horizontal, Spacing = 5, Children = { Ui.Icon(icon, 10.5), Ui.Text(title, 11, semibold: true) } });
        if (value is not null) { value.HorizontalAlignment = HorizontalAlignment.Right; header.Children.Add(value); }
        return header;
    }

    /// <summary>A slider from <paramref name="minimum"/> to 100% in 5% steps with quick-pick pills under it.</summary>
    UIElement SliderSection(string icon, string title, double current, double minimum, (double, string)[] presets, Action<double> set, string? lockedBy = null, bool scale = false)
    {
        string Label(double v) => scale && v >= 0.99 ? "Original (100%)" : $"{v * 100:0}%";
        static bool Near(double a, double b) => Math.Abs(a - b) < 0.01;

        var value = Ui.Text(Label(current), 10.5, semibold: true);
        value.Foreground = Ui.AccentBrush;
        var slider = new Slider { Minimum = minimum * 100, Maximum = 100, StepFrequency = 5, Value = current * 100, Foreground = Ui.AccentBrush, IsThumbToolTipEnabled = false };
        AutomationProperties.SetName(slider, title);
        Ui.PillBar<double>? pills = null;
        pills = new Ui.PillBar<double>(presets, v => Near(v, slider.Value / 100), v => slider.Value = v * 100);
        slider.ValueChanged += (_, e) =>
        {
            double v = e.NewValue / 100;
            value.Text = Label(v);
            pills.Select(p => Near(p, v));
            set(v);
        };
        var panel = new StackPanel { Spacing = 7, Children = { SectionHeader(icon, title, value), slider, pills.View } };
        return lockedBy is null ? panel : Locked(panel, lockedBy);
    }

    static StackPanel PillSection<T>(string icon, string title, string? summary, IReadOnlyList<(T, string)> options, Func<T, bool> isSelected, Action<T> onPick)
    {
        TextBlock? value = null;
        if (summary is not null) { value = Ui.Text(summary, 10.5, semibold: true); value.Foreground = Ui.AccentBrush; }
        return new StackPanel { Spacing = 7, Children = { SectionHeader(icon, title, value), new Ui.PillBar<T>(options, isSelected, onPick).View } };
    }

    /// <summary>In a target-size mode the engine derives this from the limit, so it is dimmed and explained instead of silently ignored.</summary>
    UIElement Locked(FrameworkElement section, string what)
    {
        if (!TargetMode) return section;
        section.Opacity = 0.4;
        section.IsHitTestVisible = false;
        if (section is Control control) control.IsEnabled = false;
        var note = Ui.Text($"Set automatically: the target size decides the {what}.", 10.5, secondary: true);
        return new StackPanel { Spacing = 6, Children = { section, note } };
    }

    static Grid ToggleRow(string title, string subtitle, bool value, Action<bool> set)
    {
        var toggle = Ui.Toggle(value, set, title);
        var detail = Ui.Text(subtitle, 10.5, secondary: true);
        detail.TextWrapping = TextWrapping.Wrap;
        var row = new Grid { ColumnSpacing = 10 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.Children.Add(new StackPanel { Spacing = 1, VerticalAlignment = VerticalAlignment.Center, Children = { Ui.Text(title, 12, semibold: true), detail } });
        Grid.SetColumn(toggle, 1);
        row.Children.Add(toggle);
        return row;
    }
}
