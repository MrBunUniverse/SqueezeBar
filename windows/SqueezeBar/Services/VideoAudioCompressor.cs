using System;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using CliWrap;
using SqueezeBar.Models;

namespace SqueezeBar.Services;

public static class VideoAudioCompressor
{
    public static async Task<CompressionResult?> CompressVideoAsync(
        string inputPath,
        CompressionConfiguration config,
        IProgress<double>? progress = null)
    {
        try
        {
            if (!File.Exists(inputPath)) return null;

            string? ffmpeg = FfmpegService.Shared.GetFfmpegPath();
            if (string.IsNullOrEmpty(ffmpeg))
            {
                progress?.Report(0.05);
                bool ok = await FfmpegService.Shared.DownloadFfmpegAsync(new Progress<double>(p => progress?.Report(p * 0.3)));
                if (ok) ffmpeg = FfmpegService.Shared.GetFfmpegPath();
            }

            if (string.IsNullOrEmpty(ffmpeg))
            {
                System.Diagnostics.Debug.WriteLine("[VideoAudioCompressor] FFmpeg is not available.");
                return null;
            }

            progress?.Report(0.1);
            var fileInfo = new FileInfo(inputPath);
            long originalSize = fileInfo.Length;

            string dir = Path.GetDirectoryName(inputPath) ?? "";
            string nameWithoutExt = Path.GetFileNameWithoutExtension(inputPath);
            string targetExt = config.VideoCodec == VideoCodecPreference.AnimatedGIF ? ".gif" : ".mp4";

            string outputPath = Path.Combine(dir, $"{nameWithoutExt}{config.OutputSuffix}{targetExt}");
            int counter = 1;
            while (File.Exists(outputPath))
            {
                outputPath = Path.Combine(dir, $"{nameWithoutExt}{config.OutputSuffix}_{counter}{targetExt}");
                counter++;
            }

            // Build FFmpeg Arguments
            var args = new StringBuilder();
            args.Append($"-y -i \"{inputPath}\" ");

            if (config.VideoCodec == VideoCodecPreference.AnimatedGIF)
            {
                int fps = 15;
                int scaleWidth = (int)(1280 * config.VideoResolutionScale);
                args.Append($"-vf \"fps={fps},scale={scaleWidth}:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse\" ");
            }
            else
            {
                // Video codec selection with CRF quality
                int crf = (int)(28 - (config.VideoQuality * 10)); // ~18 (high) to 28 (compressed)
                if (config.VideoCodec == VideoCodecPreference.HEVC)
                {
                    args.Append($"-c:v libx265 -crf {crf} -preset medium ");
                }
                else
                {
                    args.Append($"-c:v libx264 -crf {crf} -preset medium ");
                }

                // Resolution scale filter
                if (config.VideoResolutionScale < 0.99)
                {
                    args.Append($"-vf \"scale=trunc(iw*{config.VideoResolutionScale}/2)*2:trunc(ih*{config.VideoResolutionScale}/2)*2\" ");
                }

                // Audio configuration
                if (config.VideoRemoveAudio)
                {
                    args.Append("-an ");
                }
                else
                {
                    args.Append("-c:a aac -b:a 128k ");
                }
            }

            args.Append($"\"{outputPath}\"");

            progress?.Report(0.35);

            // Execute FFmpeg
            var result = await Cli.Wrap(ffmpeg)
                .WithArguments(args.ToString())
                .WithValidation(CommandResultValidation.None)
                .ExecuteAsync();

            progress?.Report(1.0);

            if (File.Exists(outputPath))
            {
                var outFile = new FileInfo(outputPath);
                return new CompressionResult
                {
                    OriginalPath = inputPath,
                    OutputPath = outputPath,
                    OriginalSize = originalSize,
                    CompressedSize = outFile.Length,
                    MediaType = MediaType.Video
                };
            }

            return null;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[VideoAudioCompressor] Error: {ex.Message}");
            return null;
        }
    }

    public static async Task<CompressionResult?> CompressAudioAsync(
        string inputPath,
        CompressionConfiguration config,
        IProgress<double>? progress = null)
    {
        try
        {
            if (!File.Exists(inputPath)) return null;

            string? ffmpeg = FfmpegService.Shared.GetFfmpegPath();
            if (string.IsNullOrEmpty(ffmpeg))
            {
                progress?.Report(0.05);
                bool ok = await FfmpegService.Shared.DownloadFfmpegAsync(new Progress<double>(p => progress?.Report(p * 0.3)));
                if (ok) ffmpeg = FfmpegService.Shared.GetFfmpegPath();
            }

            if (string.IsNullOrEmpty(ffmpeg))
            {
                System.Diagnostics.Debug.WriteLine("[VideoAudioCompressor Audio] FFmpeg is not available.");
                return null;
            }

            progress?.Report(0.1);
            var fileInfo = new FileInfo(inputPath);
            long originalSize = fileInfo.Length;

            string dir = Path.GetDirectoryName(inputPath) ?? "";
            string nameWithoutExt = Path.GetFileNameWithoutExtension(inputPath);
            string targetExt = ".m4a";

            string outputPath = Path.Combine(dir, $"{nameWithoutExt}{config.OutputSuffix}{targetExt}");
            int counter = 1;
            while (File.Exists(outputPath))
            {
                outputPath = Path.Combine(dir, $"{nameWithoutExt}{config.OutputSuffix}_{counter}{targetExt}");
                counter++;
            }

            string bitrate = config.AudioBitrate switch
            {
                AudioBitratePreference.K64 => "64k",
                AudioBitratePreference.K128 => "128k",
                AudioBitratePreference.K256 => "256k",
                AudioBitratePreference.K320 => "320k",
                _ => "192k"
            };

            var args = $"-y -i \"{inputPath}\" -c:a aac -b:a {bitrate} \"{outputPath}\"";

            progress?.Report(0.35);

            var result = await Cli.Wrap(ffmpeg)
                .WithArguments(args)
                .WithValidation(CommandResultValidation.None)
                .ExecuteAsync();

            progress?.Report(1.0);

            if (File.Exists(outputPath))
            {
                var outFile = new FileInfo(outputPath);
                return new CompressionResult
                {
                    OriginalPath = inputPath,
                    OutputPath = outputPath,
                    OriginalSize = originalSize,
                    CompressedSize = outFile.Length,
                    MediaType = MediaType.Audio
                };
            }

            return null;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[VideoAudioCompressor Audio] Error: {ex.Message}");
            return null;
        }
    }
}
