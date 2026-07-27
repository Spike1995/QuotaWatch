using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

internal static class QuotaWatchLauncher
{
#if QUOTA_WATCH_LAUNCHER_TEST
    private const string InstanceMutexName =
        @"Local\QuotaWatchDesktopLauncherTest";
#else
    private const string InstanceMutexName =
        @"Local\QuotaWatchDesktopLauncher";
#endif

    private const uint TrayCallbackMessage = 0x0400 + 1;
    private const uint LeftButtonUpMessage = 0x0202;
    private const string FlutterWindowClass =
        "FLUTTER_RUNNER_WIN32_WINDOW";

    private delegate bool EnumWindowsCallback(
        IntPtr window,
        IntPtr parameter
    );

    [DllImport("user32.dll")]
    private static extern IntPtr GetDesktopWindow();

    [DllImport("user32.dll")]
    private static extern bool EnumChildWindows(
        IntPtr parent,
        EnumWindowsCallback callback,
        IntPtr parameter
    );

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(
        IntPtr window,
        out uint processId
    );

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(
        IntPtr window,
        StringBuilder className,
        int maximumCount
    );

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PostMessage(
        IntPtr window,
        uint message,
        IntPtr wParam,
        IntPtr lParam
    );

    [STAThread]
    private static int Main(string[] args)
    {
        bool ownsInstance;
        using (var mutex = new Mutex(
            true,
            InstanceMutexName,
            out ownsInstance
        ))
        {
            if (!ownsInstance)
            {
                for (int attempt = 0; attempt < 20; attempt++)
                {
                    if (ActivateExistingQuotaWatch())
                    {
                        return 0;
                    }
                    try
                    {
                        if (mutex.WaitOne(250))
                        {
                            ownsInstance = true;
                            break;
                        }
                    }
                    catch (AbandonedMutexException)
                    {
                        ownsInstance = true;
                        break;
                    }
                }
                if (!ownsInstance)
                {
                    ShowError(
                        "Quota Watch is still starting.\n\n" +
                        "Please wait a few seconds and try again."
                    );
                    return 1;
                }
            }

            // A previous launcher may have released the mutex just after its
            // Flutter window appeared. Recheck before creating another process.
            if (ActivateExistingQuotaWatch())
            {
                return 0;
            }
            return Run(args);
        }
    }

    private static int Run(string[] args)
    {
        string repoRoot = FindRepoRoot(AppDomain.CurrentDomain.BaseDirectory);
        if (repoRoot == null)
        {
            repoRoot = FindRepoRoot(Directory.GetCurrentDirectory());
        }
        if (repoRoot == null)
        {
            ShowError(
                "Could not find the Quota Watch Windows release.\n\n" +
                "Keep this launcher beside the quota_watch release folder."
            );
            return 1;
        }

        string explicitDesktop;
        if (!TryReadDesktopOverride(args, out explicitDesktop))
        {
            ShowError("The desktop launcher arguments are invalid.");
            return 1;
        }
        string desktopExecutable = explicitDesktop ??
            FindDesktopExecutable(repoRoot);
        if (
            String.IsNullOrWhiteSpace(desktopExecutable) ||
            !File.Exists(desktopExecutable)
        )
        {
            ShowError(
                "The Windows release executable was not found.\n\n" +
                "Run: flutter build windows --release"
            );
            return 1;
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = desktopExecutable,
            WorkingDirectory = Path.GetDirectoryName(desktopExecutable),
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden,
        };
        ClearProviderEnvironment(startInfo);

        try
        {
            using (Process desktop = Process.Start(startInfo))
            {
                if (desktop == null)
                {
                    ShowError("The Quota Watch desktop process did not start.");
                    return 1;
                }
                // Catch immediate loader/plugin failures while allowing the GUI
                // launcher to exit once the desktop process is healthy. The
                // Flutter process then becomes the only persistent app process.
                if (desktop.WaitForExit(1500) && desktop.ExitCode != 0)
                {
                    string logPath = WriteDiagnosticLog(
                        "Desktop exited during startup with code " +
                        desktop.ExitCode + ".",
                        null
                    );
                    ShowError(
                        "Quota Watch failed to start.\n\n" +
                        "Diagnostic log:\n" +
                        logPath
                    );
                    return desktop.ExitCode;
                }
                return 0;
            }
        }
        catch (Exception exception)
        {
            string logPath = WriteDiagnosticLog("", exception);
            ShowError(
                "Quota Watch launcher failed.\n\n" +
                "Diagnostic log:\n" +
                logPath
            );
            return 1;
        }
    }

    private static void ClearProviderEnvironment(ProcessStartInfo startInfo)
    {
        foreach (string name in new[]
        {
            "QUOTA_WATCH_CODEX_REAL",
            "QUOTA_WATCH_KIMI_REAL",
            "QUOTA_WATCH_KIMI_API_KEY",
            "KIMI_CODING_API_KEY",
            "QUOTA_WATCH_GLM_REAL",
            "QUOTA_WATCH_GLM_API_KEY",
            "GLM_API_KEY",
        })
        {
            startInfo.EnvironmentVariables[name] = "";
        }
    }

    private static bool TryReadDesktopOverride(
        string[] args,
        out string desktopExecutable
    )
    {
        desktopExecutable = null;
        for (int index = 0; index < args.Length; index++)
        {
            string argument = args[index];
            if (String.Equals(
                argument,
                "-DesktopExecutable",
                StringComparison.OrdinalIgnoreCase
            ))
            {
                if (index + 1 >= args.Length)
                {
                    return false;
                }
                desktopExecutable = args[++index];
                continue;
            }

            // Retain harmless compatibility with old shortcuts while removing
            // every backend/PowerShell responsibility from the production path.
            if (
                String.Equals(
                    argument,
                    "-BackendPort",
                    StringComparison.OrdinalIgnoreCase
                ) ||
                String.Equals(
                    argument,
                    "-StartupTimeoutSeconds",
                    StringComparison.OrdinalIgnoreCase
                )
            )
            {
                if (index + 1 >= args.Length)
                {
                    return false;
                }
                index++;
                continue;
            }
            if (
                String.Equals(
                    argument,
                    "-Desktop",
                    StringComparison.OrdinalIgnoreCase
                ) ||
                String.Equals(
                    argument,
                    "-DisableGlm",
                    StringComparison.OrdinalIgnoreCase
                )
            )
            {
                continue;
            }
            return false;
        }
        return true;
    }

    private static string FindDesktopExecutable(string repoRoot)
    {
        string buildRoot = Path.Combine(
            repoRoot,
            "quota_watch",
            "build",
            "windows"
        );
        foreach (string architecture in new[] { "x64", "arm64" })
        {
            string candidate = Path.Combine(
                buildRoot,
                architecture,
                "runner",
                "Release",
                "quota_watch.exe"
            );
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }
        return null;
    }

    private static bool ActivateExistingQuotaWatch()
    {
#if QUOTA_WATCH_LAUNCHER_TEST
        // Launcher tests run beside the user's real Quota Watch instance.
        // Never activate or inspect that unrelated production window.
        return false;
#else
        foreach (Process process in Process.GetProcessesByName("quota_watch"))
        {
            using (process)
            {
                IntPtr flutterWindow = IntPtr.Zero;
                uint targetProcessId = (uint)process.Id;
                EnumChildWindows(
                    GetDesktopWindow(),
                    delegate(IntPtr window, IntPtr parameter)
                    {
                        uint windowProcessId;
                        GetWindowThreadProcessId(
                            window,
                            out windowProcessId
                        );
                        if (windowProcessId != targetProcessId)
                        {
                            return true;
                        }

                        var className = new StringBuilder(128);
                        GetClassName(
                            window,
                            className,
                            className.Capacity
                        );
                        if (!String.Equals(
                            className.ToString(),
                            FlutterWindowClass,
                            StringComparison.Ordinal
                        ))
                        {
                            return true;
                        }
                        flutterWindow = window;
                        return false;
                    },
                    IntPtr.Zero
                );
                if (flutterWindow != IntPtr.Zero)
                {
                    return PostMessage(
                        flutterWindow,
                        TrayCallbackMessage,
                        IntPtr.Zero,
                        new IntPtr(LeftButtonUpMessage)
                    );
                }
            }
        }
        return false;
#endif
    }

    private static string WriteDiagnosticLog(
        string diagnostic,
        Exception exception
    )
    {
        string directory = Path.Combine(
            Path.GetTempPath(),
            "quota-watch-launcher"
        );
        Directory.CreateDirectory(directory);
        string logPath = Path.Combine(
            directory,
            "desktop-launcher-" +
            DateTime.UtcNow.ToString("yyyyMMddHHmmss") +
            "-" +
            Process.GetCurrentProcess().Id +
            ".log"
        );
        var content = new StringBuilder();
        content.AppendLine("Quota Watch desktop launcher failed.");
        content.AppendLine("UTC: " + DateTime.UtcNow.ToString("O"));
        if (!String.IsNullOrWhiteSpace(diagnostic))
        {
            content.AppendLine();
            content.AppendLine(diagnostic);
        }
        if (exception != null)
        {
            content.AppendLine();
            content.AppendLine(
                exception.GetType().Name + ": " + exception.Message
            );
        }
        File.WriteAllText(logPath, content.ToString(), Encoding.UTF8);
        return logPath;
    }

    private static void ShowError(string message)
    {
        MessageBox.Show(
            message,
            "Quota Watch",
            MessageBoxButtons.OK,
            MessageBoxIcon.Error
        );
    }

    private static string FindRepoRoot(string startDirectory)
    {
        var directory = new DirectoryInfo(startDirectory);
        for (int depth = 0; directory != null && depth < 6; depth++)
        {
            if (FindDesktopExecutable(directory.FullName) != null)
            {
                return directory.FullName;
            }
            directory = directory.Parent;
        }
        return null;
    }
}
