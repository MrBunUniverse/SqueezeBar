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
            if (File.Exists(AppDataFfmpeg) && new FileInfo(AppDataFfmpeg).Length > 1024 * 1024)
                return AppDataFfmpeg;

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
        string[] downloadMirrors = new[]
        {
            "https://github.com/MrBunUniverse/SquezeBar/releases/download/v0.98/ffmpeg.exe",
            "https://github.com/eugeneware/ffmpeg-static/releases/download/b4.4/win32-x64"
        };

        foreach (var url in downloadMirrors)
        {
            try
            {
                string dir = Path.GetDirectoryName(AppDataFfmpeg)!;
                Directory.CreateDirectory(dir);

                string tempFile = AppDataFfmpeg + ".tmp";
                if (File.Exists(tempFile)) File.Delete(tempFile);

                using var client = new HttpClient();
                client.Timeout = TimeSpan.FromMinutes(5);

                using var response = await client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead);
                if (!response.IsSuccessStatusCode) continue;

                var totalBytes = response.Content.Headers.ContentLength ?? 75 * 1024 * 1024;
                using var contentStream = await response.Content.ReadAsStreamAsync();
                using var fileStream = new FileStream(tempFile, FileMode.Create, FileAccess.Write, FileShare.None, 16384, true);

                var buffer = new byte[16384];
                long totalRead = 0;
                int bytesRead;

                while ((bytesRead = await contentStream.ReadAsync(buffer, 0, buffer.Length)) > 0)
                {
                    await fileStream.WriteAsync(buffer, 0, bytesRead);
                    totalRead += bytesRead;
                    progress?.Report(Math.Min(1.0, (double)totalRead / totalBytes));
                }

                fileStream.Close();

                if (File.Exists(tempFile) && new FileInfo(tempFile).Length > 1024 * 1024)
                {
                    if (File.Exists(AppDataFfmpeg)) File.Delete(AppDataFfmpeg);
                    File.Move(tempFile, AppDataFfmpeg);
                    return true;
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"[FfmpegService] Mirror failed ({url}): {ex.Message}");
            }
        }

        return false;
    }
}
