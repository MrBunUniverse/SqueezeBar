namespace SqueezeBar.Core;

/// <summary>Auto-squeeze watch folder: new media files that appear in the folder are compressed once fully written.</summary>
public sealed class FolderWatch : IDisposable
{
    FileSystemWatcher? _watcher;

    public void Start(string folder, Func<string> suffix, Action<string> onNewFile)
    {
        Stop();
        if (!Directory.Exists(folder)) return;
        _watcher = new FileSystemWatcher(folder) { NotifyFilter = NotifyFilters.FileName, EnableRaisingEvents = true };
        void Handle(string path) => _ = Task.Run(async () =>
        {
            var name = Path.GetFileName(path);
            // Our own outputs land here too; skipping the suffix stops an endless loop.
            if (name.StartsWith('.') || name.Contains(suffix(), StringComparison.OrdinalIgnoreCase)) return;
            if (MediaTypes.Classify(path) == MediaType.Unsupported) return;
            if (await WaitUntilStableAsync(path)) onNewFile(path);
        });
        _watcher.Created += (_, e) => Handle(e.FullPath);
        _watcher.Renamed += (_, e) => Handle(e.FullPath); // browsers download to a temp name, then rename
    }

    public void Stop()
    {
        _watcher?.Dispose();
        _watcher = null;
    }

    public void Dispose() => Stop();

    /// <summary>Waits until the size stops changing and the file can be opened (copy finished). Gives up after about two minutes.</summary>
    static async Task<bool> WaitUntilStableAsync(string path)
    {
        long last = -1;
        for (int i = 0; i < 120; i++)
        {
            await Task.Delay(1000);
            try
            {
                long size = new FileInfo(path).Length;
                if (size == last && size > 0)
                {
                    using var probe = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
                    return true;
                }
                last = size;
            }
            catch (FileNotFoundException) { return false; }
            catch (IOException) { } // still locked by the writer
        }
        return false;
    }
}
