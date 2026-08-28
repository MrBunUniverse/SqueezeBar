using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using CliWrap;
using SqueezeBar.Models;

namespace SqueezeBar.Services;

public static class PdfCompressor
{
    public static string? GetGhostscriptPath()
    {
        try
        {
            // 1. CrossOver / Wine host paths
            string[] macPaths = new[]
            {
                @"Z:\opt\homebrew\bin\gs",
                @"Z:\usr\local\bin\gs",
                @"Z:\usr\bin\gs",
                "/opt/homebrew/bin/gs",
                "/usr/local/bin/gs",
                "/usr/bin/gs"
            };
            foreach (var p in macPaths)
            {
                if (File.Exists(p)) return p;
            }

            // 2. Windows paths
            string[] winPaths = new[]
            {
                @"C:\Program Files\gs\gs10.03.0\bin\gswin64c.exe",
                @"C:\Program Files\gs\gs10.02.1\bin\gswin64c.exe",
                @"C:\Program Files\gs\gs10.00.0\bin\gswin64c.exe",
                @"C:\Program Files\gs\gs9.56.1\bin\gswin64c.exe",
                @"C:\Program Files (x86)\gs\gs10.03.0\bin\gswin32c.exe",
                @"C:\ProgramData\chocolatey\bin\gswin64c.exe"
            };
            foreach (var p in winPaths)
            {
                if (File.Exists(p)) return p;
            }

            // 3. Check PATH
            using var proc = Process.Start(new ProcessStartInfo
            {
                FileName = "gswin64c",
                Arguments = "-version",
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            });
            if (proc != null)
            {
                proc.WaitForExit(800);
                if (proc.ExitCode == 0) return "gswin64c";
            }

            using var procGs = Process.Start(new ProcessStartInfo
            {
                FileName = "gs",
                Arguments = "-version",
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            });
            if (procGs != null)
            {
                procGs.WaitForExit(800);
                if (procGs.ExitCode == 0) return "gs";
            }
        }
        catch { }

        return null;
    }

    public static async Task<CompressionResult?> CompressPdfAsync(
        string inputPath,
        CompressionConfiguration config,
        IProgress<double>? progress = null,
        CancellationToken cancellationToken = default)
    {
        try
        {
            if (!File.Exists(inputPath)) return null;

            progress?.Report(0.1);
            var fileInfo = new FileInfo(inputPath);
            long originalSize = fileInfo.Length;

            string dir = Path.GetDirectoryName(inputPath) ?? "";
            string nameWithoutExt = Path.GetFileNameWithoutExtension(inputPath);
            string outputPath = Path.Combine(dir, $"{nameWithoutExt}{config.OutputSuffix}.pdf");

            int counter = 1;
            while (File.Exists(outputPath))
            {
                outputPath = Path.Combine(dir, $"{nameWithoutExt}{config.OutputSuffix}_{counter}.pdf");
                counter++;
            }

            string? gs = GetGhostscriptPath();
            if (!string.IsNullOrEmpty(gs))
            {
                string pdfSettings = config.PdfDPI switch
                {
                    <= 72 => "/screen",
                    <= 150 => "/ebook",
                    <= 200 => "/printer",
                    _ => "/prepress"
                };

                var args = $"-sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS={pdfSettings} -dNOPAUSE -dQUIET -dBATCH {(config.PdfGrayscale ? "-sColorConversionStrategy=Gray -dProcessColorModel=/DeviceGray " : "")}-sOutputFile=\"{outputPath}\" \"{inputPath}\"";

                progress?.Report(0.35);

                await Cli.Wrap(gs)
                    .WithArguments(args)
                    .WithValidation(CommandResultValidation.None)
                    .ExecuteAsync(cancellationToken);

                progress?.Report(1.0);
            }
            else
            {
                // Fallback: Copy and report
                progress?.Report(0.5);
                File.Copy(inputPath, outputPath, true);
                progress?.Report(1.0);
            }

            if (File.Exists(outputPath))
            {
                var outFile = new FileInfo(outputPath);
                if (outFile.Length > 0)
                {
                    return new CompressionResult
                    {
                        OriginalPath = inputPath,
                        OutputPath = outputPath,
                        OriginalSize = originalSize,
                        CompressedSize = outFile.Length,
                        MediaType = MediaType.Pdf
                    };
                }
            }

            return null;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[PdfCompressor] Error: {ex.Message}");
            return null;
        }
    }
}
