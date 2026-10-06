namespace SqueezeBar.Core;

/// <summary>Pause/cancel switch shared between the UI and a running encode. Safe to use from any thread.</summary>
public sealed class JobControl
{
    readonly object _gate = new();
    readonly CancellationTokenSource _cts = new();
    bool _paused;
    bool _cancelled;

    /// <summary>Cancelled together with the job; pass it to async platform APIs.</summary>
    public CancellationToken Token => _cts.Token;

    public bool IsPaused { get { lock (_gate) return _paused; } }
    public bool IsCancelled { get { lock (_gate) return _cancelled; } }

    public void Pause()
    {
        lock (_gate) { if (!_cancelled) _paused = true; }
    }

    public void Resume()
    {
        lock (_gate) { _paused = false; Monitor.PulseAll(_gate); }
    }

    public void Cancel()
    {
        lock (_gate) { _cancelled = true; _paused = false; Monitor.PulseAll(_gate); }
        _cts.Cancel();
    }

    /// <summary>
    /// Blocks the calling thread while paused. Returns false once the job has been cancelled, meaning the caller should stop.
    /// Only call this from encode threads, never from the UI thread.
    /// </summary>
    public bool Checkpoint()
    {
        lock (_gate)
        {
            while (_paused && !_cancelled) Monitor.Wait(_gate);
            return !_cancelled;
        }
    }
}
