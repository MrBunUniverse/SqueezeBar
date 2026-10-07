using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Serialization;
using SqueezeBar.Core;
using SqueezeBar.Media;

namespace SqueezeBar;

enum UiScale { Small, Medium, Large }

/// <summary>App behaviour and appearance (not compression settings). Saved as prefs.json.</summary>
sealed record AppPreferences
{
    public string Accent { get; init; } = "Blue";
    public string CustomAccentHex { get; init; } = "1A80FF";
    public UiScale Scale { get; init; } = UiScale.Medium;
    public bool WatchFolderEnabled { get; init; }
    public string? WatchFolder { get; init; }
    public bool SoundEnabled { get; init; } = true;
    public string SoundTheme { get; init; } = "Crystal";
    public long TotalBytesSaved { get; init; }

    [JsonIgnore]
    public double ScaleFactor => Scale switch { UiScale.Small => 0.85, UiScale.Large => 1.18, _ => 1.0 };
}

/// <summary>Settings, history and the engine. Settings are the <see cref="CompressionConfiguration"/> record itself, saved as JSON.</summary>
sealed class AppState
{
    const int HistoryLimit = 50;
    static readonly string Folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SqueezeBar");
    static readonly JsonSerializerOptions Json = new() { WriteIndented = true, Converters = { new JsonStringEnumConverter() } };

    // Must stay below Folder and Json: static fields initialise top to bottom, and the constructor reads both.
    public static AppState Shared { get; } = new();

    public CompressionConfiguration Config { get; private set; }
    public AppPreferences Prefs { get; private set; }
    public List<CompressionResult> History { get; }
    public MediaCompressionEngine Engine { get; } = new(Compressors.All);

    AppState()
    {
        Config = Load<CompressionConfiguration>("settings.json") ?? new();
        Prefs = Load<AppPreferences>("prefs.json") ?? new();
        History = Load<List<CompressionResult>>("history.json") ?? [];
        Engine.CanEncodeImage = Compressors.CanEncodeImage;
        if (SHGetKnownFolderPath(new Guid("374DE290-123F-4565-9164-39C4925E467B"), 0, IntPtr.Zero, out var downloads) == 0)
            Engine.FallbackFolder = downloads;
    }

    public void Update(Func<CompressionConfiguration, CompressionConfiguration> change)
    {
        Config = change(Config);
        Save("settings.json", Config);
    }

    public void UpdatePrefs(Func<AppPreferences, AppPreferences> change)
    {
        Prefs = change(Prefs);
        Save("prefs.json", Prefs);
    }

    public void AddResult(CompressionResult result)
    {
        UpdatePrefs(p => p with { TotalBytesSaved = p.TotalBytesSaved + result.BytesSaved });
        History.Insert(0, result);
        if (History.Count > HistoryLimit) History.RemoveRange(HistoryLimit, History.Count - HistoryLimit);
        Save("history.json", History);
    }

    public void RemoveResult(CompressionResult result)
    {
        History.Remove(result);
        Save("history.json", History);
    }

    public void ClearHistory()
    {
        History.Clear();
        Save("history.json", History);
    }

    static T? Load<T>(string name) where T : class
    {
        try { return JsonSerializer.Deserialize<T>(File.ReadAllText(Path.Combine(Folder, name)), Json); }
        catch { return null; } // missing or unreadable: start from defaults
    }

    static void Save<T>(string name, T value)
    {
        try
        {
            Directory.CreateDirectory(Folder);
            File.WriteAllText(Path.Combine(Folder, name), JsonSerializer.Serialize(value, Json));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { } // settings stay in memory for this run
    }

    [DllImport("shell32", CharSet = CharSet.Unicode)]
    static extern int SHGetKnownFolderPath([MarshalAs(UnmanagedType.LPStruct)] Guid id, uint flags, IntPtr token, out string path);
}
