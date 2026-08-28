using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using SqueezeBar.Services;

namespace SqueezeBar.Models;

public enum PopoverTab
{
    Activity,
    Settings
}

public enum MediaCategory
{
    Images,
    Video,
    Audio,
    Pdf
}

public class AppState : INotifyPropertyChanged
{
    private static readonly Lazy<AppState> _instance = new(() => new AppState());
    public static AppState Shared => _instance.Value;

    // Navigation & View States
    private PopoverTab _selectedTab = PopoverTab.Activity;
    public PopoverTab SelectedTab
    {
        get => _selectedTab;
        set { _selectedTab = value; OnPropertyChanged(); OnPropertyChanged(nameof(IsActivityTab)); OnPropertyChanged(nameof(IsSettingsTab)); }
    }

    public bool IsActivityTab => SelectedTab == PopoverTab.Activity;
    public bool IsSettingsTab => SelectedTab == PopoverTab.Settings;

    private MediaCategory _activeFormatCategory = MediaCategory.Images;
    public MediaCategory ActiveFormatCategory
    {
        get => _activeFormatCategory;
        set { _activeFormatCategory = value; OnPropertyChanged(); UpdateFormatCategoryFlags(); }
    }

    private bool _isFormatDrawerExpanded = true;
    public bool IsFormatDrawerExpanded
    {
        get => _isFormatDrawerExpanded;
        set { _isFormatDrawerExpanded = value; OnPropertyChanged(); }
    }

    // Format flags for UI binding
    public bool IsImagesActive => ActiveFormatCategory == MediaCategory.Images && IsFormatDrawerExpanded;
    public bool IsVideoActive => ActiveFormatCategory == MediaCategory.Video && IsFormatDrawerExpanded;
    public bool IsAudioActive => ActiveFormatCategory == MediaCategory.Audio && IsFormatDrawerExpanded;
    public bool IsPdfActive => ActiveFormatCategory == MediaCategory.Pdf && IsFormatDrawerExpanded;

    private void UpdateFormatCategoryFlags()
    {
        OnPropertyChanged(nameof(IsImagesActive));
        OnPropertyChanged(nameof(IsVideoActive));
        OnPropertyChanged(nameof(IsAudioActive));
        OnPropertyChanged(nameof(IsPdfActive));
        OnPropertyChanged(nameof(ActiveCategoryTitle));
    }

    public string ActiveCategoryTitle => ActiveFormatCategory switch
    {
        MediaCategory.Images => "Image Compression Settings",
        MediaCategory.Video => "Video Encoding Settings",
        MediaCategory.Audio => "Audio Compression Settings",
        MediaCategory.Pdf => "PDF Optimization Settings",
        _ => "Compression Settings"
    };

    // Global Preset & Limits
    private TargetSizeMode _targetSizeMode = TargetSizeMode.Discord25;
    public TargetSizeMode TargetSizeMode
    {
        get => _targetSizeMode;
        set { _targetSizeMode = value; OnPropertyChanged(); OnPropertyChanged(nameof(TargetLimitLabel)); }
    }

    private double _customTargetSizeMB = 25.0;
    public double CustomTargetSizeMB
    {
        get => _customTargetSizeMB;
        set { _customTargetSizeMB = value; OnPropertyChanged(); }
    }

    private bool _preserveResolutionInTargetMode = true;
    public bool PreserveResolutionInTargetMode
    {
        get => _preserveResolutionInTargetMode;
        set { _preserveResolutionInTargetMode = value; OnPropertyChanged(); }
    }

    private bool _preserveAudioQualityInTargetMode = false;
    public bool PreserveAudioQualityInTargetMode
    {
        get => _preserveAudioQualityInTargetMode;
        set { _preserveAudioQualityInTargetMode = value; OnPropertyChanged(); }
    }

    public string TargetLimitLabel => TargetSizeMode switch
    {
        TargetSizeMode.Off => "Manual",
        TargetSizeMode.Discord25 => "≤ 25 MB",
        TargetSizeMode.Email10 => "≤ 10 MB",
        TargetSizeMode.Discord50 => "≤ 50 MB",
        TargetSizeMode.Custom => $"≤ {CustomTargetSizeMB:F0} MB",
        _ => "Manual"
    };

    // Images Settings
    private double _imageQuality = 0.80;
    public double ImageQuality
    {
        get => _imageQuality;
        set { _imageQuality = value; OnPropertyChanged(); OnPropertyChanged(nameof(ImageQualityPercent)); OnPropertyChanged(nameof(ImageSummaryText)); }
    }
    public int ImageQualityPercent => (int)(ImageQuality * 100);

    private double _imageResolutionScale = 1.0;
    public double ImageResolutionScale
    {
        get => _imageResolutionScale;
        set { _imageResolutionScale = value; OnPropertyChanged(); OnPropertyChanged(nameof(ImageSummaryText)); }
    }

    private ImageFormatPolicy _imageFormatPolicy = ImageFormatPolicy.ModernWebP;
    public ImageFormatPolicy ImageFormatPolicy
    {
        get => _imageFormatPolicy;
        set { _imageFormatPolicy = value; OnPropertyChanged(); OnPropertyChanged(nameof(ImageSummaryText)); }
    }

    public string ImageSummaryText => $"{ImageFormatPolicy} • {ImageQualityPercent}% Q • {(int)(ImageResolutionScale * 100)}% Scale";

    // Video Settings
    private double _videoQuality = 0.70;
    public double VideoQuality
    {
        get => _videoQuality;
        set { _videoQuality = value; OnPropertyChanged(); OnPropertyChanged(nameof(VideoQualityPercent)); OnPropertyChanged(nameof(VideoSummaryText)); }
    }
    public int VideoQualityPercent => (int)(VideoQuality * 100);

    private double _videoResolutionScale = 1.0;
    public double VideoResolutionScale
    {
        get => _videoResolutionScale;
        set { _videoResolutionScale = value; OnPropertyChanged(); OnPropertyChanged(nameof(VideoSummaryText)); }
    }

    private VideoCodecPreference _videoCodec = VideoCodecPreference.HEVC;
    public VideoCodecPreference VideoCodec
    {
        get => _videoCodec;
        set { _videoCodec = value; OnPropertyChanged(); OnPropertyChanged(nameof(VideoSummaryText)); }
    }

    private int _videoFramerate = 0; // 0 = Original
    public int VideoFramerate
    {
        get => _videoFramerate;
        set { _videoFramerate = value; OnPropertyChanged(); OnPropertyChanged(nameof(VideoSummaryText)); }
    }

    private bool _videoRemoveAudio = false;
    public bool VideoRemoveAudio
    {
        get => _videoRemoveAudio;
        set { _videoRemoveAudio = value; OnPropertyChanged(); }
    }

    public string VideoSummaryText => $"{VideoCodec}{(VideoFramerate > 0 ? $" • {VideoFramerate} FPS" : "")} • {VideoQualityPercent}% Q • {(int)(VideoResolutionScale * 100)}% Scale";

    // Audio Settings
    private AudioBitratePreference _audioBitrate = AudioBitratePreference.K192;
    public AudioBitratePreference AudioBitrate
    {
        get => _audioBitrate;
        set { _audioBitrate = value; OnPropertyChanged(); OnPropertyChanged(nameof(AudioSummaryText)); }
    }

    public string AudioSummaryText => $"{AudioBitrate.ToString().TrimStart('K')} kbps AAC • Stereo";

    // PDF Settings
    private int _pdfDpi = 150;
    public int PdfDpi
    {
        get => _pdfDpi;
        set { _pdfDpi = value; OnPropertyChanged(); OnPropertyChanged(nameof(PdfSummaryText)); }
    }

    private bool _pdfGrayscale = false;
    public bool PdfGrayscale
    {
        get => _pdfGrayscale;
        set { _pdfGrayscale = value; OnPropertyChanged(); OnPropertyChanged(nameof(PdfSummaryText)); }
    }

    public string PdfSummaryText => $"{PdfDpi} DPI{(PdfGrayscale ? " • Grayscale" : " • Color")}";

    // General App & Theme Settings
    private string _accentColorHex = "#00D2FF";
    public string AccentColorHex
    {
        get => _accentColorHex;
        set { _accentColorHex = value; OnPropertyChanged(); }
    }

    private BackgroundDarkness _backgroundDarkness = BackgroundDarkness.DarkGrey;
    public BackgroundDarkness BackgroundDarkness
    {
        get => _backgroundDarkness;
        set { _backgroundDarkness = value; OnPropertyChanged(); }
    }

    private string _outputSuffix = "_squeezed";
    public string OutputSuffix
    {
        get => _outputSuffix;
        set { _outputSuffix = value; OnPropertyChanged(); }
    }

    private bool _stripMetadata = true;
    public bool StripMetadata
    {
        get => _stripMetadata;
        set { _stripMetadata = value; OnPropertyChanged(); }
    }

    private bool _replaceOriginal = false;
    public bool ReplaceOriginal
    {
        get => _replaceOriginal;
        set { _replaceOriginal = value; OnPropertyChanged(); }
    }

    // Collections
    public ObservableCollection<StagedQueueItem> StagedQueue { get; } = new();
    public ObservableCollection<CompressionJob> ActiveJobs { get; } = new();
    public ObservableCollection<CompressionResult> History { get; } = new();
    public ObservableCollection<string> WatchedFolders { get; } = new();

    // Stats
    private long _totalBytesSaved = 0;
    public long TotalBytesSaved
    {
        get => _totalBytesSaved;
        set { _totalBytesSaved = value; OnPropertyChanged(); OnPropertyChanged(nameof(FormattedTotalSaved)); }
    }

    private int _totalFilesSqueezed = 0;
    public int TotalFilesSqueezed
    {
        get => _totalFilesSqueezed;
        set { _totalFilesSqueezed = value; OnPropertyChanged(); }
    }

    private bool _isProcessing = false;
    public bool IsProcessing
    {
        get => _isProcessing;
        set { _isProcessing = value; OnPropertyChanged(); }
    }

    public string FormattedTotalSaved
    {
        get
        {
            if (TotalBytesSaved < 1024) return $"{TotalBytesSaved} B";
            if (TotalBytesSaved < 1024 * 1024) return $"{TotalBytesSaved / 1024.0:F1} KB";
            if (TotalBytesSaved < 1024 * 1024 * 1024) return $"{TotalBytesSaved / (1024.0 * 1024):F1} MB";
            return $"{TotalBytesSaved / (1024.0 * 1024 * 1024):F2} GB";
        }
    }

    public string StagedQueueCountText => $"Staged Queue ({StagedQueue.Count})";

    public CompressionConfiguration BuildCurrentConfiguration()
    {
        return new CompressionConfiguration
        {
            ImageQuality = ImageQuality,
            ImageResolutionScale = ImageResolutionScale,
            ImageFormatPolicy = ImageFormatPolicy,
            VideoQuality = VideoQuality,
            VideoResolutionScale = VideoResolutionScale,
            VideoCodec = VideoCodec,
            VideoRemoveAudio = VideoRemoveAudio,
            AudioBitrate = AudioBitrate,
            PdfDPI = PdfDpi,
            PdfGrayscale = PdfGrayscale,
            TargetSizeMode = TargetSizeMode,
            StripMetadata = StripMetadata,
            OutputSuffix = OutputSuffix,
            ReplaceOriginal = ReplaceOriginal
        };
    }

    public void AddFilesToStagedQueue(IEnumerable<string> paths)
    {
        var baseConfig = BuildCurrentConfiguration();
        var resolved = MediaCompressionEngine.Shared.GatherMediaFiles(paths);
        foreach (var path in resolved)
        {
            var type = MediaCompressionEngine.Shared.ClassifyFile(path);
            if (type == MediaType.Unsupported) continue;

            long size = new FileInfo(path).Length;
            var item = new StagedQueueItem(path, size, type, baseConfig);
            StagedQueue.Add(item);
        }
        OnPropertyChanged(nameof(StagedQueueCountText));
    }

    public void RemoveFromStagedQueue(Guid id)
    {
        var item = StagedQueue.FirstOrDefault(x => x.Id == id);
        if (item != null)
        {
            StagedQueue.Remove(item);
            OnPropertyChanged(nameof(StagedQueueCountText));
        }
    }

    public void ClearStagedQueue()
    {
        StagedQueue.Clear();
        OnPropertyChanged(nameof(StagedQueueCountText));
    }

    public async Task ProcessStagedQueueAsync()
    {
        if (StagedQueue.Count == 0 || IsProcessing) return;

        IsProcessing = true;
        var itemsToProcess = StagedQueue.ToList();
        StagedQueue.Clear();
        OnPropertyChanged(nameof(StagedQueueCountText));

        var baseConfig = BuildCurrentConfiguration();

        foreach (var item in itemsToProcess)
        {
            var job = new CompressionJob
            {
                FilePath = item.FilePath,
                MediaType = item.MediaType,
                StatusText = "Optimizing..."
            };
            ActiveJobs.Insert(0, job);

            var itemConfig = item.BuildConfiguration(baseConfig);
            var progress = new Progress<double>(p => job.Progress = p);

            var result = await Task.Run(() => MediaCompressionEngine.Shared.CompressFileAsync(item.FilePath, itemConfig, progress, job.Cts.Token));

            job.IsCompleted = true;
            if (job.StatusText == "Cancelled")
            {
                // Kept as Cancelled
            }
            else if (result != null)
            {
                job.StatusText = "Complete";
                History.Insert(0, result);
                TotalBytesSaved += result.BytesSaved;
                TotalFilesSqueezed++;
            }
            else
            {
                job.StatusText = "Failed";
            }
        }

        IsProcessing = false;
    }

    public async Task ProcessDroppedFilesImmediatelyAsync(IEnumerable<string> paths)
    {
        var resolved = MediaCompressionEngine.Shared.GatherMediaFiles(paths);
        if (resolved.Count == 0) return;

        IsProcessing = true;
        var config = BuildCurrentConfiguration();

        foreach (var path in resolved)
        {
            var type = MediaCompressionEngine.Shared.ClassifyFile(path);
            var job = new CompressionJob
            {
                FilePath = path,
                MediaType = type,
                StatusText = "Optimizing..."
            };
            ActiveJobs.Insert(0, job);

            var progress = new Progress<double>(p => job.Progress = p);
            var result = await Task.Run(() => MediaCompressionEngine.Shared.CompressFileAsync(path, config, progress, job.Cts.Token));

            job.IsCompleted = true;
            if (job.StatusText == "Cancelled")
            {
                // Kept as Cancelled
            }
            else if (result != null)
            {
                job.StatusText = "Complete";
                History.Insert(0, result);
                TotalBytesSaved += result.BytesSaved;
                TotalFilesSqueezed++;
            }
            else
            {
                job.StatusText = "Failed";
            }
        }

        IsProcessing = false;
    }

    public void ClearCompletedJobs()
    {
        var completed = ActiveJobs.Where(x => x.IsCompleted).ToList();
        foreach (var c in completed) ActiveJobs.Remove(c);
        OnPropertyChanged(nameof(IsProcessing));
    }

    public void CancelJob(Guid jobId)
    {
        var job = ActiveJobs.FirstOrDefault(x => x.Id == jobId);
        if (job != null)
        {
            try { job.Cts.Cancel(); } catch { }
            job.IsCompleted = true;
            job.StatusText = "Cancelled";
        }
    }

    public void CancelAllJobs()
    {
        foreach (var job in ActiveJobs.Where(x => !x.IsCompleted))
        {
            try { job.Cts.Cancel(); } catch { }
            job.IsCompleted = true;
            job.StatusText = "Cancelled";
        }
        IsProcessing = false;
    }

    public void ResetStats()
    {
        TotalBytesSaved = 0;
        TotalFilesSqueezed = 0;
        History.Clear();
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    protected void OnPropertyChanged([CallerMemberName] string? name = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
}
