using System.Collections.Concurrent;
using ExeWatch.Models;

namespace ExeWatch.Internal;

internal sealed class SamplerThread : IDisposable
{
    private readonly ConcurrentDictionary<string, GaugeRegistration> _gauges = new();
    private readonly Action<string, double, string> _recordGauge;
    private readonly InternalLogger _logger;
    private readonly Thread _thread;
    private readonly ManualResetEventSlim _stopEvent = new(false);
    private readonly int _intervalMs;

    public SamplerThread(int intervalSec, Action<string, double, string> recordGauge, InternalLogger logger)
    {
        _intervalMs = Math.Max(intervalSec, Constants.MinGaugeSamplingIntervalSec) * 1000;
        _recordGauge = recordGauge;
        _logger = logger;

        _thread = new Thread(Run)
        {
            IsBackground = true,
            Name = "ExeWatch-Sampler"
        };
        _thread.Start();
    }

    public bool Register(string name, Func<double> callback, string tag)
    {
        if (_gauges.Count >= Constants.MaxRegisteredGauges)
            return false;

        _gauges[name] = new GaugeRegistration { Name = name, Callback = callback, Tag = tag };
        return true;
    }

    public void Unregister(string name) => _gauges.TryRemove(name, out _);

    public int Count => _gauges.Count;

    private void Run()
    {
        while (!_stopEvent.Wait(_intervalMs))
        {
            foreach (var kvp in _gauges)
            {
                try
                {
                    var value = kvp.Value.Callback();
                    _recordGauge(kvp.Value.Name, value, kvp.Value.Tag);
                }
                catch (Exception ex)
                {
                    _logger.Log($"ERROR | Gauge callback '{kvp.Key}' failed: {ex.Message}");
                }
            }
        }
    }

    public void Dispose()
    {
        _stopEvent.Set();
        _thread.Join(TimeSpan.FromSeconds(3));
        _stopEvent.Dispose();
    }
}
