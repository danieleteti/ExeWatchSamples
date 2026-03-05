using ExeWatch.WinForms;

namespace ExeWatchWindowsForms;

internal static class Program
{
    [STAThread]
    static void Main()
    {
        // Install WinForms exception hook (must be before Application.Run)
        ExeWatchWinForms.Install();

        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm());
    }
}
