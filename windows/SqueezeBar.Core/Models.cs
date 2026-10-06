namespace SqueezeBar.Core;

// Ported from macOS/Sources/SqueezeBar/Models/CompressionModels.swift.
// Enum member names are persisted in settings; never rename them without a migration.

public enum MediaType { Image, Video, Audio, Pdf, Unsupported }

public static class MediaTypes
{
    static readonly HashSet<string> Image = new(StringComparer.OrdinalIgnoreCase)
        { "jpg", "jpeg", "png", "webp", "heic", "heif", "tiff", "tif", "bmp", "gif", "avif" };
    static readonly HashSet<string> Video = new(StringComparer.OrdinalIgnoreCase)
        { "mov", "mp4", "m4v", "mkv", "webm", "avi", "wmv", "flv", "ts" };
    static readonly HashSet<string> Audio = new(StringComparer.OrdinalIgnoreCase)
        { "mp3", "m4a", "wav", "aac", "flac", "aiff", "aif", "caf", "alac", "ogg" };

    public static MediaType Classify(string path)
    {
        var ext = Path.GetExtension(path).TrimStart('.');
        if (Image.Contains(ext)) return MediaType.Image;
        if (Video.Contains(ext)) return MediaType.Video;
        if (Audio.Contains(ext)) return MediaType.Audio;
        if (ext.Equals("pdf", StringComparison.OrdinalIgnoreCase)) return MediaType.Pdf;
        return MediaType.Unsupported;
    }
}

public enum PdfDpiOption { Dpi72 = 72, Dpi150 = 150, Dpi200 = 200, Dpi300 = 300 }

public enum ImageFormatPolicy { PreserveOriginal, HeicModern, WebpModern, AvifModern, PngLossless, JpegStandard }

/// <summary>Value is the bitrate in bits per second.</summary>
public enum AudioBitratePreference
{
    K16 = 16_000, K32 = 32_000, K64 = 64_000, K128 = 128_000, K192 = 192_000, K256 = 256_000, K320 = 320_000
}

public enum VideoCodecPreference { Hevc, H264, Gif }

/// <summary>Value is the target FPS; 0 keeps the source frame rate.</summary>
public enum VideoFramerateOption { Original = 0, Fps60 = 60, Fps50 = 50, Fps30 = 30, Fps25 = 25, Fps24 = 24, Fps15 = 15, Fps12 = 12 }

/// <summary>Value is the FPS cap; 0 keeps the source frame rate.</summary>
public enum GifFramerateOption { Full = 0, Smooth24 = 24, Half15 = 15, Compact10 = 10 }

public enum TargetSizeMode { Off, Discord50, Discord25, Email10, Web2, Custom }

/// <summary>Per-run settings snapshot. A record so per-file overrides can use <c>with</c>.</summary>
public sealed record CompressionConfiguration
{
    public double ImageQuality { get; init; } = 0.85;
    public double ImageResolutionScale { get; init; } = 1.0;
    public ImageFormatPolicy ImageFormatPolicy { get; init; } = ImageFormatPolicy.PreserveOriginal;
    public double VideoQuality { get; init; } = 0.80;
    public double VideoResolutionScale { get; init; } = 1.0;
    public VideoCodecPreference VideoCodec { get; init; } = VideoCodecPreference.Hevc;
    public VideoFramerateOption VideoFramerate { get; init; } = VideoFramerateOption.Original;
    public bool VideoRemoveAudio { get; init; }
    public GifFramerateOption GifFramerate { get; init; } = GifFramerateOption.Half15;
    public AudioBitratePreference AudioBitrate { get; init; } = AudioBitratePreference.K128;
    public PdfDpiOption PdfDpi { get; init; } = PdfDpiOption.Dpi150;
    public double PdfImageQuality { get; init; } = 0.70;
    public bool PdfGrayscale { get; init; }
    public bool PdfStripMetadata { get; init; } = true;
    public TargetSizeMode TargetSizeMode { get; init; } = TargetSizeMode.Off;
    public double CustomTargetSizeMB { get; init; } = 25.0;
    public bool PreserveResolutionInTargetMode { get; init; }
    public bool PreserveAudioQualityInTargetMode { get; init; }
    public string Suffix { get; init; } = "_min";
    public string? CustomOutputFolder { get; init; }
    public bool ExportToSubfolder { get; init; }
    public string SubfolderName { get; init; } = "Squeezed";
    public bool StripMetadata { get; init; }

    public double? EffectiveTargetSizeMB => TargetSizeMode switch
    {
        TargetSizeMode.Off => null,
        TargetSizeMode.Discord50 => 50.0,
        TargetSizeMode.Discord25 => 25.0,
        TargetSizeMode.Email10 => 10.0,
        TargetSizeMode.Web2 => 2.0,
        _ => CustomTargetSizeMB,
    };
}

public sealed record CompressionResult(
    Guid Id,
    string OriginalPath,
    string OutputPath,
    long OriginalSize,
    long CompressedSize,
    TimeSpan Duration,
    MediaType MediaType,
    DateTimeOffset Timestamp,
    string? OriginalDimensions = null,
    string? OutputDimensions = null,
    Guid? FolderId = null)
{
    public long BytesSaved => Math.Max(0, OriginalSize - CompressedSize);
    public double PercentSaved => OriginalSize > 0 ? Math.Max(0.0, (double)(OriginalSize - CompressedSize) / OriginalSize * 100.0) : 0.0;
    public string FileName => Path.GetFileName(OriginalPath);
}

/// <summary>A file waiting in the staged queue, with per-file overrides on the base configuration.</summary>
public sealed class StagedQueueItem
{
    public Guid Id { get; } = Guid.NewGuid();
    public string FilePath { get; }
    public long OriginalSize { get; }
    public MediaType MediaType { get; }

    public double CustomQuality { get; set; }
    public double CustomResolutionScale { get; set; }
    public ImageFormatPolicy CustomImageFormat { get; set; }
    public VideoCodecPreference CustomVideoCodec { get; set; }
    public VideoFramerateOption CustomVideoFramerate { get; set; }
    public bool CustomVideoRemoveAudio { get; set; }
    public AudioBitratePreference CustomAudioBitrate { get; set; }
    public PdfDpiOption CustomPdfDpi { get; set; }
    public double CustomPdfImageQuality { get; set; }
    public bool CustomPdfGrayscale { get; set; }
    public TargetSizeMode CustomTargetSizeMode { get; set; }
    public double CustomTargetSizeMB { get; set; }
    public bool StripMetadata { get; set; }

    public StagedQueueItem(string filePath, long originalSize, MediaType mediaType, CompressionConfiguration baseConfig)
    {
        FilePath = filePath;
        OriginalSize = originalSize;
        MediaType = mediaType;

        (CustomQuality, CustomResolutionScale) = mediaType switch
        {
            MediaType.Image => (baseConfig.ImageQuality, baseConfig.ImageResolutionScale),
            MediaType.Video => (baseConfig.VideoQuality, baseConfig.VideoResolutionScale),
            MediaType.Pdf => (baseConfig.PdfImageQuality, 1.0),
            _ => (0.80, 1.0),
        };
        CustomImageFormat = baseConfig.ImageFormatPolicy;
        CustomVideoCodec = baseConfig.VideoCodec;
        CustomVideoFramerate = baseConfig.VideoFramerate;
        CustomVideoRemoveAudio = baseConfig.VideoRemoveAudio;
        CustomAudioBitrate = baseConfig.AudioBitrate;
        CustomPdfDpi = baseConfig.PdfDpi;
        CustomPdfImageQuality = baseConfig.PdfImageQuality;
        CustomPdfGrayscale = baseConfig.PdfGrayscale;
        CustomTargetSizeMode = baseConfig.TargetSizeMode;
        CustomTargetSizeMB = baseConfig.CustomTargetSizeMB;
        StripMetadata = baseConfig.StripMetadata;
    }

    public CompressionConfiguration BuildConfiguration(CompressionConfiguration baseConfig)
    {
        var config = MediaType switch
        {
            MediaType.Image => baseConfig with
            {
                ImageQuality = CustomQuality,
                ImageResolutionScale = CustomResolutionScale,
                ImageFormatPolicy = CustomImageFormat,
            },
            MediaType.Video => baseConfig with
            {
                VideoQuality = CustomQuality,
                VideoResolutionScale = CustomResolutionScale,
                VideoCodec = CustomVideoCodec,
                VideoFramerate = CustomVideoFramerate,
                VideoRemoveAudio = CustomVideoRemoveAudio,
            },
            MediaType.Audio => baseConfig with { AudioBitrate = CustomAudioBitrate },
            MediaType.Pdf => baseConfig with
            {
                PdfDpi = CustomPdfDpi,
                PdfImageQuality = CustomPdfImageQuality,
                PdfGrayscale = CustomPdfGrayscale,
            },
            _ => baseConfig,
        };
        return config with
        {
            TargetSizeMode = CustomTargetSizeMode,
            CustomTargetSizeMB = CustomTargetSizeMB,
            StripMetadata = StripMetadata,
        };
    }
}
