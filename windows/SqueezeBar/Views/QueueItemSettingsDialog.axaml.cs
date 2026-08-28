using System;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Media;
using SqueezeBar.Models;

namespace SqueezeBar.Views;

public partial class QueueItemSettingsDialog : Window
{
    private readonly StagedQueueItem _item;

    public QueueItemSettingsDialog()
    {
        InitializeComponent();
        _item = new StagedQueueItem("Sample.mp4", 1024 * 1024 * 25, MediaType.Video, new CompressionConfiguration());
        SetupBindings();
    }

    public QueueItemSettingsDialog(StagedQueueItem item)
    {
        InitializeComponent();
        _item = item;
        SetupBindings();
    }

    private void SetupBindings()
    {
        FileNameText.Text = _item.FileName;
        FileSizeText.Text = $"{_item.FormattedOriginalSize} • {_item.Extension}";

        MediaTypeBadge.Text = _item.MediaType switch
        {
            MediaType.Video => "Video",
            MediaType.Audio => "Audio",
            MediaType.Pdf => "PDF",
            _ => "Image"
        };

        // 1. Target Size Limit Setup
        LockResolutionCheck.IsChecked = _item.PreserveResolutionInTargetMode;
        LockResolutionCheck.IsCheckedChanged += (s, e) => _item.PreserveResolutionInTargetMode = LockResolutionCheck.IsChecked ?? true;

        LockAudioCheck.IsChecked = _item.PreserveAudioQualityInTargetMode;
        LockAudioCheck.IsCheckedChanged += (s, e) => _item.PreserveAudioQualityInTargetMode = LockAudioCheck.IsChecked ?? false;

        UpdateLimitUI();

        // 2. Quality / Bitrate Setup
        QualitySlider.Value = _item.CustomQuality;
        UpdateQualityLabel();
        QualitySlider.PropertyChanged += (s, e) =>
        {
            if (e.Property.Name == nameof(Slider.Value))
            {
                _item.CustomQuality = QualitySlider.Value;
                UpdateQualityLabel();
            }
        };

        // 3. Resolution Scale Setup
        ResolutionSlider.Value = _item.CustomResolutionScale;
        UpdateResolutionLabel();
        ResolutionSlider.PropertyChanged += (s, e) =>
        {
            if (e.Property.Name == nameof(Slider.Value))
            {
                _item.CustomResolutionScale = ResolutionSlider.Value;
                UpdateResolutionLabel();
            }
        };

        // 4. Metadata Strip
        StripMetadataCheck.IsChecked = _item.StripMetadata;
        StripMetadataCheck.IsCheckedChanged += (s, e) => _item.StripMetadata = StripMetadataCheck.IsChecked ?? true;

        // 5. Media Specific Configuration
        switch (_item.MediaType)
        {
            case MediaType.Video:
                QualityTitleText.Text = "Video Bitrate";
                ResolutionCard.IsVisible = true;
                FramerateCard.IsVisible = true;
                VideoCodecPanel.IsVisible = true;
                ImageFormatPanel.IsVisible = false;
                AudioBitratePanel.IsVisible = false;
                PdfDpiPanel.IsVisible = false;
                MuteAudioCheck.IsChecked = _item.CustomVideoRemoveAudio;
                MuteAudioCheck.IsCheckedChanged += (s, e) => _item.CustomVideoRemoveAudio = MuteAudioCheck.IsChecked ?? false;

                UpdateVideoCodecUI();
                UpdateFramerateUI();
                break;

            case MediaType.Image:
                QualityTitleText.Text = "Image Quality";
                ResolutionCard.IsVisible = true;
                FramerateCard.IsVisible = false;
                VideoCodecPanel.IsVisible = false;
                ImageFormatPanel.IsVisible = true;
                AudioBitratePanel.IsVisible = false;
                PdfDpiPanel.IsVisible = false;

                UpdateImageFormatUI();
                break;

            case MediaType.Audio:
                QualityTitleText.Text = "Audio Bitrate";
                ResolutionCard.IsVisible = false;
                FramerateCard.IsVisible = false;
                VideoCodecPanel.IsVisible = false;
                ImageFormatPanel.IsVisible = false;
                AudioBitratePanel.IsVisible = true;
                PdfDpiPanel.IsVisible = false;

                UpdateAudioBitrateUI();
                break;

            case MediaType.Pdf:
                QualityTitleText.Text = "Document Resolution (DPI)";
                ResolutionCard.IsVisible = false;
                FramerateCard.IsVisible = false;
                VideoCodecPanel.IsVisible = false;
                ImageFormatPanel.IsVisible = false;
                AudioBitratePanel.IsVisible = false;
                PdfDpiPanel.IsVisible = true;

                PdfGrayscaleCheck.IsChecked = _item.CustomPdfGrayscale;
                PdfGrayscaleCheck.IsCheckedChanged += (s, e) => _item.CustomPdfGrayscale = PdfGrayscaleCheck.IsChecked ?? false;

                UpdatePdfDpiUI();
                break;
        }
    }

    private void UpdateQualityLabel()
    {
        if (_item.MediaType == MediaType.Video)
        {
            QualityPercentText.Text = $"{(int)(_item.CustomQuality * 100)}% of source";
        }
        else if (_item.MediaType == MediaType.Pdf)
        {
            QualityPercentText.Text = $"{_item.CustomPdfDpi} DPI";
        }
        else
        {
            QualityPercentText.Text = $"{(int)(_item.CustomQuality * 100)}%";
        }
    }

    private void UpdateResolutionLabel()
    {
        if (_item.CustomResolutionScale >= 0.99)
        {
            ResolutionScaleText.Text = "Original (100%)";
            UpdatePillGroup(ResOrigBtn, Res25Btn, Res50Btn, Res75Btn);
        }
        else
        {
            ResolutionScaleText.Text = $"{(int)(_item.CustomResolutionScale * 100)}%";
            if (Math.Abs(_item.CustomResolutionScale - 0.25) < 0.05) UpdatePillGroup(Res25Btn, Res50Btn, Res75Btn, ResOrigBtn);
            else if (Math.Abs(_item.CustomResolutionScale - 0.50) < 0.05) UpdatePillGroup(Res50Btn, Res25Btn, Res75Btn, ResOrigBtn);
            else if (Math.Abs(_item.CustomResolutionScale - 0.75) < 0.05) UpdatePillGroup(Res75Btn, Res25Btn, Res50Btn, ResOrigBtn);
        }
    }

    // ── Target Size Limit Handlers ──
    private void UpdateLimitUI()
    {
        TargetLimitLabel.Text = _item.CustomTargetSizeMode switch
        {
            TargetSizeMode.Manual or TargetSizeMode.Off => "Manual / Off",
            TargetSizeMode.Discord50 => "≤ 50 MB",
            TargetSizeMode.Discord25 => "≤ 25 MB",
            TargetSizeMode.Email10 => "≤ 10 MB",
            TargetSizeMode.Web2 => "≤ 2 MB",
            TargetSizeMode.Custom => $"≤ {_item.CustomTargetSizeMB} MB",
            _ => "Off"
        };

        switch (_item.CustomTargetSizeMode)
        {
            case TargetSizeMode.Discord50: UpdatePillGroup(Limit50Btn, LimitManualBtn, Limit25Btn, Limit10Btn, Limit2Btn, LimitCustomBtn); break;
            case TargetSizeMode.Discord25: UpdatePillGroup(Limit25Btn, LimitManualBtn, Limit50Btn, Limit10Btn, Limit2Btn, LimitCustomBtn); break;
            case TargetSizeMode.Email10: UpdatePillGroup(Limit10Btn, LimitManualBtn, Limit50Btn, Limit25Btn, Limit2Btn, LimitCustomBtn); break;
            case TargetSizeMode.Web2: UpdatePillGroup(Limit2Btn, LimitManualBtn, Limit50Btn, Limit25Btn, Limit10Btn, LimitCustomBtn); break;
            case TargetSizeMode.Custom: UpdatePillGroup(LimitCustomBtn, LimitManualBtn, Limit50Btn, Limit25Btn, Limit10Btn, Limit2Btn); break;
            default: UpdatePillGroup(LimitManualBtn, Limit50Btn, Limit25Btn, Limit10Btn, Limit2Btn, LimitCustomBtn); break;
        }
    }

    private void LimitManual_Click(object? sender, RoutedEventArgs e) { _item.CustomTargetSizeMode = TargetSizeMode.Manual; UpdateLimitUI(); }
    private void Limit50_Click(object? sender, RoutedEventArgs e) { _item.CustomTargetSizeMode = TargetSizeMode.Discord50; UpdateLimitUI(); }
    private void Limit25_Click(object? sender, RoutedEventArgs e) { _item.CustomTargetSizeMode = TargetSizeMode.Discord25; UpdateLimitUI(); }
    private void Limit10_Click(object? sender, RoutedEventArgs e) { _item.CustomTargetSizeMode = TargetSizeMode.Email10; UpdateLimitUI(); }
    private void Limit2_Click(object? sender, RoutedEventArgs e) { _item.CustomTargetSizeMode = TargetSizeMode.Web2; UpdateLimitUI(); }
    private void LimitCustom_Click(object? sender, RoutedEventArgs e) { _item.CustomTargetSizeMode = TargetSizeMode.Custom; UpdateLimitUI(); }

    // ── Quality Presets ──
    private void PresetMaxComp_Click(object? sender, RoutedEventArgs e) { QualitySlider.Value = 0.50; UpdatePillGroup(PresetMaxCompBtn, PresetBalancedBtn, PresetVisLosslessBtn); }
    private void PresetBalanced_Click(object? sender, RoutedEventArgs e) { QualitySlider.Value = 0.70; UpdatePillGroup(PresetBalancedBtn, PresetMaxCompBtn, PresetVisLosslessBtn); }
    private void PresetVisLossless_Click(object? sender, RoutedEventArgs e) { QualitySlider.Value = 0.90; UpdatePillGroup(PresetVisLosslessBtn, PresetMaxCompBtn, PresetBalancedBtn); }

    // ── Resolution Presets ──
    private void Res25_Click(object? sender, RoutedEventArgs e) { ResolutionSlider.Value = 0.25; }
    private void Res50_Click(object? sender, RoutedEventArgs e) { ResolutionSlider.Value = 0.50; }
    private void Res75_Click(object? sender, RoutedEventArgs e) { ResolutionSlider.Value = 0.75; }
    private void ResOrig_Click(object? sender, RoutedEventArgs e) { ResolutionSlider.Value = 1.0; }

    // ── Framerate Handlers ──
    private void UpdateFramerateUI()
    {
        FramerateText.Text = _item.CustomVideoFramerate == 0 ? "Original" : $"{_item.CustomVideoFramerate} FPS";
        switch (_item.CustomVideoFramerate)
        {
            case 60: UpdatePillGroup(Fps60Btn, FpsOrigBtn, Fps50Btn, Fps30Btn, Fps25Btn, Fps24Btn, Fps15Btn, Fps12Btn); break;
            case 50: UpdatePillGroup(Fps50Btn, FpsOrigBtn, Fps60Btn, Fps30Btn, Fps25Btn, Fps24Btn, Fps15Btn, Fps12Btn); break;
            case 30: UpdatePillGroup(Fps30Btn, FpsOrigBtn, Fps60Btn, Fps50Btn, Fps25Btn, Fps24Btn, Fps15Btn, Fps12Btn); break;
            case 25: UpdatePillGroup(Fps25Btn, FpsOrigBtn, Fps60Btn, Fps50Btn, Fps30Btn, Fps24Btn, Fps15Btn, Fps12Btn); break;
            case 24: UpdatePillGroup(Fps24Btn, FpsOrigBtn, Fps60Btn, Fps50Btn, Fps30Btn, Fps25Btn, Fps15Btn, Fps12Btn); break;
            case 15: UpdatePillGroup(Fps15Btn, FpsOrigBtn, Fps60Btn, Fps50Btn, Fps30Btn, Fps25Btn, Fps24Btn, Fps12Btn); break;
            case 12: UpdatePillGroup(Fps12Btn, FpsOrigBtn, Fps60Btn, Fps50Btn, Fps30Btn, Fps25Btn, Fps24Btn, Fps15Btn); break;
            default: UpdatePillGroup(FpsOrigBtn, Fps60Btn, Fps50Btn, Fps30Btn, Fps25Btn, Fps24Btn, Fps15Btn, Fps12Btn); break;
        }
    }

    private void FpsOrig_Click(object? sender, RoutedEventArgs e) { _item.CustomVideoFramerate = 0; UpdateFramerateUI(); }
    private void Fps60_Click(object? sender, RoutedEventArgs e) { _item.CustomVideoFramerate = 60; UpdateFramerateUI(); }
    private void Fps50_Click(object? sender, RoutedEventArgs e) { _item.CustomVideoFramerate = 50; UpdateFramerateUI(); }
    private void Fps30_Click(object? sender, RoutedEventArgs e) { _item.CustomVideoFramerate = 30; UpdateFramerateUI(); }
    private void Fps25_Click(object? sender, RoutedEventArgs e) { _item.CustomVideoFramerate = 25; UpdateFramerateUI(); }
    private void Fps24_Click(object? sender, RoutedEventArgs e) { _item.CustomVideoFramerate = 24; UpdateFramerateUI(); }
    private void Fps15_Click(object? sender, RoutedEventArgs e) { _item.CustomVideoFramerate = 15; UpdateFramerateUI(); }
    private void Fps12_Click(object? sender, RoutedEventArgs e) { _item.CustomVideoFramerate = 12; UpdateFramerateUI(); }

    // ── Video Codec Handlers ──
    private void UpdateVideoCodecUI()
    {
        switch (_item.CustomVideoCodec)
        {
            case VideoCodecPreference.H264: UpdatePillGroup(CodecH264Btn, CodecHevcBtn, CodecGifBtn); break;
            case VideoCodecPreference.AnimatedGIF: UpdatePillGroup(CodecGifBtn, CodecHevcBtn, CodecH264Btn); break;
            default: UpdatePillGroup(CodecHevcBtn, CodecH264Btn, CodecGifBtn); break;
        }
    }

    private void CodecHevc_Click(object? sender, RoutedEventArgs e) { _item.CustomVideoCodec = VideoCodecPreference.HEVC; UpdateVideoCodecUI(); }
    private void CodecH264_Click(object? sender, RoutedEventArgs e) { _item.CustomVideoCodec = VideoCodecPreference.H264; UpdateVideoCodecUI(); }
    private void CodecGif_Click(object? sender, RoutedEventArgs e) { _item.CustomVideoCodec = VideoCodecPreference.AnimatedGIF; UpdateVideoCodecUI(); }

    // ── Image Format Handlers ──
    private void UpdateImageFormatUI()
    {
        switch (_item.CustomImageFormat)
        {
            case ImageFormatPolicy.ModernWebP: UpdatePillGroup(ImgWebpBtn, ImgJpegBtn, ImgPreserveBtn); break;
            case ImageFormatPolicy.WebJPEG: UpdatePillGroup(ImgJpegBtn, ImgWebpBtn, ImgPreserveBtn); break;
            default: UpdatePillGroup(ImgPreserveBtn, ImgWebpBtn, ImgJpegBtn); break;
        }
    }

    private void ImgWebp_Click(object? sender, RoutedEventArgs e) { _item.CustomImageFormat = ImageFormatPolicy.ModernWebP; UpdateImageFormatUI(); }
    private void ImgJpeg_Click(object? sender, RoutedEventArgs e) { _item.CustomImageFormat = ImageFormatPolicy.WebJPEG; UpdateImageFormatUI(); }
    private void ImgPreserve_Click(object? sender, RoutedEventArgs e) { _item.CustomImageFormat = ImageFormatPolicy.PreserveOriginal; UpdateImageFormatUI(); }

    // ── Audio Bitrate Handlers ──
    private void UpdateAudioBitrateUI()
    {
        switch (_item.CustomAudioBitrate)
        {
            case AudioBitratePreference.K64: UpdatePillGroup(Audio64Btn, Audio128Btn, Audio192Btn, Audio256Btn, Audio320Btn); break;
            case AudioBitratePreference.K128: UpdatePillGroup(Audio128Btn, Audio64Btn, Audio192Btn, Audio256Btn, Audio320Btn); break;
            case AudioBitratePreference.K256: UpdatePillGroup(Audio256Btn, Audio64Btn, Audio128Btn, Audio192Btn, Audio320Btn); break;
            case AudioBitratePreference.K320: UpdatePillGroup(Audio320Btn, Audio64Btn, Audio128Btn, Audio192Btn, Audio256Btn); break;
            default: UpdatePillGroup(Audio192Btn, Audio64Btn, Audio128Btn, Audio256Btn, Audio320Btn); break;
        }
    }

    private void Audio64_Click(object? sender, RoutedEventArgs e) { _item.CustomAudioBitrate = AudioBitratePreference.K64; UpdateAudioBitrateUI(); }
    private void Audio128_Click(object? sender, RoutedEventArgs e) { _item.CustomAudioBitrate = AudioBitratePreference.K128; UpdateAudioBitrateUI(); }
    private void Audio192_Click(object? sender, RoutedEventArgs e) { _item.CustomAudioBitrate = AudioBitratePreference.K192; UpdateAudioBitrateUI(); }
    private void Audio256_Click(object? sender, RoutedEventArgs e) { _item.CustomAudioBitrate = AudioBitratePreference.K256; UpdateAudioBitrateUI(); }
    private void Audio320_Click(object? sender, RoutedEventArgs e) { _item.CustomAudioBitrate = AudioBitratePreference.K320; UpdateAudioBitrateUI(); }

    // ── PDF DPI Handlers ──
    private void UpdatePdfDpiUI()
    {
        switch (_item.CustomPdfDpi)
        {
            case 72: UpdatePillGroup(Pdf72Btn, Pdf150Btn, Pdf200Btn, Pdf300Btn); break;
            case 200: UpdatePillGroup(Pdf200Btn, Pdf72Btn, Pdf150Btn, Pdf300Btn); break;
            case 300: UpdatePillGroup(Pdf300Btn, Pdf72Btn, Pdf150Btn, Pdf200Btn); break;
            default: UpdatePillGroup(Pdf150Btn, Pdf72Btn, Pdf200Btn, Pdf300Btn); break;
        }
        UpdateQualityLabel();
    }

    private void Pdf72_Click(object? sender, RoutedEventArgs e) { _item.CustomPdfDpi = 72; UpdatePdfDpiUI(); }
    private void Pdf150_Click(object? sender, RoutedEventArgs e) { _item.CustomPdfDpi = 150; UpdatePdfDpiUI(); }
    private void Pdf200_Click(object? sender, RoutedEventArgs e) { _item.CustomPdfDpi = 200; UpdatePdfDpiUI(); }
    private void Pdf300_Click(object? sender, RoutedEventArgs e) { _item.CustomPdfDpi = 300; UpdatePdfDpiUI(); }

    // ── Pill Group Highlighting Helper ──
    private void UpdatePillGroup(Button activeBtn, params Button[] otherBtns)
    {
        var accentHex = AppState.Shared.AccentColorHex;
        var activeBg = SolidColorBrush.Parse(accentHex);
        var inactiveBg = SolidColorBrush.Parse("#28282C");
        var inactiveFg = SolidColorBrush.Parse("#A0A0B0");
        var borderBrush = SolidColorBrush.Parse("#2D2D32");

        activeBtn.Background = activeBg;
        activeBtn.Foreground = Brushes.Black;
        activeBtn.BorderBrush = Brushes.Transparent;
        activeBtn.FontWeight = FontWeight.SemiBold;

        foreach (var btn in otherBtns)
        {
            btn.Background = inactiveBg;
            btn.Foreground = inactiveFg;
            btn.BorderBrush = borderBrush;
            btn.FontWeight = FontWeight.Normal;
        }
    }

    private void Done_Click(object? sender, RoutedEventArgs e)
    {
        Close();
    }
}
