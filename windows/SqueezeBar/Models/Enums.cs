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
    Off = 0,
    Manual = 0,
    Discord50 = 1,
    Discord25 = 2,
    Email10 = 3,
    Web2 = 4,
    Custom = 5
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
            TargetSizeMode.Discord50 => 50L * 1024 * 1024,
            TargetSizeMode.Discord25 => 25L * 1024 * 1024,
            TargetSizeMode.Email10 => 10L * 1024 * 1024,
            TargetSizeMode.Web2 => 2L * 1024 * 1024,
            TargetSizeMode.Custom => (long)(customMB * 1024 * 1024),
            _ => null
        };
    }

    public static string GetDisplayName(this TargetSizeMode mode) => mode switch
    {
        TargetSizeMode.Off => "Manual / Off",
        TargetSizeMode.Discord50 => "50MB (Discord)",
        TargetSizeMode.Discord25 => "25MB (Discord)",
        TargetSizeMode.Email10 => "10MB (Email)",
        TargetSizeMode.Web2 => "2MB (Web)",
        TargetSizeMode.Custom => "Custom Limit",
        _ => "Off"
    };
}
