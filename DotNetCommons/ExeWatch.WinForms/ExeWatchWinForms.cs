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

        // When the debugger is attached, do NOT override the exception mode.
        // WinForms defaults to ThrowException under debugger, which lets
        // Visual Studio break at the exact throw site — identical to running
        // without ExeWatch. The exception is still logged via
        // AppDomain.UnhandledException in ExeWatchClient.
        //
        // In production (no debugger), we catch ThreadException to log
        // the error and show the standard WinForms exception dialog.
        if (!System.Diagnostics.Debugger.IsAttached)
        {
            Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
            Application.ThreadException += OnThreadException;
        }
    }

    private static void OnThreadException(object sender, System.Threading.ThreadExceptionEventArgs e)
    {
        // Log to ExeWatch first
        if (ExeWatchSdk.IsInitialized)
        {
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

        // Show the standard WinForms exception dialog (same as without ExeWatch)
        using var dialog = new ThreadExceptionDialog(e.Exception);
        if (dialog.ShowDialog() == DialogResult.Abort)
            Application.Exit();
    }
}
