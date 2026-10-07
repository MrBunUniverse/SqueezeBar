using System.Runtime.InteropServices.WindowsRuntime;
using System.Text;
using SqueezeBar.Core;
using SqueezeBar.Media;
using Windows.Data.Pdf;
using Windows.Graphics.Imaging;
using Windows.Media.Editing;
using Windows.Media.MediaProperties;
using Windows.Storage;

namespace SqueezeBar.Media.Tests;

// These run on Windows only (in the VM: ./scripts/vm.sh 'dotnet test SqueezeBar.Media.Tests').
public class MediaTests : IDisposable
{
    readonly string _dir = Directory.CreateTempSubdirectory("sb-media-").FullName;
    public void Dispose() { try { Directory.Delete(_dir, true); } catch { } }

    string At(string name) => Path.Combine(_dir, name);
    static readonly IProgress<double> NoProgress = new Progress<double>();

    /// Writes a width x height image: left half opaque red, right half fully transparent.
    async Task<string> WriteImage(string name, Guid encoderId, int width, int height, ushort? orientation = null, BitmapPropertySet? tags = null)
    {
        var pixels = new byte[width * height * 4];
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width / 2; x++)
            {
                int i = (y * width + x) * 4;
                pixels[i + 2] = 255; pixels[i + 3] = 255;
            }
        using var stream = new FileStream(At(name), FileMode.Create, FileAccess.ReadWrite);
        var encoder = await BitmapEncoder.CreateAsync(encoderId, stream.AsRandomAccessStream());
        encoder.SetPixelData(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied, (uint)width, (uint)height, 96, 96, pixels);
        if (orientation is ushort o)
            await encoder.BitmapProperties.SetPropertiesAsync(new BitmapPropertySet
                { { "System.Photo.Orientation", new BitmapTypedValue(o, Windows.Foundation.PropertyType.UInt16) } });
        if (tags is not null) await encoder.BitmapProperties.SetPropertiesAsync(tags);
        await encoder.FlushAsync();
        return At(name);
    }

    static async Task<(BitmapDecoder Decoder, byte[] Pixels)> Read(string path)
    {
        using var stream = File.OpenRead(path);
        var decoder = await BitmapDecoder.CreateAsync(stream.AsRandomAccessStream());
        var pixels = (await decoder.GetPixelDataAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Straight, new BitmapTransform(),
            ExifOrientationMode.IgnoreExifOrientation, ColorManagementMode.DoNotColorManage)).DetachPixelData();
        return (decoder, pixels);
    }

    [Fact]
    public async Task ExplicitPngStaysPngWithAlphaAtLowQuality()
    {
        var source = await WriteImage("a.png", BitmapEncoder.PngEncoderId, 32, 24);
        var config = new CompressionConfiguration { ImageFormatPolicy = ImageFormatPolicy.PngLossless, ImageQuality = 0.3 };
        await Compressors.CompressImageAsync(source, At("out.png"), config, new(), NoProgress);

        Assert.Equal(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }, File.ReadAllBytes(At("out.png")).Take(8));
        var (decoder, pixels) = await Read(At("out.png"));
        Assert.Equal((32u, 24u), (decoder.PixelWidth, decoder.PixelHeight));
        Assert.Equal(255, pixels[3]);                 // left: opaque
        Assert.Equal(0, pixels[(32 - 1) * 4 + 3]);    // right: still transparent
    }

    [Fact]
    public async Task JpegOutputIsScaledAndTransparencyBecomesWhite()
    {
        var source = await WriteImage("a.png", BitmapEncoder.PngEncoderId, 200, 100);
        var config = new CompressionConfiguration { ImageFormatPolicy = ImageFormatPolicy.JpegStandard, ImageResolutionScale = 0.5 };
        await Compressors.CompressImageAsync(source, At("out.jpg"), config, new(), NoProgress);

        var (decoder, pixels) = await Read(At("out.jpg"));
        Assert.Equal((100u, 50u), (decoder.PixelWidth, decoder.PixelHeight));
        int right = (25 * 100 + 90) * 4;
        Assert.True(pixels[right] > 240 && pixels[right + 1] > 240 && pixels[right + 2] > 240, "transparent area should be white");
        int left = (25 * 100 + 10) * 4;
        Assert.True(pixels[left + 2] > 200 && pixels[left] < 60, "opaque area should stay red");
    }

    /// Mirrors the Mac orientation tests: EXIF rotation is baked into pixels, not left in metadata.
    [Fact]
    public async Task ExifRotationIsBakedIntoPixels()
    {
        // Stored 200x100 (left red, right black in a JPEG) with orientation 6 (rotate 90 clockwise to display)
        // => displays as 100x200 with the red half on top.
        var source = await WriteImage("a.jpg", BitmapEncoder.JpegEncoderId, 200, 100, orientation: 6);
        await Compressors.CompressImageAsync(source, At("out.jpg"), new() { ImageResolutionScale = 0.5 }, new(), NoProgress);

        var (decoder, pixels) = await Read(At("out.jpg"));
        Assert.Equal((50u, 100u), (decoder.PixelWidth, decoder.PixelHeight));
        Assert.Equal((50u, 100u), (decoder.OrientedPixelWidth, decoder.OrientedPixelHeight)); // no orientation tag left behind
        int top = (10 * 50 + 25) * 4, bottom = (90 * 50 + 25) * 4;
        Assert.True(pixels[top + 2] > 200 && pixels[top] < 60, "top should be red");
        Assert.True(pixels[bottom] < 40 && pixels[bottom + 2] < 40, "bottom should be the black half");
    }

    [Fact]
    public async Task MetadataIsKeptUnlessStripIsOn()
    {
        var source = await WriteImage("a.jpg", BitmapEncoder.JpegEncoderId, 64, 48, tags: new()
        {
            { "System.Photo.CameraModel", new BitmapTypedValue("SqueezeCam 1", Windows.Foundation.PropertyType.String) },
            { "System.Copyright", new BitmapTypedValue("SirJameTV", Windows.Foundation.PropertyType.String) },
        });

        async Task<string?> CameraOf(string path)
        {
            using var stream = File.OpenRead(path);
            var decoder = await BitmapDecoder.CreateAsync(stream.AsRandomAccessStream());
            var found = await decoder.BitmapProperties.GetPropertiesAsync(["System.Photo.CameraModel"]);
            return found.TryGetValue("System.Photo.CameraModel", out var value) ? value.Value as string : null;
        }
        Assert.Equal("SqueezeCam 1", await CameraOf(source));

        await Compressors.CompressImageAsync(source, At("kept.jpg"), new(), new(), NoProgress);
        Assert.Equal("SqueezeCam 1", await CameraOf(At("kept.jpg")));

        await Compressors.CompressImageAsync(source, At("stripped.jpg"), new() { StripMetadata = true }, new(), NoProgress);
        Assert.Null(await CameraOf(At("stripped.jpg")));
    }

    [Fact]
    public async Task WebpAndAvifAreWrittenThroughFfmpeg()
    {
        Assert.True(Ffmpeg.IsAvailable, "run scripts/fetch-ffmpeg.sh first");
        Assert.True(Compressors.CanEncodeImage("webp") && Compressors.CanEncodeImage("avif"));
        var source = await WriteImage("a.png", BitmapEncoder.PngEncoderId, 200, 100);

        await Compressors.CompressImageAsync(source, At("out.webp"), new() { ImageFormatPolicy = ImageFormatPolicy.WebpModern, ImageResolutionScale = 0.5 }, new(), NoProgress);
        // This Windows may lack a WebP decoder (it is a Store extension), so check the result via FFmpeg.
        await Ffmpeg.RunAsync(["-i", At("out.webp"), At("check.png")], 0, new(), null);
        var (webp, pixels) = await Read(At("check.png"));
        Assert.Equal((100u, 50u), (webp.PixelWidth, webp.PixelHeight));
        Assert.True(pixels[(25 * 100 + 10) * 4 + 2] > 200, "left half should stay red");
        Assert.True(pixels[(25 * 100 + 90) * 4 + 3] < 30, "right half should stay transparent");

        await Compressors.CompressImageAsync(source, At("out.avif"), new() { ImageFormatPolicy = ImageFormatPolicy.AvifModern }, new(), NoProgress);
        var avif = await Ffmpeg.ProbeAsync(At("out.avif"), default);
        Assert.Equal((200, 100), (avif.Width, avif.Height));
    }

    [Fact]
    public async Task ImageWindowsCannotReadIsDecodedByFfmpeg()
    {
        // A WebP original on a PC without the WebP extension: FFmpeg decodes, Windows encodes the JPEG.
        var png = await WriteImage("a.png", BitmapEncoder.PngEncoderId, 200, 100);
        await Ffmpeg.RunAsync(["-i", png, "-c:v", "libwebp", "-lossless", "1", At("in.webp")], 0, new(), null);
        await Compressors.CompressImageAsync(At("in.webp"), At("out.jpg"), new() { ImageFormatPolicy = ImageFormatPolicy.JpegStandard }, new(), NoProgress);
        var (decoder, pixels) = await Read(At("out.jpg"));
        Assert.Equal((200u, 100u), (decoder.PixelWidth, decoder.PixelHeight));
        Assert.True(pixels[(50 * 200 + 20) * 4 + 2] > 200, "left half should stay red");
    }

    /// Makes a clip with FFmpeg itself: 2 s of moving test pattern, 320x180 stored, with a tone.
    async Task<string> WriteClip(string name, string videoCodec, string audioCodec = "aac")
    {
        await Ffmpeg.RunAsync(["-f", "lavfi", "-i", "testsrc2=size=320x180:rate=30:duration=2", "-f", "lavfi", "-i", "sine=frequency=440:duration=2",
            "-c:v", videoCodec, "-pix_fmt", "yuv420p", "-c:a", audioCodec, At(name)], 2, new(), null);
        return At(name);
    }

    /// The case that failed in the VM: an HEVC original on a PC without the HEVC extension.
    [Theory]
    [InlineData("hevc.mp4", "libx265")]
    [InlineData("av1.mkv", "libsvtav1")]
    public async Task VideoWindowsCannotReadFallsBackToFfmpeg(string name, string sourceCodec)
    {
        var source = await WriteClip(name, sourceCodec, name.EndsWith("mkv") ? "libopus" : "aac");
        var config = new CompressionConfiguration { VideoCodec = VideoCodecPreference.H264, VideoResolutionScale = 0.5 };
        var reported = new List<double>();
        await Compressors.CompressVideoAsync(source, At("out.mp4"), config, new(), new SyncProgress(reported.Add));

        var output = await Describe(At("out.mp4"));
        Assert.Equal("H264", output.Video.Subtype);
        Assert.Equal((160u, 90u), (output.Video.Width, output.Video.Height));
        Assert.True(output.Audio.SampleRate > 0, "audio track should be kept");
        Assert.NotEmpty(reported);
    }

    [Fact]
    public async Task HevcOutputWorksWithoutAWindowsHevcEncoder()
    {
        var source = await WriteClip("h264.mp4", "libx264");
        await Compressors.CompressVideoAsync(source, At("out.mp4"), new() { VideoCodec = VideoCodecPreference.Hevc }, new(), NoProgress);
        var output = await Ffmpeg.ProbeAsync(At("out.mp4"), default);
        Assert.Equal((320, 180), (output.Width, output.Height));
    }

    /// Mirrors the Mac orientation rule: a portrait phone clip must come out portrait, not sideways or squashed.
    [Theory]
    [InlineData("libx264")]   // Windows can read this one, so the native path runs
    [InlineData("libx265")]   // FFmpeg path
    public async Task RotatedVideoKeepsItsDisplayOrientation(string sourceCodec)
    {
        // Stored 320x180 with a 90-degree rotation flag: it displays as 180x320.
        await WriteClip("flat.mp4", sourceCodec);
        await Ffmpeg.RunAsync(["-display_rotation", "90", "-i", At("flat.mp4"), "-c", "copy", At("rotated.mp4")], 2, new(), null);
        var source = await Ffmpeg.ProbeAsync(At("rotated.mp4"), default);
        Assert.Equal((180, 320), (source.Width, source.Height));

        await Compressors.CompressVideoAsync(At("rotated.mp4"), At("out.mp4"), new() { VideoCodec = VideoCodecPreference.H264 }, new(), NoProgress);
        var output = await Ffmpeg.ProbeAsync(At("out.mp4"), default);
        Assert.Equal((180, 320), (output.Width, output.Height));
    }

    [Fact]
    public async Task GifOutputFollowsSizeAndFrameRateCaps()
    {
        var source = await WriteClip("h264.mp4", "libx264");
        var config = new CompressionConfiguration { VideoCodec = VideoCodecPreference.Gif, GifFramerate = GifFramerateOption.Compact10, VideoResolutionScale = 0.25 };
        await Compressors.CompressVideoAsync(source, At("out.gif"), config, new(), NoProgress);

        Assert.Equal("GIF8", System.Text.Encoding.ASCII.GetString(File.ReadAllBytes(At("out.gif")), 0, 4));
        var output = await Ffmpeg.ProbeAsync(At("out.gif"), default);
        Assert.Equal((160, 90), (output.Width, output.Height));   // long edge capped at 640 * 0.25
        Assert.Equal(10, output.Fps, 0);
    }

    [Fact]
    public async Task AudioWindowsCannotReadFallsBackToFfmpeg()
    {
        await Ffmpeg.RunAsync(["-f", "lavfi", "-i", "sine=frequency=440:duration=2", "-c:a", "libopus", At("a.ogg")], 2, new(), null);
        await Compressors.CompressAudioAsync(At("a.ogg"), At("out.m4a"), new() { AudioBitrate = AudioBitratePreference.K64 }, new(), NoProgress);
        Assert.Equal("AAC", (await Describe(At("out.m4a"))).Audio.Subtype);
    }

    [Fact]
    public async Task FfmpegEncodeCanBeCancelled()
    {
        var control = new JobControl();
        var encode = Ffmpeg.RunAsync(["-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=30:duration=600", "-c:v", "libx265", At("long.mp4")], 600, control, null);
        await Task.Delay(1500);
        control.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => encode);
    }

    async Task<string> WriteVideo(string name)
    {
        var composition = new MediaComposition();
        foreach (var i in Enumerable.Range(0, 4))
        {
            var frame = await StorageFile.GetFileFromPathAsync(await WriteImage($"f{i}.png", BitmapEncoder.PngEncoderId, 640 + i * 2, 360));
            composition.Clips.Add(await MediaClip.CreateFromImageFileAsync(frame, TimeSpan.FromSeconds(0.5)));
        }
        composition.BackgroundAudioTracks.Add(await BackgroundAudioTrack.CreateFromFileAsync(
            await StorageFile.GetFileFromPathAsync(@"C:\Windows\Media\Alarm01.wav")));
        var folder = await StorageFolder.GetFolderFromPathAsync(_dir);
        var file = await folder.CreateFileAsync(name, CreationCollisionOption.ReplaceExisting);
        var profile = MediaEncodingProfile.CreateMp4(VideoEncodingQuality.Vga);
        profile.Video.Width = 640; profile.Video.Height = 360;
        await composition.RenderToFileAsync(file, MediaTrimmingPreference.Precise, profile);
        return file.Path;
    }

    static async Task<MediaEncodingProfile> Describe(string path) =>
        await MediaEncodingProfile.CreateFromFileAsync(await StorageFile.GetFileFromPathAsync(path));

    [Fact]
    public async Task VideoIsResizedSlowedAndKeepsAudio()
    {
        var source = await WriteVideo("v.mp4");
        var config = new CompressionConfiguration
            { VideoCodec = VideoCodecPreference.H264, VideoResolutionScale = 0.5, VideoFramerate = VideoFramerateOption.Fps15 };
        var reported = new List<double>();
        await Compressors.CompressVideoAsync(source, At("out.mp4"), config, new(), new SyncProgress(reported.Add));

        var output = await Describe(At("out.mp4"));
        Assert.Equal((320u, 180u), (output.Video.Width, output.Video.Height));
        Assert.Equal(15.0, (double)output.Video.FrameRate.Numerator / output.Video.FrameRate.Denominator, 1);
        Assert.True(output.Audio.SampleRate > 0, "audio track should be kept");
        Assert.Contains(reported, p => p > 0.9);
    }

    [Fact]
    public async Task HevcRequestStillProducesAVideoAndRemoveAudioDropsTheTrack()
    {
        // Machines without an HEVC encoder (like the test VM) must fall back to H.264 instead of failing.
        var source = await WriteVideo("v.mp4");
        await Compressors.CompressVideoAsync(source, At("out.mp4"), new() { VideoRemoveAudio = true }, new(), NoProgress);
        var output = await Describe(At("out.mp4"));
        Assert.Equal((640u, 360u), (output.Video.Width, output.Video.Height));
        Assert.True(output.Audio is null || output.Audio.SampleRate == 0, "audio track should be removed");
    }

    [Fact]
    public async Task VideoAndAudioRefuseToOverwriteSource()
    {
        var source = At("clip.mp4");
        File.WriteAllText(source, "original");
        await Assert.ThrowsAnyAsync<Exception>(() => Compressors.CompressVideoAsync(source, source, new(), new(), NoProgress));
        await Assert.ThrowsAnyAsync<Exception>(() => Compressors.CompressAudioAsync(source, source, new(), new(), NoProgress));
        Assert.Equal("original", File.ReadAllText(source));
    }

    [Fact]
    public async Task CancelledVideoThrows()
    {
        var source = await WriteVideo("v.mp4");
        var control = new JobControl();
        control.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            Compressors.CompressVideoAsync(source, At("out.mp4"), new(), control, NoProgress));
    }

    [Theory]
    [InlineData(AudioBitratePreference.K16)]
    [InlineData(AudioBitratePreference.K64)]
    [InlineData(AudioBitratePreference.K320)]
    public async Task AudioIsEncodedToAacAtRequestedBitrate(AudioBitratePreference bitrate)
    {
        await Compressors.CompressAudioAsync(@"C:\Windows\Media\Alarm01.wav", At("out.m4a"), new() { AudioBitrate = bitrate }, new(), NoProgress);
        var output = await Describe(At("out.m4a"));
        Assert.Equal("AAC", output.Audio.Subtype);
        Assert.InRange(output.Audio.Bitrate, (uint)bitrate * 0.8, (uint)bitrate * 1.2);
    }

    [Fact]
    public async Task PdfIsRewrittenWithSamePagesAndSize()
    {
        var objects = new[]
        {
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R 6 0 R] /Count 2 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
            "<< /Length 44 >>\nstream\nBT /F1 48 Tf 72 700 Td (SqueezeBar) Tj ET\nendstream",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 792 612] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
        };
        var pdf = new StringBuilder("%PDF-1.4\n");
        var offsets = new List<int>();
        for (int i = 0; i < objects.Length; i++) { offsets.Add(pdf.Length); pdf.Append($"{i + 1} 0 obj\n{objects[i]}\nendobj\n"); }
        int xref = pdf.Length;
        pdf.Append($"xref\n0 {objects.Length + 1}\n0000000000 65535 f \n");
        foreach (var o in offsets) pdf.Append($"{o:D10} 00000 n \n");
        pdf.Append($"trailer\n<< /Size {objects.Length + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n");
        File.WriteAllText(At("in.pdf"), pdf.ToString(), Encoding.ASCII);

        foreach (var grayscale in new[] { false, true })
        {
            var result = At($"out-{grayscale}.pdf");
            await Compressors.CompressPdfAsync(At("in.pdf"), result, new() { PdfGrayscale = grayscale, PdfDpi = PdfDpiOption.Dpi72 }, new(), NoProgress);
            var output = await PdfDocument.LoadFromFileAsync(await StorageFile.GetFileFromPathAsync(result));
            Assert.Equal(2u, output.PageCount);
            using var first = output.GetPage(0);
            using var second = output.GetPage(1);
            Assert.Equal((816.0, 1056.0), (Math.Round(first.Size.Width), Math.Round(first.Size.Height)));
            Assert.Equal((1056.0, 816.0), (Math.Round(second.Size.Width), Math.Round(second.Size.Height)));
        }
    }

    sealed class SyncProgress(Action<double> report) : IProgress<double>
    {
        public void Report(double value) { lock (this) report(value); }
    }
}
