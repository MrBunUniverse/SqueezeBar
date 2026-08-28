using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Media;
using Avalonia.Platform.Storage;
using Avalonia.VisualTree;
using SqueezeBar.Models;
using SqueezeBar.Services;

namespace SqueezeBar.Views;

public partial class MainWindow : Window
{
    private readonly AppState _state = AppState.Shared;

    public MainWindow()
    {
        InitializeComponent();

        StagedQueueItemsList.ItemsSource = _state.StagedQueue;
        HistoryItemsList.ItemsSource = _state.History;
        ActiveJobsList.ItemsSource = _state.ActiveJobs;
        WatchedFoldersList.ItemsSource = _state.WatchedFolders;

        _state.PropertyChanged += (s, e) =>
        {
            if (e.PropertyName == nameof(_state.FormattedTotalSaved))
            {
                SavedStatsText.Text = $"{_state.FormattedTotalSaved} Saved";
                LifetimeSavedText.Text = _state.FormattedTotalSaved;
            }
            else if (e.PropertyName == nameof(_state.TotalFilesSqueezed))
            {
                LifetimeFilesText.Text = $"{_state.TotalFilesSqueezed} files";
            }
            else if (e.PropertyName == nameof(_state.StagedQueueCountText))
            {
                QueueHeaderTitle.Text = _state.StagedQueueCountText;
                SqueezeAllBtn.Content = _state.StagedQueue.Count > 0 ? $"Squeeze All ({_state.StagedQueue.Count})" : "Squeeze All";
                EmptyQueueHint.IsVisible = _state.StagedQueue.Count == 0;
            }
            else if (e.PropertyName == nameof(_state.IsProcessing))
            {
                ProcessingBadge.IsVisible = _state.IsProcessing;
                ActiveJobsBorder.IsVisible = _state.ActiveJobs.Count > 0;
                FooterStatusText.Text = _state.IsProcessing ? "Optimizing..." : "Ready";
            }
            else if (e.PropertyName == nameof(_state.ImageSummaryText) ||
                     e.PropertyName == nameof(_state.VideoSummaryText) ||
                     e.PropertyName == nameof(_state.AudioSummaryText) ||
                     e.PropertyName == nameof(_state.PdfSummaryText))
            {
                UpdateCategoryTileDisplays();
            }
        };

        UpdateCategoryTileDisplays();

        // Sliders
        ImgQualitySlider.Value = _state.ImageQuality;
        ImgQualitySlider.PropertyChanged += (s, e) =>
        {
            if (e.Property.Name == nameof(Slider.Value))
            {
                _state.ImageQuality = ImgQualitySlider.Value;
                ImgQualityPercentText.Text = $"{_state.ImageQualityPercent}%";
            }
        };

        ImgScaleSlider.Value = _state.ImageResolutionScale;
        ImgScaleSlider.PropertyChanged += (s, e) =>
        {
            if (e.Property.Name == nameof(Slider.Value))
            {
                _state.ImageResolutionScale = ImgScaleSlider.Value;
                ImgResolutionScaleText.Text = _state.ImageResolutionScale >= 0.99 ? "Original (100%)" : $"{(int)(_state.ImageResolutionScale * 100)}% Scale";
            }
        };

        VidQualitySlider.Value = _state.VideoQuality;
        VidQualitySlider.PropertyChanged += (s, e) =>
        {
            if (e.Property.Name == nameof(Slider.Value))
            {
                _state.VideoQuality = VidQualitySlider.Value;
                VidBitratePercentText.Text = $"{_state.VideoQualityPercent}% of source";
            }
        };

        VidScaleSlider.Value = _state.VideoResolutionScale;
        VidScaleSlider.PropertyChanged += (s, e) =>
        {
            if (e.Property.Name == nameof(Slider.Value))
            {
                _state.VideoResolutionScale = VidScaleSlider.Value;
                VidResolutionScaleText.Text = _state.VideoResolutionScale >= 0.99 ? "Original (100%)" : $"{(int)(_state.VideoResolutionScale * 100)}% Scale";
            }
        };

        CustomTargetSizeSlider.Value = _state.CustomTargetSizeMB;
        CustomTargetSizeSlider.PropertyChanged += (s, e) =>
        {
            if (e.Property.Name == nameof(Slider.Value))
            {
                _state.CustomTargetSizeMB = CustomTargetSizeSlider.Value;
                CustomTargetSizeLabel.Text = $"{_state.CustomTargetSizeMB:F0} MB";
                TargetLimitDisplay.Text = $"≤ {_state.CustomTargetSizeMB:F0} MB";
            }
        };

        LockResolutionCheck.IsChecked = _state.PreserveResolutionInTargetMode;
        LockResolutionCheck.IsCheckedChanged += (s, e) => _state.PreserveResolutionInTargetMode = LockResolutionCheck.IsChecked ?? true;

        LockAudioCheck.IsChecked = _state.PreserveAudioQualityInTargetMode;
        LockAudioCheck.IsCheckedChanged += (s, e) => _state.PreserveAudioQualityInTargetMode = LockAudioCheck.IsChecked ?? false;

        RemoveAudioCheck.IsChecked = _state.VideoRemoveAudio;
        RemoveAudioCheck.IsCheckedChanged += (s, e) => _state.VideoRemoveAudio = RemoveAudioCheck.IsChecked ?? false;

        PdfGrayscaleCheck.IsChecked = _state.PdfGrayscale;
        PdfGrayscaleCheck.IsCheckedChanged += (s, e) => _state.PdfGrayscale = PdfGrayscaleCheck.IsChecked ?? false;

        SettingsSuffixBox.PropertyChanged += (s, e) =>
        {
            if (e.Property.Name == nameof(TextBox.Text))
                _state.OutputSuffix = SettingsSuffixBox.Text?.Trim() ?? "_squeezed";
        };

        ReplaceOriginalCheck.IsCheckedChanged += (s, e) => _state.ReplaceOriginal = ReplaceOriginalCheck.IsChecked ?? false;
        StripMetadataCheck.IsCheckedChanged += (s, e) => _state.StripMetadata = StripMetadataCheck.IsChecked ?? true;

        // Drag & Drop
        DragDrop.SetAllowDrop(this, true);
        AddHandler(DragDrop.DragOverEvent, OnDragOver);
        AddHandler(DragDrop.DragEnterEvent, OnDragEnter);
        AddHandler(DragDrop.DropEvent, OnWindowDrop);

        DragDrop.SetAllowDrop(QuickDropBorder, true);
        QuickDropBorder.AddHandler(DragDrop.DropEvent, OnQuickDrop);
        QuickDropBorder.AddHandler(DragDrop.DragOverEvent, OnDragOver);
        QuickDropBorder.AddHandler(DragDrop.DragEnterEvent, OnDragEnter);

        DragDrop.SetAllowDrop(StagedQueueBorder, true);
        StagedQueueBorder.AddHandler(DragDrop.DropEvent, OnStagedDrop);
        StagedQueueBorder.AddHandler(DragDrop.DragOverEvent, OnDragOver);
        StagedQueueBorder.AddHandler(DragDrop.DragEnterEvent, OnDragEnter);

        EmptyQueueHint.IsVisible = _state.StagedQueue.Count == 0;        // Prevent Wine / CrossOver from maximizing into a new macOS Fullscreen Space
        PropertyChanged += (s, e) =>
        {
            if (e.Property == Window.WindowStateProperty && WindowState != WindowState.Normal)
            {
                WindowState = WindowState.Normal;
            }
        };

        AddHandler(InputElement.DoubleTappedEvent, (s, e) =>
        {
            e.Handled = true;
        }, RoutingStrategies.Bubble);

        ApplyBackgroundDarkness(_state.BackgroundDarkness);
    }

    // ── Tab Navigation ──
    private void ActivityTab_Click(object? sender, RoutedEventArgs e)
    {
        _state.SelectedTab = PopoverTab.Activity;
        ActivityTabPanel.IsVisible = true;
        SettingsTabPanel.IsVisible = false;
        ActivityTabBtn.Background = SolidColorBrush.Parse("#2A2A2F");
        ActivityTabBtn.BorderBrush = SolidColorBrush.Parse("#353539");
        SettingsTabBtn.Background = Brushes.Transparent;
    }

    private void SettingsTab_Click(object? sender, RoutedEventArgs e)
    {
        _state.SelectedTab = PopoverTab.Settings;
        ActivityTabPanel.IsVisible = false;
        SettingsTabPanel.IsVisible = true;
        SettingsTabBtn.Background = SolidColorBrush.Parse("#2A2A2F");
        ActivityTabBtn.Background = Brushes.Transparent;
        ActivityTabBtn.BorderBrush = Brushes.Transparent;
    }

    // ── Category Tile Selection (Toggle Drawer) ──
    private void SelectImagesCategory_PointerPressed(object? sender, PointerPressedEventArgs e)
    {
        e.Handled = true;
        ToggleCategory(MediaCategory.Images);
    }
    private void SelectVideoCategory_PointerPressed(object? sender, PointerPressedEventArgs e)
    {
        e.Handled = true;
        ToggleCategory(MediaCategory.Video);
    }
    private void SelectAudioCategory_PointerPressed(object? sender, PointerPressedEventArgs e)
    {
        e.Handled = true;
        ToggleCategory(MediaCategory.Audio);
    }
    private void SelectPdfCategory_PointerPressed(object? sender, PointerPressedEventArgs e)
    {
        e.Handled = true;
        ToggleCategory(MediaCategory.Pdf);
    }

    private void CloseDrawer_Click(object? sender, RoutedEventArgs e)
    {
        _state.IsFormatDrawerExpanded = false;
        FormatDrawerBorder.IsVisible = false;
        UpdateTileStyles();
    }

    private void ToggleCategory(MediaCategory category)
    {
        if (_state.ActiveFormatCategory == category && _state.IsFormatDrawerExpanded)
        {
            _state.IsFormatDrawerExpanded = false;
            FormatDrawerBorder.IsVisible = false;
        }
        else
        {
            _state.ActiveFormatCategory = category;
            _state.IsFormatDrawerExpanded = true;
            FormatDrawerBorder.IsVisible = true;

            DrawerCategoryTitle.Text = category switch
            {
                MediaCategory.Images => "Image Settings",
                MediaCategory.Video => "Video Settings",
                MediaCategory.Audio => "Audio Settings",
                MediaCategory.Pdf => "PDF Settings",
                _ => "Format Settings"
            };

            ImagesDeckPanel.IsVisible = category == MediaCategory.Images;
            VideoDeckPanel.IsVisible = category == MediaCategory.Video;
            AudioDeckPanel.IsVisible = category == MediaCategory.Audio;
            PdfDeckPanel.IsVisible = category == MediaCategory.Pdf;
            LockAudioCheck.IsVisible = category == MediaCategory.Video;
        }
        UpdateTileStyles();
        UpdateCategoryTileDisplays();
    }

    private void UpdateCategoryTileDisplays()
    {
        // Images
        var imgFmt = _state.ImageFormatPolicy switch
        {
            ImageFormatPolicy.ModernWebP => "Modern WebP",
            ImageFormatPolicy.WebJPEG => "Web JPEG",
            _ => "Preserve Original"
        };
        string imgScale = _state.ImageResolutionScale >= 0.99 ? "100%" : $"{(int)(_state.ImageResolutionScale * 100)}%";
        ImagesTileFormat.Text = imgFmt;
        ImagesTileQuality.Text = $"{_state.ImageQualityPercent}% Quality • {imgScale} Scale";

        // Video
        var vidCodec = _state.VideoCodec switch
        {
            VideoCodecPreference.H264 => "H.264",
            VideoCodecPreference.AnimatedGIF => "GIF",
            _ => "HEVC"
        };
        var vidFps = _state.VideoFramerate > 0 ? $"{_state.VideoFramerate} FPS" : "Original";
        string vidScale = _state.VideoResolutionScale >= 0.99 ? "100%" : $"{(int)(_state.VideoResolutionScale * 100)}%";
        VideoTileCodec.Text = $"{vidCodec} • {vidFps}";
        VideoTileQuality.Text = $"{_state.VideoQualityPercent}% Quality • {vidScale} Scale";

        // Audio
        AudioTileBitrate.Text = $"{_state.AudioBitrate.ToString().TrimStart('K')} kbps";
        AudioTileSubtitle.Text = "AAC Stereo";

        // PDF
        PdfTileDpi.Text = $"{_state.PdfDpi} DPI";
        PdfTileSubtitle.Text = _state.PdfGrayscale ? "Grayscale • Optimized" : "Optimized";
    }

    private void UpdateTileStyles()
    {
        var accentBrush = SolidColorBrush.Parse(_state.AccentColorHex);
        string defaultBorderHex = _state.BackgroundDarkness switch
        {
            BackgroundDarkness.ReallyDark => "#222228",
            BackgroundDarkness.Oled => "#1A1A20",
            _ => "#2D2D32"
        };
        string defaultBgHex = _state.BackgroundDarkness switch
        {
            BackgroundDarkness.ReallyDark => "#18181D",
            BackgroundDarkness.Oled => "#0E0E11",
            _ => "#222226"
        };
        string activeBgHex = _state.BackgroundDarkness switch
        {
            BackgroundDarkness.ReallyDark => "#14242C",
            BackgroundDarkness.Oled => "#0D1820",
            _ => "#172C35"
        };

        var defaultBorder = SolidColorBrush.Parse(defaultBorderHex);
        var defaultBg = SolidColorBrush.Parse(defaultBgHex);
        var activeBg = SolidColorBrush.Parse(activeBgHex);
        var defaultTitle = SolidColorBrush.Parse("#B0B0BE");
        var mutedChevron = SolidColorBrush.Parse("#55556A");
        bool exp = _state.IsFormatDrawerExpanded;

        // Images
        bool imgActive = exp && _state.ActiveFormatCategory == MediaCategory.Images;
        ImagesTileBorder.BorderBrush = imgActive ? accentBrush : defaultBorder;
        ImagesTileBorder.BorderThickness = imgActive ? new Thickness(1.5) : new Thickness(0.5);
        ImagesTileBorder.Background = imgActive ? activeBg : defaultBg;
        ImagesTitleText.Foreground = imgActive ? accentBrush : defaultTitle;
        ImagesChevron.Text = imgActive ? "▲" : "▼";
        ImagesChevron.Foreground = imgActive ? accentBrush : mutedChevron;

        // Video
        bool vidActive = exp && _state.ActiveFormatCategory == MediaCategory.Video;
        VideoTileBorder.BorderBrush = vidActive ? accentBrush : defaultBorder;
        VideoTileBorder.BorderThickness = vidActive ? new Thickness(1.5) : new Thickness(0.5);
        VideoTileBorder.Background = vidActive ? activeBg : defaultBg;
        VideoTitleText.Foreground = vidActive ? accentBrush : defaultTitle;
        VideoChevron.Text = vidActive ? "▲" : "▼";
        VideoChevron.Foreground = vidActive ? accentBrush : mutedChevron;

        // Audio
        bool audActive = exp && _state.ActiveFormatCategory == MediaCategory.Audio;
        AudioTileBorder.BorderBrush = audActive ? accentBrush : defaultBorder;
        AudioTileBorder.BorderThickness = audActive ? new Thickness(1.5) : new Thickness(0.5);
        AudioTileBorder.Background = audActive ? activeBg : defaultBg;
        AudioTitleText.Foreground = audActive ? accentBrush : defaultTitle;
        AudioChevron.Text = audActive ? "▲" : "▼";
        AudioChevron.Foreground = audActive ? accentBrush : mutedChevron;

        // PDF
        bool pdfActive = exp && _state.ActiveFormatCategory == MediaCategory.Pdf;
        PdfTileBorder.BorderBrush = pdfActive ? accentBrush : defaultBorder;
        PdfTileBorder.BorderThickness = pdfActive ? new Thickness(1.5) : new Thickness(0.5);
        PdfTileBorder.Background = pdfActive ? activeBg : defaultBg;
        PdfTitleText.Foreground = pdfActive ? accentBrush : defaultTitle;
        PdfChevron.Text = pdfActive ? "▲" : "▼";
        PdfChevron.Foreground = pdfActive ? accentBrush : mutedChevron;
    }

    // ── Target Size Limits ──
    private void PresetOff_Click(object? sender, RoutedEventArgs e) { _state.TargetSizeMode = TargetSizeMode.Off; TargetLimitDisplay.Text = "Manual"; CustomTargetSizePanel.IsVisible = false; UpdatePresetButtonStyles(PresetOffBtn); }
    private void Preset50_Click(object? sender, RoutedEventArgs e) { _state.TargetSizeMode = TargetSizeMode.Discord50; TargetLimitDisplay.Text = "≤ 50 MB"; CustomTargetSizePanel.IsVisible = false; UpdatePresetButtonStyles(Preset50Btn); }
    private void Preset25_Click(object? sender, RoutedEventArgs e) { _state.TargetSizeMode = TargetSizeMode.Discord25; TargetLimitDisplay.Text = "≤ 25 MB"; CustomTargetSizePanel.IsVisible = false; UpdatePresetButtonStyles(Preset25Btn); }
    private void Preset10_Click(object? sender, RoutedEventArgs e) { _state.TargetSizeMode = TargetSizeMode.Email10; TargetLimitDisplay.Text = "≤ 10 MB"; CustomTargetSizePanel.IsVisible = false; UpdatePresetButtonStyles(Preset10Btn); }
    private void Preset2_Click(object? sender, RoutedEventArgs e) { _state.TargetSizeMode = TargetSizeMode.Custom; _state.CustomTargetSizeMB = 2.0; TargetLimitDisplay.Text = "≤ 2 MB"; CustomTargetSizePanel.IsVisible = false; UpdatePresetButtonStyles(Preset2Btn); }
    private void PresetCustom_Click(object? sender, RoutedEventArgs e) { _state.TargetSizeMode = TargetSizeMode.Custom; TargetLimitDisplay.Text = $"≤ {_state.CustomTargetSizeMB:F0} MB"; CustomTargetSizePanel.IsVisible = true; UpdatePresetButtonStyles(PresetCustomBtn); }

    private void UpdatePresetButtonStyles(Button activeBtn)
    {
        string inactiveHex = _state.BackgroundDarkness switch
        {
            BackgroundDarkness.ReallyDark => "#1B1B20",
            BackgroundDarkness.Oled => "#141418",
            _ => "#28282C"
        };
        string borderHex = _state.BackgroundDarkness switch
        {
            BackgroundDarkness.ReallyDark => "#222228",
            BackgroundDarkness.Oled => "#1A1A20",
            _ => "#2D2D32"
        };

        var inactive = SolidColorBrush.Parse(inactiveHex);
        var activeBg = SolidColorBrush.Parse(_state.AccentColorHex);
        var inactiveFg = SolidColorBrush.Parse("#A0A0B0");

        foreach (var btn in new[] { PresetOffBtn, Preset50Btn, Preset25Btn, Preset10Btn, Preset2Btn, PresetCustomBtn })
        {
            btn.Background = inactive;
            btn.Foreground = inactiveFg;
            btn.BorderBrush = SolidColorBrush.Parse(borderHex);
            btn.FontWeight = FontWeight.Normal;
        }
        activeBtn.Background = activeBg;
        activeBtn.Foreground = Brushes.Black;
        activeBtn.BorderBrush = Brushes.Transparent;
        activeBtn.FontWeight = FontWeight.SemiBold;
    }

    // ── Video Presets & Controls ──
    private void VidPresetMax_Click(object? sender, RoutedEventArgs e) { _state.VideoQuality = 0.35; VidQualitySlider.Value = 0.35; UpdatePillGroup(VidPresetMaxBtn, VidPresetBalBtn, VidPresetLosslessBtn); }
    private void VidPresetBal_Click(object? sender, RoutedEventArgs e) { _state.VideoQuality = 0.70; VidQualitySlider.Value = 0.70; UpdatePillGroup(VidPresetBalBtn, VidPresetMaxBtn, VidPresetLosslessBtn); }
    private void VidPresetLossless_Click(object? sender, RoutedEventArgs e) { _state.VideoQuality = 0.95; VidQualitySlider.Value = 0.95; UpdatePillGroup(VidPresetLosslessBtn, VidPresetMaxBtn, VidPresetBalBtn); }

    private void VidScale25_Click(object? sender, RoutedEventArgs e) { _state.VideoResolutionScale = 0.25; VidScaleSlider.Value = 0.25; UpdatePillGroup(VidScale25Btn, VidScale50Btn, VidScale75Btn, VidScale100Btn); }
    private void VidScale50_Click(object? sender, RoutedEventArgs e) { _state.VideoResolutionScale = 0.50; VidScaleSlider.Value = 0.50; UpdatePillGroup(VidScale50Btn, VidScale25Btn, VidScale75Btn, VidScale100Btn); }
    private void VidScale75_Click(object? sender, RoutedEventArgs e) { _state.VideoResolutionScale = 0.75; VidScaleSlider.Value = 0.75; UpdatePillGroup(VidScale75Btn, VidScale25Btn, VidScale50Btn, VidScale100Btn); }
    private void VidScale100_Click(object? sender, RoutedEventArgs e) { _state.VideoResolutionScale = 1.0; VidScaleSlider.Value = 1.0; UpdatePillGroup(VidScale100Btn, VidScale25Btn, VidScale50Btn, VidScale75Btn); }

    private void FpsOrig_Click(object? sender, RoutedEventArgs e) { _state.VideoFramerate = 0; VidFramerateText.Text = "Original"; UpdatePillGroup(FpsOrigBtn, Fps60Btn, Fps50Btn, Fps30Btn, Fps25Btn, Fps24Btn, Fps15Btn, Fps12Btn); }
    private void Fps60_Click(object? sender, RoutedEventArgs e) { _state.VideoFramerate = 60; VidFramerateText.Text = "60 FPS"; UpdatePillGroup(Fps60Btn, FpsOrigBtn, Fps50Btn, Fps30Btn, Fps25Btn, Fps24Btn, Fps15Btn, Fps12Btn); }
    private void Fps50_Click(object? sender, RoutedEventArgs e) { _state.VideoFramerate = 50; VidFramerateText.Text = "50 FPS"; UpdatePillGroup(Fps50Btn, FpsOrigBtn, Fps60Btn, Fps30Btn, Fps25Btn, Fps24Btn, Fps15Btn, Fps12Btn); }
    private void Fps30_Click(object? sender, RoutedEventArgs e) { _state.VideoFramerate = 30; VidFramerateText.Text = "30 FPS"; UpdatePillGroup(Fps30Btn, FpsOrigBtn, Fps60Btn, Fps50Btn, Fps25Btn, Fps24Btn, Fps15Btn, Fps12Btn); }
    private void Fps25_Click(object? sender, RoutedEventArgs e) { _state.VideoFramerate = 25; VidFramerateText.Text = "25 FPS"; UpdatePillGroup(Fps25Btn, FpsOrigBtn, Fps60Btn, Fps50Btn, Fps30Btn, Fps24Btn, Fps15Btn, Fps12Btn); }
    private void Fps24_Click(object? sender, RoutedEventArgs e) { _state.VideoFramerate = 24; VidFramerateText.Text = "24 FPS"; UpdatePillGroup(Fps24Btn, FpsOrigBtn, Fps60Btn, Fps50Btn, Fps30Btn, Fps25Btn, Fps15Btn, Fps12Btn); }
    private void Fps15_Click(object? sender, RoutedEventArgs e) { _state.VideoFramerate = 15; VidFramerateText.Text = "15 FPS"; UpdatePillGroup(Fps15Btn, FpsOrigBtn, Fps60Btn, Fps50Btn, Fps30Btn, Fps25Btn, Fps24Btn, Fps12Btn); }
    private void Fps12_Click(object? sender, RoutedEventArgs e) { _state.VideoFramerate = 12; VidFramerateText.Text = "12 FPS"; UpdatePillGroup(Fps12Btn, FpsOrigBtn, Fps60Btn, Fps50Btn, Fps30Btn, Fps25Btn, Fps24Btn, Fps15Btn); }

    private void CodecHevc_Click(object? sender, RoutedEventArgs e) { _state.VideoCodec = VideoCodecPreference.HEVC; UpdatePillGroup(CodecHevcBtn, CodecH264Btn, CodecGifBtn); }
    private void CodecH264_Click(object? sender, RoutedEventArgs e) { _state.VideoCodec = VideoCodecPreference.H264; UpdatePillGroup(CodecH264Btn, CodecHevcBtn, CodecGifBtn); }
    private void CodecGif_Click(object? sender, RoutedEventArgs e) { _state.VideoCodec = VideoCodecPreference.AnimatedGIF; UpdatePillGroup(CodecGifBtn, CodecHevcBtn, CodecH264Btn); }

    // ── Image Presets & Formats ──
    private void ImgPresetMax_Click(object? sender, RoutedEventArgs e) { _state.ImageQuality = 0.50; ImgQualitySlider.Value = 0.50; UpdatePillGroup(ImgPresetMaxBtn, ImgPresetBalBtn, ImgPresetLosslessBtn); }
    private void ImgPresetBal_Click(object? sender, RoutedEventArgs e) { _state.ImageQuality = 0.80; ImgQualitySlider.Value = 0.80; UpdatePillGroup(ImgPresetBalBtn, ImgPresetMaxBtn, ImgPresetLosslessBtn); }
    private void ImgPresetLossless_Click(object? sender, RoutedEventArgs e) { _state.ImageQuality = 0.95; ImgQualitySlider.Value = 0.95; UpdatePillGroup(ImgPresetLosslessBtn, ImgPresetMaxBtn, ImgPresetBalBtn); }

    private void ImgScale25_Click(object? sender, RoutedEventArgs e) { _state.ImageResolutionScale = 0.25; ImgScaleSlider.Value = 0.25; UpdatePillGroup(ImgScale25Btn, ImgScale50Btn, ImgScale75Btn, ImgScale100Btn); }
    private void ImgScale50_Click(object? sender, RoutedEventArgs e) { _state.ImageResolutionScale = 0.50; ImgScaleSlider.Value = 0.50; UpdatePillGroup(ImgScale50Btn, ImgScale25Btn, ImgScale75Btn, ImgScale100Btn); }
    private void ImgScale75_Click(object? sender, RoutedEventArgs e) { _state.ImageResolutionScale = 0.75; ImgScaleSlider.Value = 0.75; UpdatePillGroup(ImgScale75Btn, ImgScale25Btn, ImgScale50Btn, ImgScale100Btn); }
    private void ImgScale100_Click(object? sender, RoutedEventArgs e) { _state.ImageResolutionScale = 1.0; ImgScaleSlider.Value = 1.0; UpdatePillGroup(ImgScale100Btn, ImgScale25Btn, ImgScale50Btn, ImgScale75Btn); }

    private void ImgFmtWebp_Click(object? sender, RoutedEventArgs e) { _state.ImageFormatPolicy = ImageFormatPolicy.ModernWebP; UpdatePillGroup(ImgFmtWebpBtn, ImgFmtJpegBtn, ImgFmtOrigBtn); }
    private void ImgFmtJpeg_Click(object? sender, RoutedEventArgs e) { _state.ImageFormatPolicy = ImageFormatPolicy.WebJPEG; UpdatePillGroup(ImgFmtJpegBtn, ImgFmtWebpBtn, ImgFmtOrigBtn); }
    private void ImgFmtOrig_Click(object? sender, RoutedEventArgs e) { _state.ImageFormatPolicy = ImageFormatPolicy.PreserveOriginal; UpdatePillGroup(ImgFmtOrigBtn, ImgFmtWebpBtn, ImgFmtJpegBtn); }

    // ── Audio Bitrate ──
    private void AudRate64_Click(object? sender, RoutedEventArgs e) { _state.AudioBitrate = AudioBitratePreference.K64; AudioBitrateText.Text = "64 kbps"; UpdatePillGroup(AudRate64Btn, AudRate128Btn, AudRate192Btn, AudRate256Btn, AudRate320Btn); }
    private void AudRate128_Click(object? sender, RoutedEventArgs e) { _state.AudioBitrate = AudioBitratePreference.K128; AudioBitrateText.Text = "128 kbps"; UpdatePillGroup(AudRate128Btn, AudRate64Btn, AudRate192Btn, AudRate256Btn, AudRate320Btn); }
    private void AudRate192_Click(object? sender, RoutedEventArgs e) { _state.AudioBitrate = AudioBitratePreference.K192; AudioBitrateText.Text = "192 kbps"; UpdatePillGroup(AudRate192Btn, AudRate64Btn, AudRate128Btn, AudRate256Btn, AudRate320Btn); }
    private void AudRate256_Click(object? sender, RoutedEventArgs e) { _state.AudioBitrate = AudioBitratePreference.K256; AudioBitrateText.Text = "256 kbps"; UpdatePillGroup(AudRate256Btn, AudRate64Btn, AudRate128Btn, AudRate192Btn, AudRate320Btn); }
    private void AudRate320_Click(object? sender, RoutedEventArgs e) { _state.AudioBitrate = AudioBitratePreference.K320; AudioBitrateText.Text = "320 kbps"; UpdatePillGroup(AudRate320Btn, AudRate64Btn, AudRate128Btn, AudRate192Btn, AudRate256Btn); }

    // ── PDF DPI ──
    private void PdfDpi72_Click(object? sender, RoutedEventArgs e) { _state.PdfDpi = 72; PdfDpiText.Text = "72 DPI"; UpdatePillGroup(PdfDpi72Btn, PdfDpi150Btn, PdfDpi200Btn, PdfDpi300Btn); }
    private void PdfDpi150_Click(object? sender, RoutedEventArgs e) { _state.PdfDpi = 150; PdfDpiText.Text = "150 DPI"; UpdatePillGroup(PdfDpi150Btn, PdfDpi72Btn, PdfDpi200Btn, PdfDpi300Btn); }
    private void PdfDpi200_Click(object? sender, RoutedEventArgs e) { _state.PdfDpi = 200; PdfDpiText.Text = "200 DPI"; UpdatePillGroup(PdfDpi200Btn, PdfDpi72Btn, PdfDpi150Btn, PdfDpi300Btn); }
    private void PdfDpi300_Click(object? sender, RoutedEventArgs e) { _state.PdfDpi = 300; PdfDpiText.Text = "300 DPI"; UpdatePillGroup(PdfDpi300Btn, PdfDpi72Btn, PdfDpi150Btn, PdfDpi200Btn); }

    // ── Helper: Pill Group Highlighter ──
    private void UpdatePillGroup(Button activeBtn, params Button[] otherBtns)
    {
        string inactiveHex = _state.BackgroundDarkness switch
        {
            BackgroundDarkness.ReallyDark => "#1B1B20",
            BackgroundDarkness.Oled => "#141418",
            _ => "#28282C"
        };
        string borderHex = _state.BackgroundDarkness switch
        {
            BackgroundDarkness.ReallyDark => "#222228",
            BackgroundDarkness.Oled => "#1A1A20",
            _ => "#2D2D32"
        };

        var inactive = SolidColorBrush.Parse(inactiveHex);
        var activeBg = SolidColorBrush.Parse(_state.AccentColorHex);
        var inactiveFg = SolidColorBrush.Parse("#A0A0B0");

        activeBtn.Background = activeBg;
        activeBtn.Foreground = Brushes.Black;
        activeBtn.BorderBrush = Brushes.Transparent;
        activeBtn.FontWeight = FontWeight.SemiBold;

        foreach (var btn in otherBtns)
        {
            btn.Background = inactive;
            btn.Foreground = inactiveFg;
            btn.BorderBrush = SolidColorBrush.Parse(borderHex);
            btn.FontWeight = FontWeight.Normal;
        }
    }

    // ── Drag & Drop ──
    private static string NormalizePath(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return "";
        string clean = raw.Trim().Trim('"', '\'');
        if (clean.StartsWith("file://", StringComparison.OrdinalIgnoreCase))
        {
            if (Uri.TryCreate(clean, UriKind.Absolute, out var uri))
                clean = uri.LocalPath;
        }
        try
        {
            clean = Uri.UnescapeDataString(clean);
        }
        catch { }
        return clean;
    }

    private static bool HasDropFiles(IDataObject data)
    {
        return data.Contains(DataFormats.Files) ||
               data.Contains(DataFormats.FileNames) ||
               data.Contains(DataFormats.Text) ||
               data.GetDataFormats().Any(f => f.IndexOf("File", StringComparison.OrdinalIgnoreCase) >= 0 || f.IndexOf("Drop", StringComparison.OrdinalIgnoreCase) >= 0);
    }

    private static List<string> ExtractDropFiles(IDataObject data)
    {
        var list = new List<string>();
        try
        {
            if (data.Contains(DataFormats.Files))
            {
                var files = data.GetFiles();
                if (files != null)
                {
                    foreach (var f in files)
                    {
                        string p = f.TryGetLocalPath() ?? f.Path.LocalPath;
                        p = NormalizePath(p);
                        if (!string.IsNullOrEmpty(p) && (File.Exists(p) || Directory.Exists(p)) && !list.Contains(p))
                            list.Add(p);
                    }
                }
            }

            if (data.Contains(DataFormats.FileNames))
            {
                if (data.Get(DataFormats.FileNames) is IEnumerable<string> fileNames)
                {
                    foreach (var fn in fileNames)
                    {
                        string p = NormalizePath(fn);
                        if (!string.IsNullOrEmpty(p) && (File.Exists(p) || Directory.Exists(p)) && !list.Contains(p))
                            list.Add(p);
                    }
                }
            }

            if (data.Contains(DataFormats.Text))
            {
                var txt = data.GetText();
                if (!string.IsNullOrWhiteSpace(txt))
                {
                    var lines = txt.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                    foreach (var line in lines)
                    {
                        string p = NormalizePath(line);
                        if (!string.IsNullOrEmpty(p) && (File.Exists(p) || Directory.Exists(p)) && !list.Contains(p))
                            list.Add(p);
                    }
                }
            }

            // Fallback scan across all data formats
            foreach (var format in data.GetDataFormats())
            {
                try
                {
                    var obj = data.Get(format);
                    if (obj is IEnumerable<string> strEnum)
                    {
                        foreach (var s in strEnum)
                        {
                            string p = NormalizePath(s);
                            if (!string.IsNullOrEmpty(p) && (File.Exists(p) || Directory.Exists(p)) && !list.Contains(p))
                                list.Add(p);
                        }
                    }
                    else if (obj is string str)
                    {
                        string p = NormalizePath(str);
                        if (!string.IsNullOrEmpty(p) && (File.Exists(p) || Directory.Exists(p)) && !list.Contains(p))
                            list.Add(p);
                    }
                }
                catch { }
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[DragDrop] Error extracting files: {ex.Message}");
        }
        return list;
    }

    private void OnDragEnter(object? sender, DragEventArgs e)
    {
        if (HasDropFiles(e.Data))
        {
            e.DragEffects = DragDropEffects.Copy | DragDropEffects.Move | DragDropEffects.Link;
            e.Handled = true;
        }
        else
        {
            e.DragEffects = DragDropEffects.None;
        }
    }

    private void OnDragOver(object? sender, DragEventArgs e)
    {
        if (HasDropFiles(e.Data))
        {
            e.DragEffects = DragDropEffects.Copy | DragDropEffects.Move | DragDropEffects.Link;
            e.Handled = true;
        }
        else
        {
            e.DragEffects = DragDropEffects.None;
        }
    }

    private async void OnWindowDrop(object? sender, DragEventArgs e)
    {
        e.Handled = true;
        var files = ExtractDropFiles(e.Data);
        if (files.Count > 0)
        {
            ActivityTab_Click(null, new RoutedEventArgs());
            await _state.ProcessDroppedFilesImmediatelyAsync(files);
        }
    }

    private async void OnQuickDrop(object? sender, DragEventArgs e)
    {
        e.Handled = true;
        var files = ExtractDropFiles(e.Data);
        if (files.Count > 0)
        {
            ActivityTab_Click(null, new RoutedEventArgs());
            await _state.ProcessDroppedFilesImmediatelyAsync(files);
        }
    }

    private void OnStagedDrop(object? sender, DragEventArgs e)
    {
        e.Handled = true;
        var files = ExtractDropFiles(e.Data);
        if (files.Count > 0)
        {
            ActivityTab_Click(null, new RoutedEventArgs());
            _state.AddFilesToStagedQueue(files);
            EmptyQueueHint.IsVisible = _state.StagedQueue.Count == 0;
        }
    }

    private async void QuickDropBorder_PointerPressed(object? sender, PointerPressedEventArgs e)
    {
        try
        {
            var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
            {
                Title = "Select Media Files to Squeeze",
                AllowMultiple = true
            });

            if (files != null && files.Count > 0)
            {
                var paths = files.Select(f => f.TryGetLocalPath() ?? f.Path.LocalPath).Where(p => !string.IsNullOrEmpty(p)).ToList();
                if (paths.Count > 0)
                {
                    ActivityTab_Click(null, new RoutedEventArgs());
                    await _state.ProcessDroppedFilesImmediatelyAsync(paths);
                }
            }
        }
        catch { }
    }

    private async void AddQueueFiles_Click(object? sender, RoutedEventArgs e)
    {
        try
        {
            var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
            {
                Title = "Add Files to Staged Queue",
                AllowMultiple = true
            });

            if (files != null && files.Count > 0)
            {
                var paths = files.Select(f => f.TryGetLocalPath() ?? f.Path.LocalPath).Where(p => !string.IsNullOrEmpty(p)).ToList();
                if (paths.Count > 0)
                {
                    ActivityTab_Click(null, new RoutedEventArgs());
                    _state.AddFilesToStagedQueue(paths);
                    EmptyQueueHint.IsVisible = _state.StagedQueue.Count == 0;
                }
            }
        }
        catch { }
    }

    private void CustomizeItem_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is StagedQueueItem item) new QueueItemSettingsDialog(item).ShowDialog(this);
    }

    private void DeleteItem_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is Guid id) _state.RemoveFromStagedQueue(id);
    }

    private void ClearQueue_Click(object? sender, RoutedEventArgs e) => _state.ClearStagedQueue();
    private async void SqueezeAll_Click(object? sender, RoutedEventArgs e) => await _state.ProcessStagedQueueAsync();
    private void CancelSingleJob_Click(object? sender, RoutedEventArgs e) { if (sender is Button btn && btn.Tag is Guid id) _state.CancelJob(id); }
    private void CancelAllJobs_Click(object? sender, RoutedEventArgs e) => _state.CancelAllJobs();
    private void ClearCompletedJobs_Click(object? sender, RoutedEventArgs e) => _state.ClearCompletedJobs();

    private void OpenFolder_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is string path && File.Exists(path))
        {
            try { Process.Start(new ProcessStartInfo { FileName = "explorer.exe", Arguments = $"/select,\"{path}\"", UseShellExecute = true }); }
            catch { /* Wine/CrossOver may not support explorer.exe */ }
        }
    }

    // ── macOS-Style Theme Color Swatches ──
    private void ThemeCyan_Click(object? sender, RoutedEventArgs e) => ApplyTheme("#00D2FF", "Cyan", ColorBallCyan);
    private void ThemeEmerald_Click(object? sender, RoutedEventArgs e) => ApplyTheme("#00E676", "Emerald", ColorBallEmerald);
    private void ThemePurple_Click(object? sender, RoutedEventArgs e) => ApplyTheme("#A855F7", "Purple", ColorBallPurple);
    private void ThemeSunset_Click(object? sender, RoutedEventArgs e) => ApplyTheme("#FF9500", "Amber", ColorBallSunset);
    private void ThemeRose_Click(object? sender, RoutedEventArgs e) => ApplyTheme("#FF2D55", "Rose", ColorBallRose);
    private void ThemeBlue_Click(object? sender, RoutedEventArgs e) => ApplyTheme("#007AFF", "Blue", ColorBallBlue);

    private int _customColorIndex = 0;
    private readonly string[] _customColors = { "#FF2D55", "#5856D6", "#00C7BE", "#30D158", "#FF9500" };

    private void ThemeCustom_Click(object? sender, RoutedEventArgs e)
    {
        string color = _customColors[_customColorIndex % _customColors.Length];
        _customColorIndex++;
        ApplyTheme(color, $"#{color.TrimStart('#')}", ColorBallCustom);
    }

    private void ApplyTheme(string hex, string label, Button activeBall)
    {
        _state.AccentColorHex = hex;
        var accentBrush = SolidColorBrush.Parse(hex);
        var accentColor = Color.Parse(hex);

        // Update Dynamic Resources
        this.Resources["AccentBrush"] = accentBrush;
        this.Resources["AccentColor"] = accentColor;
        if (Application.Current != null)
        {
            Application.Current.Resources["AccentBrush"] = accentBrush;
            Application.Current.Resources["AccentColor"] = accentColor;
        }

        // Live Header & Stats Labels
        ThemeColorLabel.Text = label;
        ThemeColorLabel.Foreground = accentBrush;
        SavedStatsText.Foreground = accentBrush;
        LifetimeSavedText.Foreground = accentBrush;
        TargetLimitDisplay.Foreground = accentBrush;
        VidBitratePercentText.Foreground = accentBrush;
        VidResolutionScaleText.Foreground = accentBrush;
        VidFramerateText.Foreground = accentBrush;
        ImgQualityPercentText.Foreground = accentBrush;
        ImgResolutionScaleText.Foreground = accentBrush;
        AudioBitrateText.Foreground = accentBrush;
        PdfDpiText.Foreground = accentBrush;
        CustomTargetSizeLabel.Foreground = accentBrush;
        SqueezeAllBtn.Background = accentBrush;

        UpdateTileStyles();
        RefreshAllPillHighlights();

        var balls = new[] { ColorBallCyan, ColorBallEmerald, ColorBallPurple, ColorBallSunset, ColorBallRose, ColorBallBlue, ColorBallCustom };
        foreach (var b in balls)
        {
            b.BorderBrush = Brushes.Transparent;
            b.BorderThickness = new Thickness(0);
            b.Width = 22;
            b.Height = 22;
            b.CornerRadius = new CornerRadius(11);
        }

        activeBall.BorderBrush = Brushes.White;
        activeBall.BorderThickness = new Thickness(2);
        activeBall.Width = 28;
        activeBall.Height = 28;
        activeBall.CornerRadius = new CornerRadius(14);
    }

    // ── Background Darkness Themes ──
    private void DarknessGrey_Click(object? sender, RoutedEventArgs e) => ApplyBackgroundDarkness(BackgroundDarkness.DarkGrey);
    private void DarknessReallyDark_Click(object? sender, RoutedEventArgs e) => ApplyBackgroundDarkness(BackgroundDarkness.ReallyDark);
    private void DarknessOled_Click(object? sender, RoutedEventArgs e) => ApplyBackgroundDarkness(BackgroundDarkness.Oled);

    private void ApplyBackgroundDarkness(BackgroundDarkness darkness)
    {
        _state.BackgroundDarkness = darkness;

        string winBgHex;
        string cardBgHex;
        string deckBgHex;
        string gliderBgHex;
        string cardBorderHex;
        string label;

        switch (darkness)
        {
            case BackgroundDarkness.ReallyDark:
                winBgHex = "#101014";
                cardBgHex = "#15151A";
                deckBgHex = "#0E0E12";
                gliderBgHex = "#0C0C0F";
                cardBorderHex = "#1E1E24";
                label = "Really Dark";
                break;
            case BackgroundDarkness.Oled:
                winBgHex = "#000000";
                cardBgHex = "#0A0A0C";
                deckBgHex = "#050507";
                gliderBgHex = "#050507";
                cardBorderHex = "#18181C";
                label = "OLED Black";
                break;
            default: // DarkGrey
                winBgHex = "#1A1A1E";
                cardBgHex = "#1F1F23";
                deckBgHex = "#18181C";
                gliderBgHex = "#141418";
                cardBorderHex = "#27272B";
                label = "Dark Grey";
                break;
        }

        var winBg = SolidColorBrush.Parse(winBgHex);
        var cardBg = SolidColorBrush.Parse(cardBgHex);
        var cardBorder = SolidColorBrush.Parse(cardBorderHex);

        this.Background = winBg;
        DarknessModeLabel.Text = label;

        // Repaint all cards and borders
        var allBorders = this.GetVisualDescendants().OfType<Border>();
        foreach (var b in allBorders)
        {
            if (b == ImagesTileBorder || b == VideoTileBorder || b == AudioTileBorder || b == PdfTileBorder)
                continue;

            if (b.Background is SolidColorBrush sb)
            {
                string oldHex = sb.Color.ToString().ToUpperInvariant();
                if (oldHex.Contains("1F1F23") || oldHex.Contains("15151A") || oldHex.Contains("0A0A0C"))
                    b.Background = cardBg;
                else if (oldHex.Contains("18181C") || oldHex.Contains("0E0E12") || oldHex.Contains("050507"))
                    b.Background = SolidColorBrush.Parse(deckBgHex);
                else if (oldHex.Contains("141418") || oldHex.Contains("0C0C0F"))
                    b.Background = SolidColorBrush.Parse(gliderBgHex);
            }
            if (b.BorderBrush is SolidColorBrush sbb)
            {
                string oldBorder = sbb.Color.ToString().ToUpperInvariant();
                if (oldBorder.Contains("27272B") || oldBorder.Contains("1E1E24") || oldBorder.Contains("18181C"))
                    b.BorderBrush = cardBorder;
            }
        }

        UpdateTileStyles();
        RefreshAllPillHighlights();

        Button activeBtn = darkness switch
        {
            BackgroundDarkness.ReallyDark => DarknessReallyDarkBtn,
            BackgroundDarkness.Oled => DarknessOledBtn,
            _ => DarknessGreyBtn
        };
        UpdatePillGroup(activeBtn, DarknessGreyBtn, DarknessReallyDarkBtn, DarknessOledBtn);
    }

    private void RefreshAllPillHighlights()
    {
        // 1. Presets
        Button activePreset = _state.TargetSizeMode switch
        {
            TargetSizeMode.Off => PresetOffBtn,
            TargetSizeMode.Discord50 => Preset50Btn,
            TargetSizeMode.Email10 => Preset10Btn,
            TargetSizeMode.Custom when Math.Abs(_state.CustomTargetSizeMB - 2.0) < 0.1 => Preset2Btn,
            TargetSizeMode.Custom => PresetCustomBtn,
            _ => Preset25Btn
        };
        UpdatePresetButtonStyles(activePreset);

        // 2. Video Deck
        Button activeVidQuality = _state.VideoQuality switch
        {
            <= 0.40 => VidPresetMaxBtn,
            >= 0.90 => VidPresetLosslessBtn,
            _ => VidPresetBalBtn
        };
        UpdatePillGroup(activeVidQuality, VidPresetMaxBtn, VidPresetBalBtn, VidPresetLosslessBtn);

        Button activeVidScale = _state.VideoResolutionScale switch
        {
            <= 0.30 => VidScale25Btn,
            <= 0.60 => VidScale50Btn,
            <= 0.85 => VidScale75Btn,
            _ => VidScale100Btn
        };
        UpdatePillGroup(activeVidScale, VidScale25Btn, VidScale50Btn, VidScale75Btn, VidScale100Btn);

        Button activeVidFps = _state.VideoFramerate switch
        {
            60 => Fps60Btn,
            50 => Fps50Btn,
            30 => Fps30Btn,
            25 => Fps25Btn,
            24 => Fps24Btn,
            15 => Fps15Btn,
            12 => Fps12Btn,
            _ => FpsOrigBtn
        };
        UpdatePillGroup(activeVidFps, FpsOrigBtn, Fps60Btn, Fps50Btn, Fps30Btn, Fps25Btn, Fps24Btn, Fps15Btn, Fps12Btn);

        Button activeVidCodec = _state.VideoCodec switch
        {
            VideoCodecPreference.H264 => CodecH264Btn,
            VideoCodecPreference.AnimatedGIF => CodecGifBtn,
            _ => CodecHevcBtn
        };
        UpdatePillGroup(activeVidCodec, CodecHevcBtn, CodecH264Btn, CodecGifBtn);

        // 3. Image Deck
        Button activeImgQuality = _state.ImageQuality switch
        {
            <= 0.50 => ImgPresetMaxBtn,
            >= 0.95 => ImgPresetLosslessBtn,
            _ => ImgPresetBalBtn
        };
        UpdatePillGroup(activeImgQuality, ImgPresetMaxBtn, ImgPresetBalBtn, ImgPresetLosslessBtn);

        Button activeImgScale = _state.ImageResolutionScale switch
        {
            <= 0.30 => ImgScale25Btn,
            <= 0.60 => ImgScale50Btn,
            <= 0.85 => ImgScale75Btn,
            _ => ImgScale100Btn
        };
        UpdatePillGroup(activeImgScale, ImgScale25Btn, ImgScale50Btn, ImgScale75Btn, ImgScale100Btn);

        Button activeImgFmt = _state.ImageFormatPolicy switch
        {
            ImageFormatPolicy.WebJPEG => ImgFmtJpegBtn,
            ImageFormatPolicy.PreserveOriginal => ImgFmtOrigBtn,
            _ => ImgFmtWebpBtn
        };
        UpdatePillGroup(activeImgFmt, ImgFmtWebpBtn, ImgFmtJpegBtn, ImgFmtOrigBtn);

        // 4. Audio Deck
        Button activeAudRate = _state.AudioBitrate switch
        {
            AudioBitratePreference.K64 => AudRate64Btn,
            AudioBitratePreference.K128 => AudRate128Btn,
            AudioBitratePreference.K256 => AudRate256Btn,
            AudioBitratePreference.K320 => AudRate320Btn,
            _ => AudRate192Btn
        };
        UpdatePillGroup(activeAudRate, AudRate64Btn, AudRate128Btn, AudRate192Btn, AudRate256Btn, AudRate320Btn);

        // 5. PDF Deck
        Button activePdfDpi = _state.PdfDpi switch
        {
            72 => PdfDpi72Btn,
            200 => PdfDpi200Btn,
            300 => PdfDpi300Btn,
            _ => PdfDpi150Btn
        };
        UpdatePillGroup(activePdfDpi, PdfDpi72Btn, PdfDpi150Btn, PdfDpi200Btn, PdfDpi300Btn);
    }

    // ── Watched Folders ──
    private async void AddWatchedFolder_Click(object? sender, RoutedEventArgs e)
    {
        var topLevel = TopLevel.GetTopLevel(this);
        if (topLevel != null)
        {
            var folders = await topLevel.StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions { Title = "Select Folder to Auto-Squeeze" });
            if (folders.Count > 0)
            {
                string path = folders[0].Path.LocalPath;
                if (!_state.WatchedFolders.Contains(path))
                {
                    _state.WatchedFolders.Add(path);
                    FolderWatchService.Shared.StartWatching(path);
                    EmptyWatchedHint.IsVisible = _state.WatchedFolders.Count == 0;
                }
            }
        }
    }

    private void RemoveWatchedFolder_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is string path)
        {
            _state.WatchedFolders.Remove(path);
            FolderWatchService.Shared.StopWatching(path);
            EmptyWatchedHint.IsVisible = _state.WatchedFolders.Count == 0;
        }
    }

    private void ResetStats_Click(object? sender, RoutedEventArgs e) => _state.ResetStats();
    private void QuitBtn_Click(object? sender, RoutedEventArgs e) => Environment.Exit(0);
}
