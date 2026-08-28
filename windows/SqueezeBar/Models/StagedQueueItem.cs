using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;

namespace SqueezeBar.Models;

public class StagedQueueItem : INotifyPropertyChanged
{
    public Guid Id { get; } = Guid.NewGuid();
    public string FilePath { get; }
    public long OriginalSize { get; }
    public MediaType MediaType { get; }

    private double _customQuality = 0.80;
    public double CustomQuality
    {
        get => _customQuality;
        set { _customQuality = value; OnPropertyChanged(); OnPropertyChanged(nameof(CustomSettingSummary)); }
    }

    private double _customResolutionScale = 1.0;
    public double CustomResolutionScale
    {
        get => _customResolutionScale;
        set { _customResolutionScale = value; OnPropertyChanged(); OnPropertyChanged(nameof(CustomSettingSummary)); }
    }

    private ImageFormatPolicy _customImageFormat = ImageFormatPolicy.PreserveOriginal;
    public ImageFormatPolicy CustomImageFormat
    {
        get => _customImageFormat;
        set { _customImageFormat = value; OnPropertyChanged(); OnPropertyChanged(nameof(CustomSettingSummary)); }
    }

    private VideoCodecPreference _customVideoCodec = VideoCodecPreference.HEVC;
    public VideoCodecPreference CustomVideoCodec
    {
        get => _customVideoCodec;
        set { _customVideoCodec = value; OnPropertyChanged(); }
    }

    private int _customVideoFramerate = 0;
    public int CustomVideoFramerate
    {
        get => _customVideoFramerate;
        set { _customVideoFramerate = value; OnPropertyChanged(); }
    }

    private bool _customVideoRemoveAudio = false;
    public bool CustomVideoRemoveAudio
    {
        get => _customVideoRemoveAudio;
        set { _customVideoRemoveAudio = value; OnPropertyChanged(); }
    }

    private TargetSizeMode _customTargetSizeMode = TargetSizeMode.Off;
    public TargetSizeMode CustomTargetSizeMode
    {
        get => _customTargetSizeMode;
        set { _customTargetSizeMode = value; OnPropertyChanged(); OnPropertyChanged(nameof(CustomSettingSummary)); }
    }

    private double _customTargetSizeMB = 25.0;
    public double CustomTargetSizeMB
    {
        get => _customTargetSizeMB;
        set { _customTargetSizeMB = value; OnPropertyChanged(); OnPropertyChanged(nameof(CustomSettingSummary)); }
    }

    private bool _preserveResolutionInTargetMode = true;
    public bool PreserveResolutionInTargetMode
    {
        get => _preserveResolutionInTargetMode;
        set { _preserveResolutionInTargetMode = value; OnPropertyChanged(); }
    }

    private bool _preserveAudioQualityInTargetMode = false;
    public bool PreserveAudioQualityInTargetMode
    {
        get => _preserveAudioQualityInTargetMode;
        set { _preserveAudioQualityInTargetMode = value; OnPropertyChanged(); }
    }

    private AudioBitratePreference _customAudioBitrate = AudioBitratePreference.K192;
    public AudioBitratePreference CustomAudioBitrate
    {
        get => _customAudioBitrate;
        set { _customAudioBitrate = value; OnPropertyChanged(); OnPropertyChanged(nameof(CustomSettingSummary)); }
    }

    private int _customPdfDpi = 150;
    public int CustomPdfDpi
    {
        get => _customPdfDpi;
        set { _customPdfDpi = value; OnPropertyChanged(); OnPropertyChanged(nameof(CustomSettingSummary)); }
    }

    private bool _customPdfGrayscale = false;
    public bool CustomPdfGrayscale
    {
        get => _customPdfGrayscale;
        set { _customPdfGrayscale = value; OnPropertyChanged(); }
    }

    private bool _stripMetadata = true;
    public bool StripMetadata
    {
        get => _stripMetadata;
        set { _stripMetadata = value; OnPropertyChanged(); }
    }

    public string FileName => Path.GetFileName(FilePath);
    public string Extension => Path.GetExtension(FilePath).TrimStart('.').ToUpperInvariant();

    public string FormattedOriginalSize
    {
        get
        {
            if (OriginalSize < 1024) return $"{OriginalSize} B";
            if (OriginalSize < 1024 * 1024) return $"{OriginalSize / 1024.0:F1} KB";
            if (OriginalSize < 1024 * 1024 * 1024) return $"{OriginalSize / (1024.0 * 1024):F1} MB";
            return $"{OriginalSize / (1024.0 * 1024 * 1024):F2} GB";
        }
    }

    public string CustomSettingSummary
    {
        get
        {
            var parts = new System.Collections.Generic.List<string>();
            if (CustomTargetSizeMode != TargetSizeMode.Off && CustomTargetSizeMode != TargetSizeMode.Manual)
            {
                var targetBytes = CustomTargetSizeMode.GetTargetBytes(CustomTargetSizeMB);
                if (targetBytes.HasValue)
                {
                    parts.Add($"{targetBytes.Value / (1024 * 1024)}MB Limit");
                }
            }
            parts.Add($"{(int)(CustomQuality * 100)}% Q");
            if (CustomResolutionScale < 0.99)
            {
                parts.Add($"{(int)(CustomResolutionScale * 100)}% Scale");
            }
            if (CustomVideoFramerate > 0)
            {
                parts.Add($"{CustomVideoFramerate} FPS");
            }
            return string.Join(" • ", parts);
        }
    }

    public StagedQueueItem(string filePath, long originalSize, MediaType mediaType, CompressionConfiguration baseConfig)
    {
        FilePath = filePath;
        OriginalSize = originalSize;
        MediaType = mediaType;

        CustomQuality = mediaType switch
        {
            MediaType.Image => baseConfig.ImageQuality,
            MediaType.Video => baseConfig.VideoQuality,
            _ => 0.80
        };

        CustomResolutionScale = mediaType switch
        {
            MediaType.Image => baseConfig.ImageResolutionScale,
            MediaType.Video => baseConfig.VideoResolutionScale,
            _ => 1.0
        };

        CustomImageFormat = baseConfig.ImageFormatPolicy;
        CustomVideoCodec = baseConfig.VideoCodec;
        CustomVideoFramerate = 0;
        CustomVideoRemoveAudio = baseConfig.VideoRemoveAudio;
        CustomAudioBitrate = baseConfig.AudioBitrate;
        CustomPdfDpi = baseConfig.PdfDPI;
        CustomPdfGrayscale = baseConfig.PdfGrayscale;
        CustomTargetSizeMode = baseConfig.TargetSizeMode;
        CustomTargetSizeMB = baseConfig.CustomTargetSizeMB;
        PreserveResolutionInTargetMode = baseConfig.PreserveResolutionInTargetMode;
        PreserveAudioQualityInTargetMode = baseConfig.PreserveAudioQualityInTargetMode;
        StripMetadata = baseConfig.StripMetadata;
    }

    public CompressionConfiguration BuildConfiguration(CompressionConfiguration baseConfig)
    {
        var config = baseConfig.Clone();
        config.ImageQuality = CustomQuality;
        config.ImageResolutionScale = CustomResolutionScale;
        config.ImageFormatPolicy = CustomImageFormat;
        config.VideoQuality = CustomQuality;
        config.VideoResolutionScale = CustomResolutionScale;
        config.VideoCodec = CustomVideoCodec;
        config.VideoFramerate = CustomVideoFramerate;
        config.VideoRemoveAudio = CustomVideoRemoveAudio;
        config.AudioBitrate = CustomAudioBitrate;
        config.PdfDPI = CustomPdfDpi;
        config.PdfGrayscale = CustomPdfGrayscale;
        config.TargetSizeMode = CustomTargetSizeMode;
        config.CustomTargetSizeMB = CustomTargetSizeMB;
        config.PreserveResolutionInTargetMode = PreserveResolutionInTargetMode;
        config.PreserveAudioQualityInTargetMode = PreserveAudioQualityInTargetMode;
        config.StripMetadata = StripMetadata;
        return config;
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    protected void OnPropertyChanged([CallerMemberName] string? name = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
}
