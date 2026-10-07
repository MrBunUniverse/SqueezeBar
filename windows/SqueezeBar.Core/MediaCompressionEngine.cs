using System.Collections.Concurrent;
using System.Diagnostics;

namespace SqueezeBar.Core;

/// <summary>
/// Encodes <paramref name="source"/> into <paramref name="destination"/>, in the format named by the destination's extension.
/// Must stop when <paramref name="control"/> is cancelled and must never write to the source path.
/// </summary>
public delegate Task CompressFn(string source, string destination, CompressionConfiguration config, JobControl control, IProgress<double> progress);

/// <summary>
/// Ported from macOS/Sources/SqueezeBar/Engine/MediaCompressionEngine.swift. Every input path goes through here
/// so destinations, naming, the Downloads fallback and cancellation stay consistent.
/// Events are raised on thread-pool threads; the UI must marshal them.
/// </summary>
public sealed class MediaCompressionEngine(IReadOnlyDictionary<MediaType, CompressFn> compressors)
{
    /// <summary>Internal marker compared in logic (<c>error == Cancelled</c>), not display text.</summary>
    public const string Cancelled = "Cancelled";

    readonly ConcurrentDictionary<Guid, JobControl> _controls = new();
    readonly Dictionary<Guid, string> _destinations = [];

    // Shared by every call: the watch folder and Explorer menu submit files one at a time, and
    // a per-call limit would let those all encode at once.
    readonly SemaphoreSlim _slots = new(Environment.ProcessorCount <= 8 ? 2 : 4);

    // Windows' list, used on every platform so the tests behave the same on the Mac.
    static readonly HashSet<char> InvalidNameChars = [.. "<>:\"/\\|?*", .. Enumerable.Range(0, 32).Select(i => (char)i)];

    /// <summary>Whether this machine can encode an image extension. Unavailable formats fall back to JPEG.</summary>
    public Func<string, bool> CanEncodeImage { get; set; } = _ => true;

    /// <summary>Optional human-readable details ("1920 × 1080 • 30 fps") for the history row.</summary>
    public Func<string, MediaType, Task<string?>>? ProbeDimensions { get; set; }

    // ponytail: assumes the default Downloads location; the app should set this from the
    // Downloads known folder so redirected (OneDrive, other drive) setups work.
    public string FallbackFolder { get; set; } =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");

    public event Action<Guid, string, MediaType>? JobAdded;
    public event Action<Guid, double>? JobProgress;
    public event Action<Guid, CompressionResult?, string?>? JobFinished;
    public event Action? BatchFinished;

    public void Pause(Guid jobId) { if (_controls.TryGetValue(jobId, out var c)) c.Pause(); }
    public void Resume(Guid jobId) { if (_controls.TryGetValue(jobId, out var c)) c.Resume(); }
    public void Cancel(Guid jobId) { if (_controls.TryGetValue(jobId, out var c)) c.Cancel(); }
    public void CancelAll() { foreach (var c in _controls.Values) c.Cancel(); }

    /// <summary>Quick drops: one configuration snapshot for the whole batch.</summary>
    public Task ProcessDroppedAsync(IEnumerable<string> paths, CompressionConfiguration config, Guid? targetFolderId = null) =>
        RunAsync(GatherMediaFiles(paths).Select(p => (p, MediaTypes.Classify(p), config)), targetFolderId);

    /// <summary>Staged queue: each item applies its own overrides to the base configuration.</summary>
    public Task ProcessStagedAsync(IEnumerable<StagedQueueItem> items, CompressionConfiguration baseConfig, Guid? targetFolderId = null) =>
        RunAsync(items.Where(i => i.MediaType != MediaType.Unsupported)
                      .Select(i => (i.FilePath, i.MediaType, i.BuildConfiguration(baseConfig))), targetFolderId);

    async Task RunAsync(IEnumerable<(string Path, MediaType Type, CompressionConfiguration Config)> files, Guid? targetFolderId)
    {
        var jobs = files.Select(f => (Id: Guid.NewGuid(), f.Path, f.Type, f.Config)).ToList();
        if (jobs.Count == 0) return;

        foreach (var job in jobs)
        {
            _controls[job.Id] = new JobControl();
            JobAdded?.Invoke(job.Id, job.Path, job.Type);
        }

        await Task.WhenAll(jobs.Select(async job =>
        {
            await _slots.WaitAsync();
            try { await ProcessSingleFileAsync(job.Id, job.Path, job.Type, job.Config, targetFolderId); }
            finally { _slots.Release(); }
        }));

        BatchFinished?.Invoke();
    }

    async Task ProcessSingleFileAsync(Guid jobId, string path, MediaType type, CompressionConfiguration config, Guid? targetFolderId)
    {
        var control = _controls[jobId];
        string? destination = null;
        try
        {
            if (control.IsCancelled) { JobFinished?.Invoke(jobId, null, Cancelled); return; }

            long originalSize = FileSize(path);
            var originalDimensions = await ProbeAsync(path, type);
            var stopwatch = Stopwatch.StartNew();
            var progress = new PercentGate(p => JobProgress?.Invoke(jobId, p));
            progress.Report(0.05);

            // First beside the source (or the configured folder); on any failure, once more into Downloads.
            Exception? failure = null;
            foreach (var folder in new[] { null, FallbackFolder })
            {
                try
                {
                    destination = ReserveDestination(jobId, path, type, config, folder);
                    await Task.Run(() => compressors[type](path, destination, config, control, progress));
                    failure = null;
                    break;
                }
                catch (Exception e)
                {
                    failure = e;
                    TryDelete(destination);
                    if (control.IsCancelled) break;
                }
            }

            if (control.IsCancelled)
            {
                TryDelete(destination);
                JobFinished?.Invoke(jobId, null, Cancelled);
                return;
            }
            if (failure is not null)
            {
                JobFinished?.Invoke(jobId, null, failure.Message);
                return;
            }

            JobFinished?.Invoke(jobId, new CompressionResult(
                Guid.NewGuid(), path, destination!, originalSize, FileSize(destination!), stopwatch.Elapsed, type,
                DateTimeOffset.Now, originalDimensions, await ProbeAsync(destination!, type), targetFolderId), null);
        }
        finally
        {
            lock (_destinations) _destinations.Remove(jobId);
            _controls.TryRemove(jobId, out _);
        }
    }

    /// <summary>Picks the output path and reserves it so concurrent jobs can't choose the same name.</summary>
    string ReserveDestination(Guid jobId, string source, MediaType type, CompressionConfiguration config, string? fallbackFolder)
    {
        var folder = fallbackFolder ?? Path.GetDirectoryName(Path.GetFullPath(source))!;
        if (fallbackFolder is null)
        {
            if (!string.IsNullOrEmpty(config.CustomOutputFolder) && Directory.Exists(config.CustomOutputFolder))
                folder = config.CustomOutputFolder;
            if (config.ExportToSubfolder)
            {
                var subfolder = string.Concat(config.SubfolderName.Where(c => !InvalidNameChars.Contains(c))).Trim(' ', '.');
                folder = Path.Combine(folder, subfolder.Length == 0 ? "Squeezed" : subfolder);
                Directory.CreateDirectory(folder);
            }
        }

        var suffix = OutputSuffix(config.Suffix);
        var extension = OutputExtension(source, type, config, CanEncodeImage);
        lock (_destinations)
        {
            var reserved = new HashSet<string>(_destinations.Values, StringComparer.OrdinalIgnoreCase);
            return _destinations[jobId] = UniqueDestination(folder, Path.GetFileNameWithoutExtension(source), suffix, extension, source, reserved);
        }
    }

    /// <summary>
    /// The suffix as it ends up in output names. It is typed by the user; characters Windows forbids in file names
    /// would make every job fail. The watch folder recognises its own outputs by this, so it must use the same value.
    /// </summary>
    public static string OutputSuffix(string? suffix)
    {
        var clean = string.Concat((suffix ?? "").Where(c => !InvalidNameChars.Contains(c)));
        return clean.Length == 0 ? "_min" : clean;
    }

    /// <summary>The extension the output will have. Compressors encode to whatever this returns.</summary>
    public static string OutputExtension(string source, MediaType type, CompressionConfiguration config, Func<string, bool>? canEncodeImage = null)
    {
        var sourceExt = Path.GetExtension(source).TrimStart('.').ToLowerInvariant();
        switch (type)
        {
            case MediaType.Image:
                var wanted = config.ImageFormatPolicy switch
                {
                    ImageFormatPolicy.HeicModern => "heic",
                    ImageFormatPolicy.WebpModern => "webp",
                    ImageFormatPolicy.AvifModern => "avif",
                    ImageFormatPolicy.JpegStandard => "jpg",
                    ImageFormatPolicy.PngLossless => "png",
                    _ => sourceExt.Length == 0 ? "jpg" : sourceExt,
                };
                return canEncodeImage is null || canEncodeImage(wanted) ? wanted : "jpg";
            case MediaType.Video: return config.VideoCodec == VideoCodecPreference.Gif ? "gif" : "mp4";
            case MediaType.Audio: return "m4a";
            case MediaType.Pdf: return "pdf";
            default: return sourceExt;
        }
    }

    /// <summary>
    /// Picks an output name that never collides with an existing file, the source itself,
    /// or a path reserved by another running job.
    /// </summary>
    public static string UniqueDestination(string folder, string baseName, string suffix, string extension, string source, IReadOnlySet<string>? reserved = null)
    {
        var sourcePath = Path.GetFullPath(source);
        bool IsTaken(string candidate) =>
            File.Exists(candidate)
            || reserved?.Contains(candidate) == true
            || string.Equals(Path.GetFullPath(candidate), sourcePath, StringComparison.OrdinalIgnoreCase);

        var candidate = Path.Combine(folder, $"{baseName}{suffix}.{extension}");
        for (int counter = 1; IsTaken(candidate); counter++)
            candidate = Path.Combine(folder, $"{baseName}{suffix} ({counter}).{extension}");
        return candidate;
    }

    /// <summary>Expands folders recursively, keeps supported media only, skips hidden files, removes duplicates.</summary>
    public static List<string> GatherMediaFiles(IEnumerable<string> paths)
    {
        var options = new EnumerationOptions
        {
            RecurseSubdirectories = true,
            IgnoreInaccessible = true,
            AttributesToSkip = FileAttributes.Hidden | FileAttributes.System,
        };
        return paths
            .SelectMany(p => Directory.Exists(p) ? Directory.EnumerateFiles(p, "*", options) : File.Exists(p) ? [p] : [])
            .Where(p => MediaTypes.Classify(p) != MediaType.Unsupported)
            .Select(Path.GetFullPath) // same file can arrive as in/a.png and in\a.png
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    async Task<string?> ProbeAsync(string path, MediaType type)
    {
        if (ProbeDimensions is null) return null;
        try { return await ProbeDimensions(path, type); }
        catch { return null; }
    }

    static long FileSize(string path)
    {
        try { return new FileInfo(path).Length; }
        catch { return 0; }
    }

    static void TryDelete(string? path)
    {
        if (path is null) return;
        try { File.Delete(path); }
        catch { /* still locked or already gone; nothing useful to do */ }
    }

    /// <summary>Encoders report per frame; only forward whole-percent changes so the UI isn't flooded.</summary>
    sealed class PercentGate(Action<double> report) : IProgress<double>
    {
        int _lastPercent = -1;

        public void Report(double value)
        {
            int percent = (int)(value * 100);
            if (Interlocked.Exchange(ref _lastPercent, percent) != percent) report(value);
        }
    }
}
