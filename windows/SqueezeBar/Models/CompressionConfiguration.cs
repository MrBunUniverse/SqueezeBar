using System;

namespace SqueezeBar.Models;

public class CompressionConfiguration
{
    public double ImageQuality { get; set; } = 0.80;
    public double ImageResolutionScale { get; set; } = 1.0;
    public ImageFormatPolicy ImageFormatPolicy { get; set; } = ImageFormatPolicy.PreserveOriginal;

    public double VideoQuality { get; set; } = 0.70;
    public double VideoResolutionScale { get; set; } = 1.0;
    public VideoCodecPreference VideoCodec { get; set; } = VideoCodecPreference.HEVC;
    public int VideoFramerate { get; set; } = 0;
    public bool VideoRemoveAudio { get; set; } = false;

    public AudioBitratePreference AudioBitrate { get; set; } = AudioBitratePreference.K192;

    public int PdfDPI { get; set; } = 150;
    public bool PdfGrayscale { get; set; } = false;

    public TargetSizeMode TargetSizeMode { get; set; } = TargetSizeMode.Off;
    public double CustomTargetSizeMB { get; set; } = 25.0;
    public bool PreserveResolutionInTargetMode { get; set; } = true;
    public bool PreserveAudioQualityInTargetMode { get; set; } = false;
    public bool StripMetadata { get; set; } = true;
    public string OutputSuffix { get; set; } = "_squeezed";
    public bool ReplaceOriginal { get; set; } = false;

    public CompressionConfiguration Clone()
    {
        return (CompressionConfiguration)MemberwiseClone();
    }
}
