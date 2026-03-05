namespace ExeWatch.Models;

internal sealed class MetricAccumulator
{
    public string Name { get; set; } = "";
    public string MetricType { get; set; } = "counter"; // "counter" or "gauge"
    public string Tag { get; set; } = "";
    public double Value { get; set; }
    public double MinValue { get; set; } = double.MaxValue;
    public double MaxValue { get; set; } = double.MinValue;
    public double SumValue { get; set; }
    public int SampleCount { get; set; }
    public DateTime PeriodStart { get; set; } = DateTime.UtcNow;

    public void AddCounter(double value)
    {
        Value += value;
        SampleCount++;
    }

    public void AddGauge(double value)
    {
        Value = value; // last value
        if (value < MinValue) MinValue = value;
        if (value > MaxValue) MaxValue = value;
        SumValue += value;
        SampleCount++;
    }

    public double Avg => SampleCount > 0 ? SumValue / SampleCount : 0;
}
