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
