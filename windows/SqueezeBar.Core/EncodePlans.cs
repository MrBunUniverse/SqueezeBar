namespace SqueezeBar.Core;

// Size and bitrate math ported from HardwareVideoCompressor.swift and HardwareAudioCompressor.swift,
// kept free of platform APIs so both apps produce the same numbers.

/// <summary>Output size and bitrates for a video encode. <c>AudioBitrate == 0</c> means no audio track.</summary>
public readonly record struct VideoPlan(int Width, int Height, int VideoBitrate, int AudioBitrate)
{
    public int AudioChannels => AudioBitrate <= 48_000 ? 1 : 2;
    public int AudioSampleRate => AudioBitrate <= 48_000 ? 32_000 : 44_100;

    public static VideoPlan For(CompressionConfiguration config, int sourceWidth, int sourceHeight, double durationSeconds, double sourceBitrate)
    {
        if (config.EffectiveTargetSizeMB is not double targetMB)
        {
            var scale = Math.Clamp(config.VideoResolutionScale, 0.25, 1.0);
            int w = Even(scale < 0.999 ? sourceWidth * scale : sourceWidth);
            int h = Even(scale < 0.999 ? sourceHeight * scale : sourceHeight);
            int audio = config.VideoRemoveAudio ? 0 : (int)config.AudioBitrate;
            return new(w, h, ManualBitrate(config, sourceWidth, sourceHeight, w, h, sourceBitrate), audio);
        }

        // 8% safety margin for the MP4 header and packet overhead.
        double targetTotalBits = targetMB * 1024.0 * 1024.0 * 0.92 * 8.0;

        int audioBitrate =
            config.VideoRemoveAudio ? 0 :
            config.PreserveAudioQualityInTargetMode ? 128_000 :
            targetMB <= 2.5 ? 48_000 :
            targetMB <= 10.0 ? 64_000 : 96_000;

        double available = Math.Max(120_000.0, targetTotalBits / durationSeconds - audioBitrate);

        double autoScale = 1.0;
        if (!config.PreserveResolutionInTargetMode)
        {
            // Step the resolution down with the bitrate so low targets don't turn blocky.
            double maxDim = available switch
            {
                >= 5_000_000 => 3840.0,
                >= 2_200_000 => 1920.0,
                >= 900_000 => 1280.0,
                >= 350_000 => 854.0,
                >= 180_000 => 640.0,
                _ => 480.0,
            };
            double longEdge = Math.Max(sourceWidth, sourceHeight);
            autoScale = Math.Min(Math.Min(1.0, maxDim / longEdge), Math.Clamp(config.VideoResolutionScale, 0.25, 1.0));
        }

        return new(
            Even(sourceWidth * autoScale),
            Even(sourceHeight * autoScale),
            (int)Math.Min(available, sourceBitrate * 0.95),
            audioBitrate);
    }

    /// <summary>Always below the source bitrate, never under 200 kbps.</summary>
    static int ManualBitrate(CompressionConfiguration config, int sourceWidth, int sourceHeight, int width, int height, double sourceBitrate)
    {
        double bitrateRatio = 0.10 + config.VideoQuality * 0.80;
        double sourcePixels = (double)sourceWidth * sourceHeight;
        double resolutionRatio = sourcePixels > 0 ? (double)width * height / sourcePixels : 1.0;
        // The Mac app treats GIF as HEVC here too.
        double codecEfficiency = config.VideoCodec == VideoCodecPreference.H264 ? 1.0 : 0.70;

        double target = sourceBitrate * bitrateRatio * resolutionRatio * codecEfficiency;
        target = Math.Min(target, sourceBitrate * 0.90);
        return (int)Math.Max(target, 200_000);
    }

    static int Even(double value) => Math.Max(2, (int)value & ~1);
}

public readonly record struct AudioPlan(int Bitrate, int Channels, int SampleRate)
{
    public static AudioPlan For(CompressionConfiguration config, double durationSeconds)
    {
        int bitrate = config.EffectiveTargetSizeMB is double targetMB
            ? (int)Math.Clamp(targetMB * 1024.0 * 1024.0 * 0.95 * 8.0 / durationSeconds, 32_000, 320_000)
            : (int)config.AudioBitrate;
        return new(
            bitrate,
            bitrate <= 32_000 ? 1 : 2,
            bitrate <= 16_000 ? 16_000 : bitrate <= 32_000 ? 22_050 : 44_100);
    }
}

/// <summary>
/// How to encode one image, ported from AcceleratedImageCompressor.swift.
/// <c>JpegInsidePng</c> keeps the .png name but writes JPEG bytes, the Mac app's way of making a PNG lossy.
/// </summary>
public readonly record struct ImagePlan(double? MaxLongEdge, double Quality, bool JpegInsidePng)
{
    public static ImagePlan For(CompressionConfiguration config, string outputExtension, long sourceSize, int sourceWidth, int sourceHeight)
    {
        var plan = Decide(config, outputExtension, sourceSize, Math.Max(sourceWidth, sourceHeight));
        return config.ImageFormatPolicy == ImageFormatPolicy.PngLossless ? plan with { JpegInsidePng = false } : plan;
    }

    static ImagePlan Decide(CompressionConfiguration config, string ext, long sourceSize, double longEdge)
    {
        bool isPng = ext == "png";
        bool isLossy = ext is "jpg" or "jpeg" or "heic" or "heif" or "webp" or "avif";
        bool keepResolution = config.PreserveResolutionInTargetMode;
        double quality = config.ImageQuality;

        if (config.EffectiveTargetSizeMB is double targetMB)
        {
            double targetBytes = targetMB * 1024.0 * 1024.0 * 0.95;
            if (sourceSize <= targetBytes) return new(null, 0.95, false);
            double ratio = targetBytes / Math.Max(sourceSize, 1);

            if (isLossy)
                return keepResolution
                    ? new(null, Math.Clamp(ratio * 0.70, 0.12, 0.85), false)
                    : new(Cap(ratio, 0.20, 0.10), Math.Clamp(Math.Sqrt(ratio) * 0.85, 0.20, 0.90), false);
            if (isPng)
            {
                if (ratio < 0.60 || keepResolution)
                    return new(keepResolution ? null : Cap(ratio, 0.30, 0.15), Math.Clamp(ratio * 0.65, 0.15, 0.85), true);
                return new(longEdge * Math.Clamp(Math.Sqrt(ratio), 0.30, 1.0), 1.0, false);
            }
        }

        if (isLossy) return new(quality <= 0.50 ? 2048 : quality <= 0.65 ? 3072 : null, quality, false);
        if (isPng)
        {
            if (quality >= 0.85) return new(null, 1.0, false);
            if (quality >= 0.65) return new(Math.Min(longEdge, 3840), 1.0, false);
            return new(Math.Min(longEdge, 2560), Math.Clamp(0.40 + (quality - 0.30) * 0.30 / 0.34, 0.35, 0.75), true);
        }
        return new(quality <= 0.60 ? 2048 : null, quality, false);

        double? Cap(double ratio, double at2560, double at1920) =>
            ratio < at2560 && longEdge > 2560 ? 2560 : ratio < at1920 && longEdge > 1920 ? 1920 : null;
    }

    /// <summary>Final resize factor (aspect ratio kept) from the user's scale and this plan's size cap.</summary>
    public double Scale(double resolutionScale, double longEdge)
    {
        double scale = Math.Clamp(resolutionScale, 0.10, 1.0);
        if (MaxLongEdge is double max && longEdge * scale > max) scale = max / longEdge;
        return scale;
    }
}

/// <summary>Render DPI and JPEG quality for a rasterised PDF, ported from AcceleratedPDFCompressor.swift.</summary>
public readonly record struct PdfPlan(double Dpi, double Quality)
{
    public static PdfPlan For(CompressionConfiguration config, long sourceSize, int pageCount)
    {
        double dpi = (int)config.PdfDpi, quality = config.PdfImageQuality;
        if (config.EffectiveTargetSizeMB is double targetMB && sourceSize > targetMB * 1024.0 * 1024.0)
        {
            double budgetPerPage = targetMB * 1024.0 * 1024.0 / Math.Max(pageCount, 1);
            (double maxDpi, double maxQuality) = budgetPerPage switch
            {
                < 60_000 => (72.0, 0.50),
                < 180_000 => (120.0, 0.65),
                < 400_000 => (150.0, 0.75),
                _ => (dpi, quality),
            };
            dpi = Math.Min(dpi, maxDpi);
            quality = Math.Min(quality, maxQuality);
        }
        return new(Math.Max(dpi, 36.0), quality);
    }
}
