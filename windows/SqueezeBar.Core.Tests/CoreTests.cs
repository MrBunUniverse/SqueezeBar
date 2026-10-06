using SqueezeBar.Core;
using Xunit;

namespace SqueezeBar.Core.Tests;

public sealed class TempDir : IDisposable
{
    public string Path { get; } = Directory.CreateTempSubdirectory("sb-test-").FullName;
    public string File(string name, string content = "x")
    {
        var path = System.IO.Path.Combine(Path, name);
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path)!);
        System.IO.File.WriteAllText(path, content);
        return path;
    }
    public void Dispose() => Directory.Delete(Path, recursive: true);
}

// Ported from macOS/Tests/SqueezeBarTests/OutputSafetyTests.swift
public class DestinationNamingTests : IDisposable
{
    readonly TempDir _dir = new();
    public void Dispose() => _dir.Dispose();

    string Unique(string suffix, string source, IReadOnlySet<string>? reserved = null) =>
        Path.GetFileName(MediaCompressionEngine.UniqueDestination(_dir.Path, "clip", suffix, "mp4", source, reserved));

    [Fact]
    public void PlainNameGetsSuffix() =>
        Assert.Equal("clip_min.mp4", Unique("_min", Path.Combine(_dir.Path, "clip.mp4")));

    [Fact]
    public void ExistingFileIsNotOverwritten()
    {
        _dir.File("clip_min.mp4");
        Assert.Equal("clip_min (1).mp4", Unique("_min", Path.Combine(_dir.Path, "clip.mp4")));
    }

    [Fact]
    public void ReservedPathIsSkipped()
    {
        var reserved = new HashSet<string> { Path.Combine(_dir.Path, "clip_min.mp4") };
        Assert.Equal("clip_min (1).mp4", Unique("_min", Path.Combine(_dir.Path, "clip.mp4"), reserved));
    }

    /// Regression carried over from the Mac app: an empty suffix used to return the source path itself.
    [Fact]
    public void DestinationNeverEqualsSource() =>
        Assert.Equal("clip (1).mp4", Unique("", _dir.File("clip.mp4")));
}

public class ClassificationTests
{
    [Theory]
    [InlineData("sample.png", MediaType.Image)]
    [InlineData("sample.JPG", MediaType.Image)]
    [InlineData("sample.mov", MediaType.Video)]
    [InlineData("sample.mp4", MediaType.Video)]
    [InlineData("sample.mp3", MediaType.Audio)]
    [InlineData("sample.wav", MediaType.Audio)]
    [InlineData("sample.flac", MediaType.Audio)]
    [InlineData("sample.m4a", MediaType.Audio)]
    [InlineData("sample.pdf", MediaType.Pdf)]
    [InlineData("sample.txt", MediaType.Unsupported)]
    [InlineData("noextension", MediaType.Unsupported)]
    public void Classify(string name, MediaType expected) => Assert.Equal(expected, MediaTypes.Classify(name));

    [Theory]
    [InlineData(ImageFormatPolicy.WebpModern, "webp")]
    [InlineData(ImageFormatPolicy.AvifModern, "avif")]
    [InlineData(ImageFormatPolicy.HeicModern, "heic")]
    [InlineData(ImageFormatPolicy.PngLossless, "png")]
    [InlineData(ImageFormatPolicy.JpegStandard, "jpg")]
    [InlineData(ImageFormatPolicy.PreserveOriginal, "png")]
    public void ImageExtensionFollowsPolicy(ImageFormatPolicy policy, string expected) =>
        Assert.Equal(expected, MediaCompressionEngine.OutputExtension("a.PNG", MediaType.Image, new() { ImageFormatPolicy = policy }));

    [Fact]
    public void UnencodableImageFormatFallsBackToJpeg() =>
        Assert.Equal("jpg", MediaCompressionEngine.OutputExtension(
            "a.png", MediaType.Image, new() { ImageFormatPolicy = ImageFormatPolicy.AvifModern }, ext => ext != "avif"));

    [Fact]
    public void VideoAudioPdfExtensions()
    {
        Assert.Equal("mp4", MediaCompressionEngine.OutputExtension("a.mov", MediaType.Video, new()));
        Assert.Equal("gif", MediaCompressionEngine.OutputExtension("a.mov", MediaType.Video, new() { VideoCodec = VideoCodecPreference.Gif }));
        Assert.Equal("m4a", MediaCompressionEngine.OutputExtension("a.wav", MediaType.Audio, new()));
        Assert.Equal("pdf", MediaCompressionEngine.OutputExtension("a.pdf", MediaType.Pdf, new()));
    }
}

// Ported from macOS/Tests/SqueezeBarTests/JobControlTests.swift
public class JobControlTests
{
    [Fact]
    public void CheckpointPassesWhenNotPaused() => Assert.True(new JobControl().Checkpoint());

    [Fact]
    public async Task PausedCheckpointBlocksUntilResume()
    {
        var control = new JobControl();
        control.Pause();
        var task = Task.Run(control.Checkpoint);
        await Assert.ThrowsAsync<TimeoutException>(() => task.WaitAsync(TimeSpan.FromMilliseconds(300)));
        control.Resume();
        Assert.True(await task.WaitAsync(TimeSpan.FromSeconds(2)));
    }

    [Fact]
    public async Task CancelWakesPausedCheckpointAndReportsCancelled()
    {
        var control = new JobControl();
        control.Pause();
        var task = Task.Run(control.Checkpoint);
        await Task.Delay(100);
        control.Cancel();
        Assert.False(await task.WaitAsync(TimeSpan.FromSeconds(2)));
        Assert.True(control.IsCancelled);
        Assert.False(control.IsPaused);
        Assert.True(control.Token.IsCancellationRequested);
    }

    [Fact]
    public void CannotPauseAfterCancel()
    {
        var control = new JobControl();
        control.Cancel();
        control.Pause();
        Assert.False(control.IsPaused);
        Assert.False(control.Checkpoint());
    }
}

public class EncodePlanTests
{
    // 1080p, 60 s, 10 Mbps source.
    static VideoPlan Plan(CompressionConfiguration c) => VideoPlan.For(c, 1920, 1080, 60, 10_000_000);

    [Fact]
    public void ManualModeScalesBitrateWithQualityAndCodec()
    {
        // 10 Mbps * (0.10 + 0.8*0.8) * 0.70 HEVC
        Assert.Equal(new VideoPlan(1920, 1080, 5_180_000, 128_000), Plan(new()));
        Assert.Equal(7_400_000, Plan(new() { VideoCodec = VideoCodecPreference.H264 }).VideoBitrate);
    }

    [Fact]
    public void ManualModeHalvesResolutionToEvenSizeAndFloorsBitrate()
    {
        var plan = VideoPlan.For(new() { VideoResolutionScale = 0.5, VideoQuality = 0 }, 1918, 1078, 60, 300_000);
        Assert.Equal((958, 538, 200_000), (plan.Width, plan.Height, plan.VideoBitrate));
    }

    [Fact]
    public void TargetModeFitsBudgetAndStepsResolutionDown()
    {
        // 25 MB over 60 s: 25*1048576*0.92*8/60 - 96k audio = 3,119,633 bps -> 1080p tier.
        var plan = Plan(new() { TargetSizeMode = TargetSizeMode.Discord25 });
        Assert.Equal(new VideoPlan(1920, 1080, 3_119_633, 96_000), plan);

        // 2 MB: 48k mono audio, 209,250 bps -> 360p tier (640 long edge).
        var small = Plan(new() { TargetSizeMode = TargetSizeMode.Web2 });
        Assert.Equal(new VideoPlan(640, 360, 209_250, 48_000), small);
        Assert.Equal((1, 32_000), (small.AudioChannels, small.AudioSampleRate));
    }

    [Fact]
    public void TargetModeHonoursLocksAndRemovedAudio()
    {
        var plan = Plan(new()
        {
            TargetSizeMode = TargetSizeMode.Web2,
            PreserveResolutionInTargetMode = true,
            VideoRemoveAudio = true,
        });
        Assert.Equal((1920, 1080, 0), (plan.Width, plan.Height, plan.AudioBitrate));
    }

    [Fact]
    public void TargetModeNeverExceedsSourceBitrate() =>
        Assert.Equal(950_000, VideoPlan.For(new() { TargetSizeMode = TargetSizeMode.Discord50 }, 1280, 720, 10, 1_000_000).VideoBitrate);

    [Fact]
    public void AudioPlan()
    {
        Assert.Equal(new AudioPlan(128_000, 2, 44_100), Core.AudioPlan.For(new(), 300));
        Assert.Equal(new AudioPlan(16_000, 1, 16_000), Core.AudioPlan.For(new() { AudioBitrate = AudioBitratePreference.K16 }, 300));
        // 2 MB over an hour would be ~4.4 kbps; clamped to the 32 kbps floor.
        Assert.Equal(new AudioPlan(32_000, 1, 22_050), Core.AudioPlan.For(new() { TargetSizeMode = TargetSizeMode.Web2 }, 3600));
        // Zero-length input must not overflow.
        Assert.Equal(320_000, Core.AudioPlan.For(new() { TargetSizeMode = TargetSizeMode.Discord50 }, 0).Bitrate);
    }
}

public class StagedQueueItemTests
{
    [Fact]
    public void OverridesApplyOnlyToTheItemsMediaType()
    {
        var baseConfig = new CompressionConfiguration { Suffix = "_x" };
        var item = new StagedQueueItem("a.mp4", 10, MediaType.Video, baseConfig)
        {
            CustomQuality = 0.4,
            CustomImageFormat = ImageFormatPolicy.PngLossless,
            CustomTargetSizeMode = TargetSizeMode.Email10,
        };
        var config = item.BuildConfiguration(baseConfig);
        Assert.Equal(0.4, config.VideoQuality);
        Assert.Equal(baseConfig.ImageQuality, config.ImageQuality);
        Assert.Equal(ImageFormatPolicy.PreserveOriginal, config.ImageFormatPolicy);
        Assert.Equal(10.0, config.EffectiveTargetSizeMB);
        Assert.Equal("_x", config.Suffix);
    }
}

public class EngineTests : IDisposable
{
    readonly TempDir _dir = new();
    public void Dispose() => _dir.Dispose();

    static MediaCompressionEngine Engine(CompressFn fn, List<(CompressionResult? Result, string? Error)> finished)
    {
        var engine = new MediaCompressionEngine(Enum.GetValues<MediaType>().ToDictionary(t => t, _ => fn));
        engine.JobFinished += (_, result, error) => { lock (finished) finished.Add((result, error)); };
        return engine;
    }

    static readonly CompressFn Copy = (src, dst, _, _, progress) =>
    {
        File.WriteAllText(dst, "small");
        progress.Report(1.0);
        return Task.CompletedTask;
    };

    [Fact]
    public async Task DropExpandsFoldersSkipsUnsupportedAndWritesBesideSource()
    {
        var png = _dir.File("in/a.png", "original bytes");
        _dir.File("in/sub/b.mp3", "original bytes");
        _dir.File("in/notes.txt");
        var finished = new List<(CompressionResult? Result, string? Error)>();
        var batches = 0;
        var engine = Engine(Copy, finished);
        engine.BatchFinished += () => batches++;

        await engine.ProcessDroppedAsync([Path.Combine(_dir.Path, "in"), png], new());

        Assert.Equal(2, finished.Count);
        Assert.All(finished, f => Assert.Null(f.Error));
        Assert.True(File.Exists(Path.Combine(_dir.Path, "in", "a_min.png")));
        Assert.True(File.Exists(Path.Combine(_dir.Path, "in", "sub", "b_min.m4a")));
        Assert.Equal("original bytes", File.ReadAllText(png));
        var result = finished.Single(f => f.Result!.MediaType == MediaType.Image).Result!;
        Assert.Equal((14, 5, 9), (result.OriginalSize, result.CompressedSize, result.BytesSaved));
        Assert.Equal(1, batches);
    }

    [Fact]
    public async Task SameNamedInputsGetDistinctOutputs()
    {
        // a.png and a.jpg both become a_min.jpg; the second must not overwrite the first.
        var inputs = new[] { _dir.File("a.png"), _dir.File("a.jpg") };
        var finished = new List<(CompressionResult? Result, string? Error)>();
        await Engine(Copy, finished).ProcessDroppedAsync(inputs, new() { ImageFormatPolicy = ImageFormatPolicy.JpegStandard });
        Assert.Equal(["a_min (1).jpg", "a_min.jpg"], finished.Select(f => Path.GetFileName(f.Result!.OutputPath)).Order());
    }

    [Fact]
    public async Task SubfolderAndCustomFolderAreUsed()
    {
        var src = _dir.File("in/a.png");
        var custom = Directory.CreateDirectory(Path.Combine(_dir.Path, "out")).FullName;
        var finished = new List<(CompressionResult? Result, string? Error)>();
        await Engine(Copy, finished).ProcessDroppedAsync([src],
            new() { CustomOutputFolder = custom, ExportToSubfolder = true, SubfolderName = " " });
        Assert.Equal(Path.Combine(custom, "Squeezed", "a_min.png"), finished.Single().Result!.OutputPath);
    }

    [Fact]
    public async Task WriteFailureFallsBackToDownloadsFolder()
    {
        var src = _dir.File("in/a.png");
        var fallback = Directory.CreateDirectory(Path.Combine(_dir.Path, "downloads")).FullName;
        var finished = new List<(CompressionResult? Result, string? Error)>();
        var engine = Engine((s, dst, c, ctl, p) =>
            dst.StartsWith(fallback) ? Copy(s, dst, c, ctl, p) : throw new UnauthorizedAccessException("read-only"), finished);
        engine.FallbackFolder = fallback;

        await engine.ProcessDroppedAsync([src], new());

        Assert.Equal(Path.Combine(fallback, "a_min.png"), finished.Single().Result!.OutputPath);
    }

    [Fact]
    public async Task FailureInBothPlacesReportsErrorAndLeavesNoPartialFile()
    {
        var src = _dir.File("in/a.png");
        var fallback = Directory.CreateDirectory(Path.Combine(_dir.Path, "downloads")).FullName;
        var finished = new List<(CompressionResult? Result, string? Error)>();
        var engine = Engine((_, dst, _, _, _) => { File.WriteAllText(dst, "partial"); throw new IOException("encoder failed"); }, finished);
        engine.FallbackFolder = fallback;

        await engine.ProcessDroppedAsync([src], new());

        Assert.Equal("encoder failed", finished.Single().Error);
        Assert.Empty(Directory.GetFiles(fallback));
        Assert.Equal(["a.png"], Directory.GetFiles(Path.Combine(_dir.Path, "in")).Select(Path.GetFileName));
    }

    [Fact]
    public async Task CancelStopsJobDeletesOutputAndSkipsFallback()
    {
        var src = _dir.File("in/a.mp4");
        var fallback = Directory.CreateDirectory(Path.Combine(_dir.Path, "downloads")).FullName;
        var finished = new List<(CompressionResult? Result, string? Error)>();
        var started = new TaskCompletionSource();
        var engine = Engine(async (_, dst, _, control, _) =>
        {
            File.WriteAllText(dst, "partial");
            started.SetResult();
            await Task.Delay(Timeout.Infinite, control.Token);
        }, finished);
        engine.FallbackFolder = fallback;
        Guid id = default;
        engine.JobAdded += (jobId, _, _) => id = jobId;

        var run = engine.ProcessDroppedAsync([src], new());
        await started.Task;
        engine.Cancel(id);
        await run;

        Assert.Equal(MediaCompressionEngine.Cancelled, finished.Single().Error);
        Assert.False(File.Exists(Path.Combine(_dir.Path, "in", "a_min.mp4")));
        Assert.Empty(Directory.GetFiles(fallback));
    }

    [Fact]
    public async Task StagedItemsUsePerFileConfiguration()
    {
        var baseConfig = new CompressionConfiguration();
        var item = new StagedQueueItem(_dir.File("a.png"), 1, MediaType.Image, baseConfig) { CustomImageFormat = ImageFormatPolicy.JpegStandard };
        var finished = new List<(CompressionResult? Result, string? Error)>();
        await Engine(Copy, finished).ProcessStagedAsync([item, new StagedQueueItem(_dir.File("b.png"), 1, MediaType.Image, baseConfig)], baseConfig);
        Assert.Equal(["a_min.jpg", "b_min.png"], finished.Select(f => Path.GetFileName(f.Result!.OutputPath)).Order());
    }
}
