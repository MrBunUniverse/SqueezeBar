using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using SqueezeBar.Models;

namespace SqueezeBar.Services;

public class MediaCompressionEngine
{
    private static readonly Lazy<MediaCompressionEngine> _instance = new(() => new MediaCompressionEngine());
    public static MediaCompressionEngine Shared => _instance.Value;

    private static readonly HashSet<string> ImageExts = new(StringComparer.OrdinalIgnoreCase)
    {
        ".jpg", ".jpeg", ".png", ".webp", ".heic", ".bmp", ".avif", ".tiff", ".ico"
    };

    private static readonly HashSet<string> VideoExts = new(StringComparer.OrdinalIgnoreCase)
    {
        ".mp4", ".mov", ".m4v", ".mkv", ".webm", ".avi", ".gif", ".wmv", ".flv", ".ts"
    };

    private static readonly HashSet<string> AudioExts = new(StringComparer.OrdinalIgnoreCase)
    {
        ".mp3", ".wav", ".aac", ".m4a", ".flac", ".ogg", ".wma", ".aiff"
    };

    private static readonly HashSet<string> PdfExts = new(StringComparer.OrdinalIgnoreCase)
    {
        ".pdf"
    };

    public MediaType ClassifyFile(string path)
    {
        string ext = Path.GetExtension(path);
        if (ImageExts.Contains(ext)) return MediaType.Image;
        if (VideoExts.Contains(ext)) return MediaType.Video;
        if (AudioExts.Contains(ext)) return MediaType.Audio;
        if (PdfExts.Contains(ext)) return MediaType.Pdf;
        return MediaType.Unsupported;
    }

    public List<string> GatherMediaFiles(IEnumerable<string> paths)
    {
        var result = new List<string>();
        foreach (var path in paths)
        {
            if (Directory.Exists(path))
            {
                try
                {
                    var files = Directory.EnumerateFiles(path, "*.*", SearchOption.AllDirectories)
                        .Where(f => ClassifyFile(f) != MediaType.Unsupported);
                    result.AddRange(files);
                }
                catch { }
            }
            else if (File.Exists(path) && ClassifyFile(path) != MediaType.Unsupported)
            {
                result.Add(path);
            }
        }
        return result;
    }

    public async Task<CompressionResult?> CompressFileAsync(string path, CompressionConfiguration config, IProgress<double>? progress = null)
    {
        var type = ClassifyFile(path);
        return type switch
        {
            MediaType.Image => await ImageCompressor.CompressImageAsync(path, config, progress),
            MediaType.Video => await VideoAudioCompressor.CompressVideoAsync(path, config, progress),
            MediaType.Audio => await VideoAudioCompressor.CompressAudioAsync(path, config, progress),
            _ => null
        };
    }
}
