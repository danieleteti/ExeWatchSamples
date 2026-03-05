namespace ExeWatch.WinForms;

/// <summary>
/// Hooks into WinForms Application.ThreadException to capture GUI exceptions.
/// Same pattern as Delphi ExeWatchSDKv1.VCL.pas.
///
/// Usage in Program.cs:
/// <code>
/// ExeWatchWinForms.Install();
/// Application.Run(new MainForm());
/// </code>
/// </summary>
public static class ExeWatchWinForms
{
    private static bool _installed;

    /// <summary>
    /// Install the WinForms exception hook. Must be called before Application.Run().
    /// </summary>
    public static void Install()
    {
        if (_installed) return;
        _installed = true;

        Application.ThreadException += OnThreadException;
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
    }

    private static void OnThreadException(object sender, System.Threading.ThreadExceptionEventArgs e)
    {
        if (!ExeWatchSdk.IsInitialized) return;

        try
        {
            var ex = e.Exception;
            var extraData = new Dictionary<string, object>
            {
                ["exception_class"] = ex.GetType().FullName ?? ex.GetType().Name,
                ["exception_source"] = "winforms_thread_exception"
            };

            var message = $"{ex.GetType().Name}: {ex.Message}";
            if (ex.StackTrace != null)
                message += $"\n{ex.StackTrace}";

            ExeWatchSdk.Log(LogLevel.Error, message, "exception", extraData);
        }
        catch
        {
            // Never let our hook crash the app
        }
    }
}
