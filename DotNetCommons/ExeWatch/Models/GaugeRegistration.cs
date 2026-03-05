namespace ExeWatch.Models;

internal sealed class GaugeRegistration
{
    public string Name { get; set; } = "";
    public Func<double> Callback { get; set; } = () => 0;
    public string Tag { get; set; } = "";
}
