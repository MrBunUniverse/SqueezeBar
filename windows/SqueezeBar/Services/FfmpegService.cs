using System;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Threading.Tasks;

namespace SqueezeBar.Services;

public class FfmpegService
{
    private static readonly Lazy<FfmpegService> _instance = new(() => new FfmpegService());
    public static FfmpegService Shared => _instance.Value;

    private static readonly string AppDataFfmpeg = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "SqueezeBar",
        "ffmpeg.exe");

    public bool IsFfmpegAvailable => !string.IsNullOrEmpty(GetFfmpegPath());

    public string? GetFfmpegPath()
    {
        try
        {
            // 1. AppData SqueezeBar folder
            if (File.Exists(AppDataFfmpeg)) return AppDataFfmpeg;

            // 2. Next to running executable
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string localExe = Path.Combine(baseDir, "ffmpeg.exe");
            if (File.Exists(localExe)) return localExe;

            string localExeNoExt = Path.Combine(baseDir, "ffmpeg");
            if (File.Exists(localExeNoExt)) return localExeNoExt;

            // 3. Current Directory
            string cwdExe = Path.Combine(Environment.CurrentDirectory, "ffmpeg.exe");
            if (File.Exists(cwdExe)) return cwdExe;

            // 4. CrossOver / Wine Host macOS paths
            string[] crossOverPaths = new[]
            {
                @"Z:\opt\homebrew\bin\ffmpeg",
                @"Z:\usr\local\bin\ffmpeg",
                @"Z:\usr\bin\ffmpeg",
                "/opt/homebrew/bin/ffmpeg",
                "/usr/local/bin/ffmpeg",
                "/usr/bin/ffmpeg"
            };
            foreach (var cp in crossOverPaths)
            {
                if (File.Exists(cp)) return cp;
            }

            // 5. Common Package Manager / System Paths
            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string[] commonPaths = new[]
            {
                Path.Combine(localAppData, "Microsoft", "WinGet", "Links", "ffmpeg.exe"),
                @"C:\ProgramData\chocolatey\bin\ffmpeg.exe",
                @"C:\ffmpeg\bin\ffmpeg.exe",
                @"C:\tools\ffmpeg\bin\ffmpeg.exe"
            };
            foreach (var cp in commonPaths)
            {
                if (File.Exists(cp)) return cp;
            }

            // 6. Check if 'ffmpeg' works in PATH
            using var proc = Process.Start(new ProcessStartInfo
            {
                FileName = "ffmpeg",
                Arguments = "-version",
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            });
            if (proc != null)
            {
                proc.WaitForExit(1000);
                if (proc.ExitCode == 0) return "ffmpeg";
            }
        }
        catch { }

        return null;
    }

    public async Task<bool> DownloadFfmpegAsync(IProgress<double>? progress = null)
    {
        try
        {
            string dir = Path.GetDirectoryName(AppDataFfmpeg)!;
            Directory.CreateDirectory(dir);

            string tempFile = AppDataFfmpeg + ".tmp";
            string downloadUrl = "https://github.com/eugeneware/ffmpeg-static/releases/download/b4.4/win32-x64";

            using var client = new HttpClient();
            client.Timeout = TimeSpan.FromMinutes(5);

            using var response = await client.GetAsync(downloadUrl, HttpCompletionOption.ResponseHeadersRead);
            response.EnsureSuccessStatusCode();

            var totalBytes = response.Content.Headers.ContentLength ?? 32 * 1024 * 1024;
            using var contentStream = await response.Content.ReadAsStreamAsync();
            using var fileStream = new FileStream(tempFile, FileMode.Create, FileAccess.Write, FileShare.None, 8192, true);

            var buffer = new byte[8192];
            long totalRead = 0;
            int bytesRead;

            while ((bytesRead = await contentStream.ReadAsync(buffer, 0, buffer.Length)) > 0)
            {
                await fileStream.WriteAsync(buffer, 0, bytesRead);
                totalRead += bytesRead;
                progress?.Report((double)totalRead / totalBytes);
            }

            fileStream.Close();

            if (File.Exists(AppDataFfmpeg)) File.Delete(AppDataFfmpeg);
            File.Move(tempFile, AppDataFfmpeg);

            return true;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[FfmpegService] Failed to download FFmpeg: {ex.Message}");
            return false;
        }
    }
}
