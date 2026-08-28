using System;

namespace SqueezeBar.Models;

public enum MediaType
{
    Image,
    Video,
    Audio,
    Pdf,
    Unsupported
}

public enum ImageFormatPolicy
{
    PreserveOriginal,
    ModernWebP,
    ModernHEIC,
    ModernAVIF,
    WebJPEG
}

public enum VideoCodecPreference
{
    HEVC,
    H264,
    AnimatedGIF
}

public enum AudioBitratePreference
{
    K64,
    K128,
    K192,
    K256,
    K320
}

public enum TargetSizeMode
{
    Off,
    Discord25,
    Email10,
    Discord50,
    Custom
}

public enum BackgroundDarkness
{
    DarkGrey,
    ReallyDark,
    Oled
}

public static class EnumExtensions
{
    public static long? GetTargetBytes(this TargetSizeMode mode, double customMB = 25.0)
    {
        return mode switch
        {
            TargetSizeMode.Discord25 => 25L * 1024 * 1024,
            TargetSizeMode.Email10 => 10L * 1024 * 1024,
            TargetSizeMode.Discord50 => 50L * 1024 * 1024,
            TargetSizeMode.Custom => (long)(customMB * 1024 * 1024),
            _ => null
        };
    }

    public static string GetDisplayName(this TargetSizeMode mode) => mode switch
    {
        TargetSizeMode.Off => "Off",
        TargetSizeMode.Discord25 => "25MB (Discord)",
        TargetSizeMode.Email10 => "10MB (Email)",
        TargetSizeMode.Discord50 => "50MB (Discord)",
        TargetSizeMode.Custom => "Custom Limit",
        _ => "Off"
    };
}
