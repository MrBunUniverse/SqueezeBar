using System;
using System.Globalization;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using CliWrap;
using SqueezeBar.Models;

namespace SqueezeBar.Services;

public static class VideoAudioCompressor
{
    private static readonly Regex DurationRegex = new(@"Duration:\s*(\d+):(\d+):(\d+\.?\d*)", RegexOptions.Compiled);
    private static readonly Regex TimeProgressRegex = new(@"time=(\d+):(\d+):(\d+\.?\d*)", RegexOptions.Compiled);

    public static async Task<double> ProbeDurationAsync(string ffmpeg, string inputPath, CancellationToken ct = default)
    {
        try
        {
            var output = new StringBuilder();
            await Cli.Wrap(ffmpeg)
                .WithArguments(args => args
                    .Add("-nostdin")
                    .Add("-hide_banner")
                    .Add("-i")
                    .Add(inputPath))
                .WithValidation(CommandResultValidation.None)
                .WithStandardErrorPipe(PipeTarget.ToStringBuilder(output))
                .ExecuteAsync(ct);

            var match = DurationRegex.Match(output.ToString());
            if (match.Success)
            {
                double hours = double.Parse(match.Groups[1].Value, CultureInfo.InvariantCulture);
                double minutes = double.Parse(match.Groups[2].Value, CultureInfo.InvariantCulture);
                double seconds = double.Parse(match.Groups[3].Value, CultureInfo.InvariantCulture);
                return (hours * 3600) + (minutes * 60) + seconds;
            }
        }
        catch { }
        return 0;
    }

    public static async Task<CompressionResult?> CompressVideoAsync(
        string inputPath,
        CompressionConfiguration config,
        IProgress<double>? progress = null,
        CancellationToken cancellationToken = default)
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

            progress?.Report(0.05);
            var fileInfo = new FileInfo(inputPath);
            long originalSize = fileInfo.Length;

            double duration = await ProbeDurationAsync(ffmpeg, inputPath, cancellationToken);
            progress?.Report(0.10);

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

            var stdErrPipe = PipeTarget.ToDelegate(line =>
            {
                if (duration > 0)
                {
                    var match = TimeProgressRegex.Match(line);
                    if (match.Success)
                    {
                        double h = double.Parse(match.Groups[1].Value, CultureInfo.InvariantCulture);
                        double m = double.Parse(match.Groups[2].Value, CultureInfo.InvariantCulture);
                        double s = double.Parse(match.Groups[3].Value, CultureInfo.InvariantCulture);
                        double currentSecs = (h * 3600) + (m * 60) + s;
                        double pct = Math.Clamp(0.10 + (0.85 * (currentSecs / duration)), 0.10, 0.95);
                        progress?.Report(pct);
                    }
                }
            });

            // Execute FFmpeg using CliWrap ArgumentsBuilder (100% Space & Unicode Safe)
            await Cli.Wrap(ffmpeg)
                .WithArguments(args =>
                {
                    args.Add("-nostdin")
                        .Add("-y")
                        .Add("-hide_banner")
                        .Add("-i")
                        .Add(inputPath);

                    if (config.VideoCodec == VideoCodecPreference.AnimatedGIF)
                    {
                        int fps = config.VideoFramerate > 0 ? config.VideoFramerate : 15;
                        int scaleWidth = (int)(1280 * config.VideoResolutionScale);
                        args.Add("-vf")
                            .Add($"fps={fps},scale={scaleWidth}:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse");
                    }
                    else
                    {
                        long? targetBytes = config.TargetSizeMode.GetTargetBytes(config.CustomTargetSizeMB);
                        bool hasTargetLimit = targetBytes.HasValue && targetBytes.Value > 0 &&
                                              config.TargetSizeMode != TargetSizeMode.Off &&
                                              config.TargetSizeMode != TargetSizeMode.Manual;

                        if (hasTargetLimit && duration > 0.5)
                        {
                            double totalBits = targetBytes!.Value * 8.0 * 0.93;
                            int audioK = config.VideoRemoveAudio ? 0 : 96;
                            int videoK = Math.Max(80, (int)((totalBits / duration / 1000.0) - audioK));

                            if (config.VideoCodec == VideoCodecPreference.HEVC)
                            {
                                args.Add("-c:v").Add("libx265")
                                    .Add("-b:v").Add($"{videoK}k")
                                    .Add("-maxrate").Add($"{(int)(videoK * 1.3)}k")
                                    .Add("-bufsize").Add($"{(int)(videoK * 2)}k")
                                    .Add("-preset").Add("fast")
                                    .Add("-tag:v").Add("hvc1")
                                    .Add("-pix_fmt").Add("yuv420p");
                            }
                            else
                            {
                                args.Add("-c:v").Add("libx264")
                                    .Add("-b:v").Add($"{videoK}k")
                                    .Add("-maxrate").Add($"{(int)(videoK * 1.3)}k")
                                    .Add("-bufsize").Add($"{(int)(videoK * 2)}k")
                                    .Add("-preset").Add("fast")
                                    .Add("-pix_fmt").Add("yuv420p");
                            }
                        }
                        else
                        {
                            int crf = (int)(28 - (config.VideoQuality * 10));
                            if (config.VideoCodec == VideoCodecPreference.HEVC)
                            {
                                args.Add("-c:v").Add("libx265")
                                    .Add("-crf").Add(crf.ToString())
                                    .Add("-preset").Add("fast")
                                    .Add("-tag:v").Add("hvc1")
                                    .Add("-pix_fmt").Add("yuv420p");
                            }
                            else
                            {
                                args.Add("-c:v").Add("libx264")
                                    .Add("-crf").Add(crf.ToString())
                                    .Add("-preset").Add("fast")
                                    .Add("-pix_fmt").Add("yuv420p");
                            }
                        }

                        if (config.VideoFramerate > 0)
                        {
                            args.Add("-r").Add(config.VideoFramerate.ToString());
                        }

                        if (config.VideoResolutionScale < 0.99)
                        {
                            args.Add("-vf").Add($"scale=trunc(iw*{config.VideoResolutionScale}/2)*2:trunc(ih*{config.VideoResolutionScale}/2)*2");
                        }

                        if (config.VideoRemoveAudio)
                        {
                            args.Add("-an");
                        }
                        else
                        {
                            string audioBitrate = config.AudioBitrate switch
                            {
                                AudioBitratePreference.K64 => "64k",
                                AudioBitratePreference.K128 => "128k",
                                AudioBitratePreference.K256 => "256k",
                                AudioBitratePreference.K320 => "320k",
                                _ => "128k"
                            };
                            args.Add("-c:a").Add("aac").Add("-b:a").Add(audioBitrate);
                        }

                        args.Add("-movflags").Add("+faststart");
                    }

                    if (config.StripMetadata)
                    {
                        args.Add("-map_metadata").Add("-1");
                    }

                    args.Add(outputPath);
                })
                .WithStandardErrorPipe(stdErrPipe)
                .WithValidation(CommandResultValidation.None)
                .ExecuteAsync(cancellationToken);

            progress?.Report(1.0);

            if (File.Exists(outputPath))
            {
                var outFile = new FileInfo(outputPath);
                if (outFile.Length > 1024)
                {
                    return new CompressionResult
                    {
                        OriginalPath = inputPath,
                        OutputPath = outputPath,
                        OriginalSize = originalSize,
                        CompressedSize = outFile.Length,
                        MediaType = MediaType.Video
                    };
                }
                else
                {
                    try { File.Delete(outputPath); } catch { }
                }
            }

            return null;
        }
        catch (OperationCanceledException)
        {
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
        IProgress<double>? progress = null,
        CancellationToken cancellationToken = default)
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

            progress?.Report(0.05);
            var fileInfo = new FileInfo(inputPath);
            long originalSize = fileInfo.Length;

            double duration = await ProbeDurationAsync(ffmpeg, inputPath, cancellationToken);
            progress?.Report(0.15);

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

            var stdErrPipe = PipeTarget.ToDelegate(line =>
            {
                if (duration > 0)
                {
                    var match = TimeProgressRegex.Match(line);
                    if (match.Success)
                    {
                        double h = double.Parse(match.Groups[1].Value, CultureInfo.InvariantCulture);
                        double m = double.Parse(match.Groups[2].Value, CultureInfo.InvariantCulture);
                        double s = double.Parse(match.Groups[3].Value, CultureInfo.InvariantCulture);
                        double currentSecs = (h * 3600) + (m * 60) + s;
                        double pct = Math.Clamp(0.15 + (0.80 * (currentSecs / duration)), 0.15, 0.95);
                        progress?.Report(pct);
                    }
                }
            });

            await Cli.Wrap(ffmpeg)
                .WithArguments(args =>
                {
                    args.Add("-nostdin")
                        .Add("-y")
                        .Add("-hide_banner")
                        .Add("-i")
                        .Add(inputPath)
                        .Add("-c:a")
                        .Add("aac")
                        .Add("-b:a")
                        .Add(bitrate);

                    if (config.StripMetadata)
                    {
                        args.Add("-map_metadata").Add("-1");
                    }

                    args.Add("-movflags").Add("+faststart");
                    args.Add(outputPath);
                })
                .WithStandardErrorPipe(stdErrPipe)
                .WithValidation(CommandResultValidation.None)
                .ExecuteAsync(cancellationToken);

            progress?.Report(1.0);

            if (File.Exists(outputPath))
            {
                var outFile = new FileInfo(outputPath);
                if (outFile.Length > 1024)
                {
                    return new CompressionResult
                    {
                        OriginalPath = inputPath,
                        OutputPath = outputPath,
                        OriginalSize = originalSize,
                        CompressedSize = outFile.Length,
                        MediaType = MediaType.Audio
                    };
                }
                else
                {
                    try { File.Delete(outputPath); } catch { }
                }
            }

            return null;
        }
        catch (OperationCanceledException)
        {
            return null;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[VideoAudioCompressor Audio] Error: {ex.Message}");
            return null;
        }
    }
}
