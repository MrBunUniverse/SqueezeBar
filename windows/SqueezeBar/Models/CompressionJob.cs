using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;

namespace SqueezeBar.Models;

public class CompressionJob : INotifyPropertyChanged
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string FilePath { get; set; } = string.Empty;
    public MediaType MediaType { get; set; }
    
    private double _progress;
    public double Progress
    {
        get => _progress;
        set { _progress = value; OnPropertyChanged(); }
    }

    private string _statusText = "Queued";
    public string StatusText
    {
        get => _statusText;
        set { _statusText = value; OnPropertyChanged(); }
    }

    private bool _isCompleted;
    public bool IsCompleted
    {
        get => _isCompleted;
        set { _isCompleted = value; OnPropertyChanged(); }
    }

    public System.Threading.CancellationTokenSource Cts { get; } = new();

    public string FileName => Path.GetFileName(FilePath);

    public event PropertyChangedEventHandler? PropertyChanged;
    protected void OnPropertyChanged([CallerMemberName] string? name = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
}

public class CompressionResult
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string OriginalPath { get; set; } = string.Empty;
    public string OutputPath { get; set; } = string.Empty;
    public long OriginalSize { get; set; }
    public long CompressedSize { get; set; }
    public MediaType MediaType { get; set; }
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;

    public string FileName => !string.IsNullOrEmpty(OutputPath) ? Path.GetFileName(OutputPath) : Path.GetFileName(OriginalPath);
    public long BytesSaved => Math.Max(0, OriginalSize - CompressedSize);
    public double PercentSaved => OriginalSize > 0 ? ((OriginalSize - CompressedSize) / (double)OriginalSize) * 100.0 : 0.0;

    public string FormattedOriginalSize => FormatSize(OriginalSize);
    public string FormattedCompressedSize => FormatSize(CompressedSize);
    public string FormattedSavings => FormatSize(BytesSaved);

    private static string FormatSize(long bytes)
    {
        if (bytes < 1024) return $"{bytes} B";
        if (bytes < 1024 * 1024) return $"{bytes / 1024.0:F1} KB";
        if (bytes < 1024 * 1024 * 1024) return $"{bytes / (1024.0 * 1024):F1} MB";
        return $"{bytes / (1024.0 * 1024 * 1024):F2} GB";
    }
}
