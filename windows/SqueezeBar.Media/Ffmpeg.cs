using System.Diagnostics;
using System.Globalization;
using System.Text.RegularExpressions;
using SqueezeBar.Core;

namespace SqueezeBar.Media;

/// <summary>
/// The bundled ffmpeg.exe, used only when Windows' own codecs can't do the job (HEVC without the paid
/// extension, MKV/WebM, GIF, WebP, AVIF). It ships beside the app and is never downloaded at runtime.
/// </summary>
public static partial class Ffmpeg
{
    public static string? ExePath { get; } = Find();
    public static bool IsAvailable => ExePath is not null;

    static string? Find()
    {
        var beside = Path.Combine(AppContext.BaseDirectory, "ffmpeg.exe");
        return File.Exists(beside) ? beside : null;
    }

    /// <summary>What FFmpeg reports about a file. Width and height are as displayed (rotation applied).</summary>
    public sealed record MediaInfo(double Duration, bool HasVideo, int Width, int Height, double Fps, double VideoBitrate, bool HasAudio);

    [GeneratedRegex(@"Duration: (\d+):(\d+):(\d+(?:\.\d+)?)")] private static partial Regex DurationPattern();
    [GeneratedRegex(@"bitrate: (\d+) kb/s")] private static partial Regex TotalBitratePattern();
    [GeneratedRegex(@", (\d{2,5})x(\d{2,5})")] private static partial Regex SizePattern();
    [GeneratedRegex(@"([\d.]+) fps")] private static partial Regex FpsPattern();
    [GeneratedRegex(@", (\d+) kb/s")] private static partial Regex StreamBitratePattern();
    [GeneratedRegex(@"rotation of (-?[\d.]+) degrees")] private static partial Regex RotationPattern();

    public static async Task<MediaInfo> ProbeAsync(string file, CancellationToken cancel)
    {
        // With no output file FFmpeg prints the stream list to stderr and exits non-zero; that listing is all we need.
        var (_, text) = await ExecuteAsync(["-hide_banner", "-i", file], null, cancel);
        static double Number(string s) => double.Parse(s, CultureInfo.InvariantCulture);

        double duration = DurationPattern().Match(text) is { Success: true } d
            ? Number(d.Groups[1].Value) * 3600 + Number(d.Groups[2].Value) * 60 + Number(d.Groups[3].Value) : 0;
        double totalBitrate = TotalBitratePattern().Match(text) is { Success: true } b ? Number(b.Groups[1].Value) * 1000 : 0;

        var lines = text.Split('\n');
        // Cover art in audio files is listed as a video stream; it isn't one.
        var video = lines.FirstOrDefault(l => l.Contains("Video:") && l.Contains("Stream #") && !l.Contains("attached pic"));
        bool hasAudio = lines.Any(l => l.Contains("Audio:") && l.Contains("Stream #"));
        if (video is null || SizePattern().Match(video) is not { Success: true } size)
            return new(duration, false, 0, 0, 0, 0, hasAudio);

        int width = int.Parse(size.Groups[1].Value), height = int.Parse(size.Groups[2].Value);
        if (RotationPattern().Match(text) is { Success: true } r && Math.Abs(Math.Abs(Number(r.Groups[1].Value)) % 180 - 90) < 1)
            (width, height) = (height, width);
        double fps = FpsPattern().Match(video) is { Success: true } f ? Number(f.Groups[1].Value) : 0;
        double videoBitrate = StreamBitratePattern().Match(video) is { Success: true } vb ? Number(vb.Groups[1].Value) * 1000 : totalBitrate;
        return new(duration, true, width, height, fps, videoBitrate, hasAudio);
    }

    /// <summary>Runs an encode, reporting progress from FFmpeg's own progress stream and stopping when the job is cancelled.</summary>
    public static async Task RunAsync(IEnumerable<string> arguments, double duration, JobControl control, IProgress<double>? progress)
    {
        string[] prefix = ["-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-nostats", "-progress", "pipe:1"];
        void OnOutput(string line)
        {
            // out_time_us (older builds: out_time_ms, also in microseconds) is the encoded position.
            if (duration <= 0 || progress is null || !line.StartsWith("out_time_", StringComparison.Ordinal)) return;
            var parts = line.Split('=');
            if (parts[0] is "out_time_us" or "out_time_ms" && long.TryParse(parts[^1], out var micros))
                progress.Report(Math.Clamp(micros / 1e6 / duration, 0, 0.99));
        }
        var (exitCode, errors) = await ExecuteAsync([.. prefix, .. arguments], OnOutput, control.Token);
        if (exitCode != 0)
            throw new InvalidOperationException(errors.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).LastOrDefault() ?? $"FFmpeg exited with code {exitCode}.");
    }

    static async Task<(int ExitCode, string Errors)> ExecuteAsync(IEnumerable<string> arguments, Action<string>? onOutput, CancellationToken cancel)
    {
        var start = new ProcessStartInfo(ExePath ?? throw new InvalidOperationException("FFmpeg is not bundled with this build."))
        {
            UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true,
        };
        foreach (var argument in arguments) start.ArgumentList.Add(argument); // ArgumentList quotes paths safely

        using var process = Process.Start(start)!;
        try { process.PriorityClass = ProcessPriorityClass.BelowNormal; } catch { } // keep the PC responsive while encoding
        using var registration = cancel.Register(() => { try { process.Kill(entireProcessTree: true); } catch { } });

        var errors = process.StandardError.ReadToEndAsync(CancellationToken.None);
        while (await process.StandardOutput.ReadLineAsync(CancellationToken.None) is string line) onOutput?.Invoke(line);
        await process.WaitForExitAsync(CancellationToken.None);
        cancel.ThrowIfCancellationRequested();
        return (process.ExitCode, await errors);
    }
}
