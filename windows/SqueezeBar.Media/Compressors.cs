using System.Runtime.InteropServices.WindowsRuntime;
using System.Text;
using SqueezeBar.Core;
using Windows.Data.Pdf;
using Windows.Graphics.Imaging;
using Windows.Media.MediaProperties;
using Windows.Media.Transcoding;
using Windows.Storage;
using Windows.Storage.Streams;

namespace SqueezeBar.Media;

/// <summary>
/// The four compressors. First choice is what ships with Windows: WIC for images, Media Foundation
/// (through MediaTranscoder) for video and audio, Windows.Data.Pdf for PDFs. The bundled FFmpeg
/// (<see cref="Ffmpeg"/>) covers what Windows can't read or write. No network at any point.
/// </summary>
public static class Compressors
{
    public static IReadOnlyDictionary<MediaType, CompressFn> All { get; } = new Dictionary<MediaType, CompressFn>
    {
        [MediaType.Image] = CompressImageAsync,
        [MediaType.Video] = CompressVideoAsync,
        [MediaType.Audio] = CompressAudioAsync,
        [MediaType.Pdf] = CompressPdfAsync,
    };

    // MARK: - Images

    static Guid? EncoderFor(string ext) => ext switch
    {
        "jpg" or "jpeg" => BitmapEncoder.JpegEncoderId,
        "png" => BitmapEncoder.PngEncoderId,
        "heic" or "heif" => BitmapEncoder.HeifEncoderId,
        "tif" or "tiff" => BitmapEncoder.TiffEncoderId,
        "bmp" => BitmapEncoder.BmpEncoderId,
        "gif" => BitmapEncoder.GifEncoderId,
        _ => null,
    };

    static bool _heifWorks;

    /// <summary>
    /// Windows lists a HEIF encoder even when the HEVC encoder behind it is missing, so try it once.
    /// Call from a background thread at startup, before <see cref="CanEncodeImage"/> is used.
    /// </summary>
    public static async Task ProbeAsync()
    {
        try
        {
            using var stream = new InMemoryRandomAccessStream();
            var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.HeifEncoderId, stream);
            encoder.SetPixelData(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Ignore, 16, 16, 96, 96, new byte[16 * 16 * 4]);
            await encoder.FlushAsync();
            _heifWorks = true;
        }
        catch { _heifWorks = false; }
    }

    /// <summary>Whether this machine can write the given image extension (WebP and AVIF through FFmpeg; HEIC only with an HEVC encoder).</summary>
    public static bool CanEncodeImage(string ext) =>
        ext is "webp" or "avif" ? Ffmpeg.IsAvailable : EncoderFor(ext) is Guid id && (id != BitmapEncoder.HeifEncoderId || _heifWorks);

    public static async Task CompressImageAsync(string source, string destination, CompressionConfiguration config, JobControl control, IProgress<double> progress)
    {
        RefuseSameFile(source, destination);
        try { await EncodeImageAsync(source, source, destination, config, control, progress); }
        catch (Exception) when (!control.IsCancelled && Ffmpeg.IsAvailable)
        {
            // Windows couldn't read it (HEIC without the HEVC extension, unusual formats): let FFmpeg turn it into a PNG first.
            // ponytail: relies on FFmpeg applying the EXIF orientation of such files; verify with rotated HEIC samples.
            var decoded = TempFile(".png");
            try
            {
                await Ffmpeg.RunAsync(["-i", source, "-frames:v", "1", decoded], 0, control, null);
                await EncodeImageAsync(decoded, source, destination, config, control, progress);
            }
            finally { TryDelete(decoded); }
        }
    }

    /// <param name="pixelSource">File to decode.</param>
    /// <param name="original">The user's file, whose size drives target-size planning.</param>
    static async Task EncodeImageAsync(string pixelSource, string original, string destination, CompressionConfiguration config, JobControl control, IProgress<double> progress)
    {
        var ext = Path.GetExtension(destination).TrimStart('.').ToLowerInvariant();
        bool viaFfmpeg = ext is "webp" or "avif";
        var encoderId = viaFfmpeg ? BitmapEncoder.PngEncoderId : EncoderFor(ext) ?? throw new NotSupportedException($"Windows cannot write .{ext} images.");

        using var input = await (await StorageFile.GetFileFromPathAsync(pixelSource)).OpenReadAsync();
        var decoder = await BitmapDecoder.CreateAsync(input);
        // ponytail: first frame only would silently flatten an animation, so refuse instead; needs a per-frame loop.
        if (decoder.FrameCount > 1) throw new NotSupportedException("Animated images are not supported on Windows yet.");
        progress.Report(0.15);

        int orientedWidth = (int)decoder.OrientedPixelWidth, orientedHeight = (int)decoder.OrientedPixelHeight;
        var plan = ImagePlan.For(config, ext, new FileInfo(original).Length, orientedWidth, orientedHeight);
        double scale = plan.Scale(config.ImageResolutionScale, Math.Max(orientedWidth, orientedHeight));
        int width = Math.Max(1, (int)Math.Round(orientedWidth * scale)), height = Math.Max(1, (int)Math.Round(orientedHeight * scale));

        // The scale is applied before the EXIF rotation, so it is given in the stored (unrotated) orientation.
        bool rotated = decoder.OrientedPixelWidth != decoder.PixelWidth;
        var transform = new BitmapTransform
        {
            ScaledWidth = (uint)(rotated ? height : width),
            ScaledHeight = (uint)(rotated ? width : height),
            InterpolationMode = BitmapInterpolationMode.Fant,
        };
        // RespectExifOrientation bakes rotation/mirroring into the pixels, so dropping metadata can't turn a portrait sideways.
        var pixels = (await decoder.GetPixelDataAsync(
            BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied, transform,
            ExifOrientationMode.RespectExifOrientation, ColorManagementMode.ColorManageToSRgb)).DetachPixelData();
        control.Token.ThrowIfCancellationRequested();
        progress.Report(0.50);

        if (plan.JpegInsidePng) encoderId = BitmapEncoder.JpegEncoderId;
        // ponytail: AVIF is written without transparency; add an alpha plane if transparent AVIFs matter.
        bool opaque = ext == "avif" || encoderId == BitmapEncoder.JpegEncoderId || encoderId == BitmapEncoder.HeifEncoderId || encoderId == BitmapEncoder.BmpEncoderId;
        if (opaque) FlattenOntoWhite(pixels);

        var options = new BitmapPropertySet();
        if (encoderId == BitmapEncoder.JpegEncoderId || encoderId == BitmapEncoder.HeifEncoderId)
            options.Add("ImageQuality", new BitmapTypedValue((float)plan.Quality, Windows.Foundation.PropertyType.Single));

        // WebP and AVIF have no Windows encoder: write the prepared pixels as a lossless PNG and let FFmpeg encode that.
        var wicTarget = viaFfmpeg ? TempFile(".png") : destination;
        try
        {
            using (var file = new FileStream(wicTarget, FileMode.Create, FileAccess.ReadWrite))
            {
                var encoder = await BitmapEncoder.CreateAsync(encoderId, file.AsRandomAccessStream(), options);
                encoder.SetPixelData(BitmapPixelFormat.Bgra8, opaque ? BitmapAlphaMode.Ignore : BitmapAlphaMode.Premultiplied,
                    (uint)width, (uint)height, decoder.DpiX, decoder.DpiY, pixels);
                // ponytail: tags are lost on the WebP/AVIF route (FFmpeg re-encodes the temp PNG); pass them with -metadata if needed.
                if (!config.StripMetadata && !viaFfmpeg) await CopyMetadataAsync(decoder, encoder);
                await encoder.FlushAsync();
            }
            if (viaFfmpeg)
            {
                progress.Report(0.70);
                string[] codec = ext == "webp"
                    ? ["-c:v", "libwebp", "-quality", ((int)Math.Round(plan.Quality * 100)).ToString()]
                    // CRF 63 is worst, 0 lossless; this maps 100% -> 13 and 30% -> 48.
                    : ["-c:v", "libsvtav1", "-crf", ((int)Math.Round(63 - plan.Quality * 50)).ToString(), "-pix_fmt", "yuv420p", "-frames:v", "1"];
                await Ffmpeg.RunAsync(["-i", wicTarget, .. codec, destination], 0, control, null);
            }
        }
        finally { if (viaFfmpeg) TryDelete(wicTarget); }
        progress.Report(1.0);
    }

    // Orientation is deliberately absent: rotation is already baked into the pixels.
    static readonly string[] KeptMetadata =
    [
        "System.Photo.DateTaken", "System.Photo.CameraManufacturer", "System.Photo.CameraModel", "System.Photo.LensModel",
        "System.Photo.ExposureTime", "System.Photo.FNumber", "System.Photo.ISOSpeed", "System.Photo.FocalLength",
        "System.Author", "System.Title", "System.Copyright", "System.Comment",
        "System.GPS.Latitude", "System.GPS.LatitudeRef", "System.GPS.Longitude", "System.GPS.LongitudeRef",
        "System.GPS.Altitude", "System.GPS.AltitudeRef",
    ];

    /// <summary>Carries camera, date, author and location tags over. Fields the output format can't hold are skipped.</summary>
    static async Task CopyMetadataAsync(BitmapDecoder decoder, BitmapEncoder encoder)
    {
        foreach (var name in KeptMetadata)
        {
            try
            {
                var found = await decoder.BitmapProperties.GetPropertiesAsync([name]);
                if (found.Count > 0) await encoder.BitmapProperties.SetPropertiesAsync(found);
            }
            catch { /* not present, or not supported by this container: the picture matters more than one tag */ }
        }
    }

    static string TempFile(string extension) => Path.Combine(Path.GetTempPath(), $"squeezebar-{Guid.NewGuid():N}{extension}");

    static void TryDelete(string path)
    {
        try { File.Delete(path); }
        catch { /* temp file; Windows clears the temp folder eventually */ }
    }

    /// <summary>Premultiplied BGRA over white, for formats without transparency.</summary>
    static void FlattenOntoWhite(byte[] bgra)
    {
        for (int i = 0; i < bgra.Length; i += 4)
        {
            int inverse = 255 - bgra[i + 3];
            if (inverse == 0) continue;
            bgra[i] = (byte)Math.Min(255, bgra[i] + inverse);
            bgra[i + 1] = (byte)Math.Min(255, bgra[i + 1] + inverse);
            bgra[i + 2] = (byte)Math.Min(255, bgra[i + 2] + inverse);
            bgra[i + 3] = 255;
        }
    }

    // MARK: - Video

    public static async Task CompressVideoAsync(string source, string destination, CompressionConfiguration config, JobControl control, IProgress<double> progress)
    {
        RefuseSameFile(source, destination);
        if (config.VideoCodec == VideoCodecPreference.Gif)
        {
            if (!Ffmpeg.IsAvailable) throw new NotSupportedException("GIF output needs the bundled FFmpeg, which is missing from this build.");
            await FfmpegGifAsync(source, destination, config, control, progress);
            return;
        }
        // Windows' own encoder first: it is hardware accelerated and Windows picks the GPU. FFmpeg takes
        // over for anything Windows can't read or write (HEVC without the paid extension, MKV, WebM...).
        try { await NativeVideoAsync(source, destination, config, control, progress); }
        catch (Exception) when (!control.IsCancelled && Ffmpeg.IsAvailable)
        {
            await FfmpegVideoAsync(source, destination, config, control, progress);
        }
    }

    static async Task NativeVideoAsync(string source, string destination, CompressionConfiguration config, JobControl control, IProgress<double> progress)
    {
        var input = await StorageFile.GetFileFromPathAsync(source);
        var sourceProfile = await MediaEncodingProfile.CreateFromFileAsync(input);
        var video = sourceProfile.Video;
        if (video is null || video.Width == 0 || video.Height == 0) throw new InvalidDataException("No video track found.");
        double duration = (await input.Properties.GetVideoPropertiesAsync()).Duration.TotalSeconds;
        if (duration <= 0) throw new InvalidDataException("The video has no duration.");

        double sourceBitrate = video.Bitrate > 0 ? video.Bitrate : new FileInfo(source).Length * 8.0 / duration;
        var plan = VideoPlan.For(config, (int)video.Width, (int)video.Height, duration, sourceBitrate);
        double sourceFps = video.FrameRate.Denominator > 0 ? (double)video.FrameRate.Numerator / video.FrameRate.Denominator : 0;
        int targetFps = (int)config.VideoFramerate;
        bool keepAudio = plan.AudioBitrate > 0 && sourceProfile.Audio is { SampleRate: > 0 };

        MediaEncodingProfile Profile(bool hevc, bool safeAudio)
        {
            var profile = hevc ? MediaEncodingProfile.CreateHevc(VideoEncodingQuality.HD1080p) : MediaEncodingProfile.CreateMp4(VideoEncodingQuality.HD1080p);
            profile.Video.Width = (uint)plan.Width;
            profile.Video.Height = (uint)plan.Height;
            profile.Video.Bitrate = (uint)plan.VideoBitrate;
            // Only ever lower the frame rate; a higher target would just duplicate frames.
            bool lower = targetFps > 0 && (sourceFps == 0 || targetFps < sourceFps - 0.5);
            profile.Video.FrameRate.Numerator = lower ? (uint)targetFps : video.FrameRate.Numerator;
            profile.Video.FrameRate.Denominator = lower ? 1 : video.FrameRate.Denominator;
            if (!keepAudio) profile.Audio = null;
            else
            {
                profile.Audio.Bitrate = (uint)plan.AudioBitrate;
                if (!safeAudio)
                {
                    profile.Audio.ChannelCount = Math.Min((uint)plan.AudioChannels, sourceProfile.Audio.ChannelCount);
                    profile.Audio.SampleRate = (uint)plan.AudioSampleRate;
                }
            }
            return profile;
        }

        // Windows picks the hardware encoder for whatever GPU is present. If that fails, fall back
        // to software, then from HEVC to H.264, then to the encoder's default audio layout.
        bool wantHevc = config.VideoCodec == VideoCodecPreference.Hevc;
        (bool Hevc, bool Hardware, bool SafeAudio)[] attempts =
            [(true, true, false), (true, false, false), (false, true, false), (false, false, false), (false, false, true)];
        try
        {
            await TranscodeAsync(input, destination, control, progress,
                attempts.Where(a => wantHevc || !a.Hevc).Select(a => (Profile(a.Hevc, a.SafeAudio), a.Hardware)));
        }
        catch (InvalidOperationException) when (video.Subtype?.ToUpperInvariant() is "HEVC" or "HVC1" or "HEV1" or "HEVCES")
        {
            // Windows only reads HEVC with a hardware decoder or the HEVC Video Extensions installed.
            throw new NotSupportedException(
                "The original file is an HEVC (H.265) video and this PC cannot open HEVC, whatever output codec is chosen. " +
                "This build has no bundled FFmpeg to fall back on; install \"HEVC Video Extensions\" from the Microsoft Store.");
        }
    }

    static async Task FfmpegVideoAsync(string source, string destination, CompressionConfiguration config, JobControl control, IProgress<double> progress)
    {
        var info = await Ffmpeg.ProbeAsync(source, control.Token);
        if (!info.HasVideo || info.Duration <= 0) throw new InvalidDataException("No video track found.");
        // FFmpeg rotates frames to their display orientation, so the plan works on displayed dimensions
        // and no rotation flag is left in the output.
        var plan = VideoPlan.For(config, info.Width, info.Height, info.Duration, info.VideoBitrate > 0 ? info.VideoBitrate : new FileInfo(source).Length * 8.0 / info.Duration);
        int targetFps = (int)config.VideoFramerate;
        bool hevc = config.VideoCodec == VideoCodecPreference.Hevc;

        var common = new List<string> { "-i", source, "-map", "0:v:0" };
        if (plan.Width != info.Width || plan.Height != info.Height) common.AddRange(["-vf", $"scale={plan.Width}:{plan.Height}:flags=lanczos"]);
        if (targetFps > 0 && (info.Fps == 0 || targetFps < info.Fps - 0.5)) common.AddRange(["-r", targetFps.ToString()]);
        common.AddRange(["-b:v", plan.VideoBitrate.ToString(), "-maxrate", (plan.VideoBitrate * 3L / 2).ToString(), "-bufsize", (plan.VideoBitrate * 2L).ToString()]);
        if (plan.AudioBitrate > 0 && info.HasAudio)
            common.AddRange(["-map", "0:a:0", "-c:a", "aac", "-b:a", plan.AudioBitrate.ToString(), "-ac", plan.AudioChannels.ToString(), "-ar", plan.AudioSampleRate.ToString()]);
        else common.Add("-an");
        if (hevc) common.AddRange(["-tag:v", "hvc1"]); // the tag Apple players expect
        common.AddRange(["-movflags", "+faststart", destination]);

        // A hardware encoder through Media Foundation when the PC has one (fast), otherwise x264/x265 in
        // software, which works on any machine and gives HandBrake-class results.
        string[][] encoders =
        [
            ["-c:v", hevc ? "hevc_mf" : "h264_mf", "-hw_encoding", "1"],
            ["-c:v", hevc ? "libx265" : "libx264", "-preset", "medium", "-pix_fmt", "yuv420p"],
        ];
        for (int i = 0; ; i++)
        {
            // Encoder options go after the input and before the output; "-i source" is the first two items.
            try { await Ffmpeg.RunAsync([.. common[..2], .. encoders[i], .. common[2..]], info.Duration, control, progress); return; }
            catch (InvalidOperationException) when (i + 1 < encoders.Length && !control.IsCancelled) { }
        }
    }

    /// <summary>Looping GIF with the Mac app's sizing: long edge capped at 640 px times the resolution scale.</summary>
    static async Task FfmpegGifAsync(string source, string destination, CompressionConfiguration config, JobControl control, IProgress<double> progress)
    {
        var info = await Ffmpeg.ProbeAsync(source, control.Token);
        if (!info.HasVideo || info.Duration <= 0) throw new InvalidDataException("No video track found.");
        double sourceFps = info.Fps > 0 ? info.Fps : 30;
        double fps = (int)config.GifFramerate is > 0 and var cap ? Math.Min(sourceFps, cap) : sourceFps;
        double scale = Math.Min(1.0, 640.0 * Math.Clamp(config.VideoResolutionScale, 0.20, 1.0) / Math.Max(info.Width, info.Height));
        int width = Math.Max(1, (int)Math.Round(info.Width * scale)), height = Math.Max(1, (int)Math.Round(info.Height * scale));
        var invariant = System.Globalization.CultureInfo.InvariantCulture;
        // One pass: build a palette from the clip, then map every frame onto it.
        string filter = $"fps={fps.ToString("0.###", invariant)},scale={width}:{height}:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5";
        await Ffmpeg.RunAsync(["-i", source, "-filter_complex", filter, "-loop", "0", destination], info.Duration, control, progress);
    }

    // MARK: - Audio

    public static async Task CompressAudioAsync(string source, string destination, CompressionConfiguration config, JobControl control, IProgress<double> progress)
    {
        RefuseSameFile(source, destination);
        try { await NativeAudioAsync(source, destination, config, control, progress); }
        catch (Exception) when (!control.IsCancelled && Ffmpeg.IsAvailable)
        {
            // Formats Windows can't read (Ogg, Opus, CAF...).
            var info = await Ffmpeg.ProbeAsync(source, control.Token);
            if (!info.HasAudio) throw new InvalidDataException("No audio track found.");
            var plan = AudioPlan.For(config, info.Duration);
            await Ffmpeg.RunAsync(["-i", source, "-vn", "-c:a", "aac", "-b:a", plan.Bitrate.ToString(), "-ac", plan.Channels.ToString(), "-ar", plan.SampleRate.ToString(), destination],
                info.Duration, control, progress);
        }
    }

    static async Task NativeAudioAsync(string source, string destination, CompressionConfiguration config, JobControl control, IProgress<double> progress)
    {
        var input = await StorageFile.GetFileFromPathAsync(source);
        double duration = (await input.Properties.GetMusicPropertiesAsync()).Duration.TotalSeconds;
        var plan = AudioPlan.For(config, duration);

        MediaEncodingProfile Profile(bool safe)
        {
            var profile = MediaEncodingProfile.CreateM4a(AudioEncodingQuality.Medium);
            profile.Audio.Bitrate = (uint)plan.Bitrate;
            if (!safe)
            {
                profile.Audio.ChannelCount = (uint)plan.Channels;
                profile.Audio.SampleRate = (uint)plan.SampleRate;
            }
            return profile;
        }
        await TranscodeAsync(input, destination, control, progress, [(Profile(false), true), (Profile(true), true)]);
    }

    static async Task TranscodeAsync(StorageFile input, string destination, JobControl control, IProgress<double> progress,
        IEnumerable<(MediaEncodingProfile Profile, bool Hardware)> attempts)
    {
        var folder = await StorageFolder.GetFolderFromPathAsync(Path.GetDirectoryName(destination)!);
        string reason = "no encoder";
        foreach (var (profile, hardware) in attempts)
        {
            control.Token.ThrowIfCancellationRequested();
            var output = await folder.CreateFileAsync(Path.GetFileName(destination), CreationCollisionOption.ReplaceExisting);
            var transcoder = new MediaTranscoder { HardwareAccelerationEnabled = hardware, AlwaysReencode = true };
            var prepared = await transcoder.PrepareFileTranscodeAsync(input, output, profile);
            if (!prepared.CanTranscode) { reason = prepared.FailureReason.ToString(); continue; }
            try
            {
                // ponytail: MediaTranscoder can be cancelled but not paused; pausing needs a Source Reader / Sink Writer loop.
                await prepared.TranscodeAsync().AsTask(control.Token, new Relay(percent => progress.Report(0.05 + percent / 100.0 * 0.95)));
                return;
            }
            catch (Exception e) when (!control.IsCancelled) { reason = e.Message.Trim(); }
        }
        throw new InvalidOperationException($"Windows could not encode this file ({reason}).");
    }

    sealed class Relay(Action<double> report) : IProgress<double>
    {
        public void Report(double value) => report(value);
    }

    // MARK: - PDF

    /// <summary>Rasterises each page to a JPEG at the chosen DPI and writes an image-only PDF, as the Mac app does.</summary>
    public static async Task CompressPdfAsync(string source, string destination, CompressionConfiguration config, JobControl control, IProgress<double> progress)
    {
        RefuseSameFile(source, destination);
        var document = await PdfDocument.LoadFromFileAsync(await StorageFile.GetFileFromPathAsync(source));
        if (document.PageCount == 0) throw new InvalidDataException("The PDF has no pages.");
        var plan = PdfPlan.For(config, new FileInfo(source).Length, (int)document.PageCount);

        using var file = new FileStream(destination, FileMode.Create, FileAccess.Write);
        var offsets = new List<long> { 0, 0 }; // objects 1 (catalog) and 2 (page tree) are written last
        void Write(string text) => file.Write(Encoding.Latin1.GetBytes(text));
        void BeginObject(int number)
        {
            while (offsets.Count < number) offsets.Add(0);
            offsets[number - 1] = file.Position;
            Write($"{number} 0 obj\n");
        }

        Write("%PDF-1.4\n%âãÏÓ\n");
        var pageObjects = new List<int>();
        for (uint index = 0; index < document.PageCount; index++)
        {
            control.Token.ThrowIfCancellationRequested();
            using var page = document.GetPage(index);
            // Page size is in 1/96 inch units.
            int pixelWidth = Math.Max(1, (int)Math.Round(page.Size.Width / 96.0 * plan.Dpi));
            int pixelHeight = Math.Max(1, (int)Math.Round(page.Size.Height / 96.0 * plan.Dpi));
            var jpeg = await RenderPageAsync(page, pixelWidth, pixelHeight, plan.Quality, config.PdfGrayscale);

            var invariant = System.Globalization.CultureInfo.InvariantCulture;
            string pointWidth = (page.Size.Width * 0.75).ToString("0.###", invariant), pointHeight = (page.Size.Height * 0.75).ToString("0.###", invariant);
            int pageNumber = 3 + (int)index * 3, contentNumber = pageNumber + 1, imageNumber = pageNumber + 2;
            pageObjects.Add(pageNumber);

            BeginObject(pageNumber);
            Write($"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {pointWidth} {pointHeight}] /Contents {contentNumber} 0 R /Resources << /XObject << /Im0 {imageNumber} 0 R >> >> >>\nendobj\n");
            string content = $"q {pointWidth} 0 0 {pointHeight} 0 0 cm /Im0 Do Q";
            BeginObject(contentNumber);
            Write($"<< /Length {content.Length} >>\nstream\n{content}\nendstream\nendobj\n");
            BeginObject(imageNumber);
            Write($"<< /Type /XObject /Subtype /Image /Width {pixelWidth} /Height {pixelHeight} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length {jpeg.Length} >>\nstream\n");
            file.Write(jpeg);
            Write("\nendstream\nendobj\n");

            progress.Report((index + 1.0) / document.PageCount);
        }

        // ponytail: source metadata is never copied (Windows.Data.Pdf doesn't expose it), so pdfStripMetadata=false has no effect.
        int infoNumber = 3 + pageObjects.Count * 3;
        BeginObject(infoNumber);
        Write("<< /Producer (SqueezeBar PDF Optimizer) >>\nendobj\n");
        BeginObject(1);
        Write("<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
        BeginObject(2);
        Write($"<< /Type /Pages /Count {pageObjects.Count} /Kids [{string.Join(" ", pageObjects.Select(n => $"{n} 0 R"))}] >>\nendobj\n");

        long xref = file.Position;
        Write($"xref\n0 {offsets.Count + 1}\n0000000000 65535 f \n");
        foreach (var offset in offsets) Write($"{offset:D10} 00000 n \n");
        Write($"trailer\n<< /Size {offsets.Count + 1} /Root 1 0 R /Info {infoNumber} 0 R >>\nstartxref\n{xref}\n%%EOF\n");
    }

    static async Task<byte[]> RenderPageAsync(PdfPage page, int width, int height, double quality, bool grayscale)
    {
        using var rendered = new InMemoryRandomAccessStream();
        await page.RenderToStreamAsync(rendered, new PdfPageRenderOptions
        {
            DestinationWidth = (uint)width,
            DestinationHeight = (uint)height,
            BackgroundColor = Windows.UI.Color.FromArgb(255, 255, 255, 255),
        });
        var decoder = await BitmapDecoder.CreateAsync(rendered);
        var pixels = (await decoder.GetPixelDataAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Ignore, new BitmapTransform(),
            ExifOrientationMode.IgnoreExifOrientation, ColorManagementMode.DoNotColorManage)).DetachPixelData();
        // WIC's WinRT surface won't take 8-bit grey input, so grey pages are stored as RGB with equal
        // channels; JPEG keeps almost no chroma for those, so the size cost is small.
        if (grayscale)
            for (int i = 0; i < pixels.Length; i += 4)
                pixels[i] = pixels[i + 1] = pixels[i + 2] = (byte)((pixels[i] * 29 + pixels[i + 1] * 150 + pixels[i + 2] * 77) >> 8);

        using var jpeg = new InMemoryRandomAccessStream();
        var options = new BitmapPropertySet { { "ImageQuality", new BitmapTypedValue((float)quality, Windows.Foundation.PropertyType.Single) } };
        var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.JpegEncoderId, jpeg, options);
        encoder.SetPixelData(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Ignore, decoder.PixelWidth, decoder.PixelHeight, 96, 96, pixels);
        await encoder.FlushAsync();

        var bytes = new byte[jpeg.Size];
        jpeg.Seek(0);
        await jpeg.ReadAsync(bytes.AsBuffer(), (uint)bytes.Length, InputStreamOptions.None);
        return bytes;
    }

    static void RefuseSameFile(string source, string destination)
    {
        if (string.Equals(Path.GetFullPath(source), Path.GetFullPath(destination), StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Refusing to overwrite the source file.");
    }
}
