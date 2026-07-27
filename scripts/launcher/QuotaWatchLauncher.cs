using System;
using System.Collections.Generic;
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
    private const uint ProcessSnapshotFlag = 0x00000002;
    private const uint SynchronizeAccess = 0x00100000;
    private const uint ProcessQueryLimitedInformationAccess = 0x00001000;
    private const uint InfiniteWait = 0xFFFFFFFF;
    private const uint WaitObject0 = 0x00000000;
    private static readonly IntPtr InvalidHandleValue = new IntPtr(-1);

    private delegate bool EnumWindowsCallback(
        IntPtr window,
        IntPtr parameter
    );

    [StructLayout(
        LayoutKind.Sequential,
        CharSet = CharSet.Unicode
    )]
    private struct ProcessEntry
    {
        public uint Size;
        public uint Usage;
        public uint ProcessId;
        public IntPtr DefaultHeapId;
        public uint ModuleId;
        public uint ThreadCount;
        public uint ParentProcessId;
        public int BasePriority;
        public uint Flags;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        public string ExecutableFile;
    }

    private sealed class RuntimeHandoff
    {
        public bool BackendOwned;
        public int BackendProcessId;
        public long BackendStartedUtcTicks;
        public int DesktopProcessId;
        public bool DesktopExited;
        public int DesktopExitCode;
    }

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

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr CreateToolhelp32Snapshot(
        uint flags,
        uint processId
    );

    [DllImport(
        "kernel32.dll",
        CharSet = CharSet.Unicode,
        SetLastError = true
    )]
    private static extern bool Process32First(
        IntPtr snapshot,
        ref ProcessEntry entry
    );

    [DllImport(
        "kernel32.dll",
        CharSet = CharSet.Unicode,
        SetLastError = true
    )]
    private static extern bool Process32Next(
        IntPtr snapshot,
        ref ProcessEntry entry
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(
        uint desiredAccess,
        bool inheritHandle,
        int processId
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint WaitForSingleObject(
        IntPtr handle,
        uint milliseconds
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetExitCodeProcess(
        IntPtr process,
        out uint exitCode
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
                // The previous launcher can briefly retain the mutex after its
                // Flutter window has already exited. Retry activation while
                // also waiting for ownership, so a new double-click either
                // wakes the real window or safely takes over after cleanup.
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
                        "Quota Watch is still starting or shutting down.\n\n" +
                        "Please wait a few seconds and try again."
                    );
                    return 1;
                }
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
                "Could not find scripts\\start_quota_watch.ps1.\n\n" +
                "Keep this launcher inside the Quota Watch repository."
            );
            return 1;
        }

        if (CanUseBootstrapRuntime(args))
        {
            return RunBootstrapRuntime(repoRoot, args);
        }

        string script = Path.Combine(
            repoRoot,
            "scripts",
            "start_quota_watch.ps1"
        );
        var arguments = new StringBuilder();
        arguments.Append("-NoLogo -NoProfile -ExecutionPolicy Bypass -File ");
        arguments.Append(QuoteArgument(script));
        arguments.Append(" -Desktop");
        foreach (string argument in args)
        {
            arguments.Append(' ');
            arguments.Append(QuoteArgument(argument));
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = arguments.ToString(),
            WorkingDirectory = repoRoot,
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };

        var diagnostic = new StringBuilder();
        object diagnosticLock = new object();
        try
        {
            using (Process process = Process.Start(startInfo))
            {
                if (process == null)
                {
                    ShowError("PowerShell did not start.");
                    return 1;
                }
                process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs eventArgs)
                {
                    AppendDiagnostic(
                        diagnostic,
                        diagnosticLock,
                        eventArgs.Data
                    );
                };
                process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs eventArgs)
                {
                    AppendDiagnostic(
                        diagnostic,
                        diagnosticLock,
                        eventArgs.Data
                    );
                };
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();
                process.WaitForExit();
                process.WaitForExit();
                if (process.ExitCode == 0)
                {
                    return 0;
                }

                string logPath = WriteDiagnosticLog(
                    diagnostic.ToString(),
                    null
                );
                ShowError(
                    "Quota Watch failed to start.\n\n" +
                    "Diagnostic log:\n" +
                    logPath
                );
                return process.ExitCode;
            }
        }
        catch (Exception exception)
        {
            string logPath = WriteDiagnosticLog(
                diagnostic.ToString(),
                exception
            );
            ShowError(
                "Quota Watch launcher failed.\n\n" +
                "Diagnostic log:\n" +
                logPath
            );
            return 1;
        }
    }

    private static bool CanUseBootstrapRuntime(string[] args)
    {
        for (int index = 0; index < args.Length; index++)
        {
            string option = args[index];
            if (
                String.Equals(
                    option,
                    "-BackendPort",
                    StringComparison.OrdinalIgnoreCase
                ) ||
                String.Equals(
                    option,
                    "-StartupTimeoutSeconds",
                    StringComparison.OrdinalIgnoreCase
                ) ||
                String.Equals(
                    option,
                    "-DesktopExecutable",
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
                    option,
                    "-DisableGlm",
                    StringComparison.OrdinalIgnoreCase
                ) ||
                String.Equals(
                    option,
                    "-Desktop",
                    StringComparison.OrdinalIgnoreCase
                )
            )
            {
                continue;
            }

            // Validation, smoke, Edge and keep-backend modes are short-lived
            // developer workflows. Preserve their original PowerShell path.
            return false;
        }
        return true;
    }

    private static int RunBootstrapRuntime(
        string repoRoot,
        string[] args
    )
    {
        string script = Path.Combine(
            repoRoot,
            "scripts",
            "start_quota_watch.ps1"
        );
        string runtimeDirectory = Path.Combine(
            Path.GetTempPath(),
            "quota-watch-launcher"
        );
        Directory.CreateDirectory(runtimeDirectory);
        string handoffPath = Path.Combine(
            runtimeDirectory,
            "runtime-handoff-" +
            DateTime.UtcNow.ToString("yyyyMMddHHmmssfff") +
            "-" +
            Process.GetCurrentProcess().Id +
            ".txt"
        );
        string bootstrapErrorPath = handoffPath + ".error.log";
        DeleteFileIfPresent(handoffPath);
        DeleteFileIfPresent(bootstrapErrorPath);

        var arguments = new StringBuilder();
        arguments.Append("-NoLogo -NoProfile -ExecutionPolicy Bypass -File ");
        arguments.Append(QuoteArgument(script));
        arguments.Append(" -Desktop -BootstrapDesktop");
        arguments.Append(" -RuntimeHandoffPath ");
        arguments.Append(QuoteArgument(handoffPath));
        foreach (string argument in args)
        {
            if (
                String.Equals(
                    argument,
                    "-Desktop",
                    StringComparison.OrdinalIgnoreCase
                )
            )
            {
                continue;
            }
            arguments.Append(' ');
            arguments.Append(QuoteArgument(argument));
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = arguments.ToString(),
            WorkingDirectory = repoRoot,
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden,
        };

        RuntimeHandoff handoff = null;
        try
        {
            using (Process bootstrap = Process.Start(startInfo))
            {
                if (bootstrap == null)
                {
                    ShowError("PowerShell bootstrap did not start.");
                    return 1;
                }
                bootstrap.WaitForExit();
                if (bootstrap.ExitCode != 0)
                {
                    string bootstrapLog = WriteDiagnosticLog(
                        "PowerShell bootstrap exited with code " +
                        bootstrap.ExitCode +
                        ". Child diagnostic: " +
                        bootstrapErrorPath,
                        null
                    );
                    ShowError(
                        "Quota Watch failed to start.\n\n" +
                        "Diagnostic log:\n" +
                        bootstrapLog
                    );
                    return bootstrap.ExitCode;
                }
            }

            string handoffText = File.Exists(handoffPath)
                ? File.ReadAllText(handoffPath, Encoding.UTF8)
                : "";
            if (!TryParseRuntimeHandoff(
                handoffText,
                out handoff
            ))
            {
                string handoffLog = WriteDiagnosticLog(
                    "Runtime handoff file was missing or invalid: " +
                    handoffPath,
                    null
                );
                ShowError(
                    "Quota Watch did not return a valid runtime handoff.\n\n" +
                    "Diagnostic log:\n" +
                    handoffLog
                );
                return 1;
            }

            if (handoff.DesktopExited)
            {
                return handoff.DesktopExitCode;
            }

            int desktopExitCode = WaitForExternalProcessExit(
                handoff.DesktopProcessId
            );
            if (desktopExitCode != 0)
            {
                WriteDiagnosticLog(
                    handoffText,
                    null
                );
            }
            return desktopExitCode;
        }
        catch (Exception exception)
        {
            StopOwnedBackend(handoff);
            string logPath = WriteDiagnosticLog(
                "Runtime handoff: " + handoffPath,
                exception
            );
            ShowError(
                "Quota Watch runtime supervision failed.\n\n" +
                "Diagnostic log:\n" +
                logPath
            );
            return 1;
        }
        finally
        {
            StopOwnedBackend(handoff);
            DeleteFileIfPresent(handoffPath);
        }
    }

    private static int WaitForExternalProcessExit(int processId)
    {
        IntPtr process = OpenProcess(
            SynchronizeAccess | ProcessQueryLimitedInformationAccess,
            false,
            processId
        );
        if (process == IntPtr.Zero)
        {
            // The desktop may exit between the PowerShell handoff and this
            // attachment. The backend still needs normal cleanup.
            return 0;
        }

        try
        {
            if (WaitForSingleObject(process, InfiniteWait) != WaitObject0)
            {
                return 0;
            }

            uint exitCode;
            if (!GetExitCodeProcess(process, out exitCode))
            {
                return 0;
            }
            return unchecked((int)exitCode);
        }
        finally
        {
            CloseHandle(process);
        }
    }

    private static void StopOwnedBackend(RuntimeHandoff handoff)
    {
        if (
            handoff == null ||
            !handoff.BackendOwned ||
            handoff.BackendProcessId <= 0
        )
        {
            return;
        }

        handoff.BackendOwned = false;
        try
        {
            using (Process backend = Process.GetProcessById(
                handoff.BackendProcessId
            ))
            {
                if (
                    backend.StartTime.ToUniversalTime().Ticks !=
                    handoff.BackendStartedUtcTicks
                )
                {
                    return;
                }
            }
        }
        catch (ArgumentException)
        {
            // The owned backend already exited, so there is nothing to stop.
            return;
        }
        catch (InvalidOperationException)
        {
            return;
        }
        StopProcessTree(handoff.BackendProcessId);
    }

    private static bool TryParseRuntimeHandoff(
        string diagnostic,
        out RuntimeHandoff handoff
    )
    {
        handoff = null;
        string[] lines = diagnostic.Replace("\r", "").Split('\n');
        foreach (string line in lines)
        {
            if (!line.StartsWith(
                "QUOTA_WATCH_RUNTIME_HANDOFF|",
                StringComparison.Ordinal
            ))
            {
                continue;
            }

            var fields = new Dictionary<string, int>(
                StringComparer.OrdinalIgnoreCase
            );
            string[] parts = line.Split('|');
            for (int index = 1; index < parts.Length; index++)
            {
                int separator = parts[index].IndexOf('=');
                if (separator <= 0)
                {
                    continue;
                }
                string name = parts[index].Substring(0, separator);
                int value;
                if (Int32.TryParse(
                    parts[index].Substring(separator + 1),
                    out value
                ))
                {
                    fields[name] = value;
                }
            }

            int backendOwned;
            int backendProcessId;
            long backendStartedUtcTicks;
            int desktopProcessId;
            int desktopExited;
            int desktopExitCode;
            if (
                !fields.TryGetValue("backendOwned", out backendOwned) ||
                !fields.TryGetValue("backendPid", out backendProcessId) ||
                !TryReadLongField(
                    parts,
                    "backendStartedUtcTicks",
                    out backendStartedUtcTicks
                ) ||
                !fields.TryGetValue("desktopPid", out desktopProcessId) ||
                !fields.TryGetValue("desktopExited", out desktopExited) ||
                !fields.TryGetValue("desktopExitCode", out desktopExitCode) ||
                desktopProcessId <= 0 ||
                (
                    backendOwned != 0 &&
                    (
                        backendProcessId <= 0 ||
                        backendStartedUtcTicks <= 0
                    )
                )
            )
            {
                return false;
            }

            handoff = new RuntimeHandoff
            {
                BackendOwned = backendOwned != 0,
                BackendProcessId = backendProcessId,
                BackendStartedUtcTicks = backendStartedUtcTicks,
                DesktopProcessId = desktopProcessId,
                DesktopExited = desktopExited != 0,
                DesktopExitCode = desktopExitCode,
            };
            return true;
        }
        return false;
    }

    private static bool TryReadLongField(
        string[] parts,
        string fieldName,
        out long value
    )
    {
        value = 0;
        foreach (string part in parts)
        {
            int separator = part.IndexOf('=');
            if (
                separator <= 0 ||
                !String.Equals(
                    part.Substring(0, separator),
                    fieldName,
                    StringComparison.Ordinal
                )
            )
            {
                continue;
            }
            return Int64.TryParse(
                part.Substring(separator + 1),
                out value
            );
        }
        return false;
    }

    private static void DeleteFileIfPresent(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
            // Temporary handoff cleanup must not hide the runtime result.
        }
    }

    private static void StopProcessTree(int rootProcessId)
    {
        List<int> processIds = ReadProcessTree(rootProcessId);
        for (int index = processIds.Count - 1; index >= 0; index--)
        {
            try
            {
                using (Process process = Process.GetProcessById(
                    processIds[index]
                ))
                {
                    process.Kill();
                    process.WaitForExit(5000);
                }
            }
            catch (ArgumentException)
            {
                // The process already exited.
            }
            catch (InvalidOperationException)
            {
                // The process already exited.
            }
            catch
            {
                // Cleanup is best-effort; a later launch still verifies the
                // health endpoint and never stops an unrelated port owner.
            }
        }
    }

    private static List<int> ReadProcessTree(int rootProcessId)
    {
        var processIds = new List<int>();
        processIds.Add(rootProcessId);

        IntPtr snapshot = CreateToolhelp32Snapshot(
            ProcessSnapshotFlag,
            0
        );
        if (snapshot == InvalidHandleValue)
        {
            return processIds;
        }

        var parentByProcess = new Dictionary<int, int>();
        try
        {
            var entry = new ProcessEntry();
            entry.Size = (uint)Marshal.SizeOf(typeof(ProcessEntry));
            if (Process32First(snapshot, ref entry))
            {
                do
                {
                    parentByProcess[(int)entry.ProcessId] =
                        (int)entry.ParentProcessId;
                    entry.Size =
                        (uint)Marshal.SizeOf(typeof(ProcessEntry));
                }
                while (Process32Next(snapshot, ref entry));
            }
        }
        finally
        {
            CloseHandle(snapshot);
        }

        bool added;
        do
        {
            added = false;
            foreach (KeyValuePair<int, int> pair in parentByProcess)
            {
                if (
                    processIds.Contains(pair.Value) &&
                    !processIds.Contains(pair.Key)
                )
                {
                    processIds.Add(pair.Key);
                    added = true;
                }
            }
        }
        while (added);

        return processIds;
    }

    private static bool ActivateExistingQuotaWatch()
    {
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
    }

    private static void AppendDiagnostic(
        StringBuilder diagnostic,
        object diagnosticLock,
        string line
    )
    {
        if (line == null)
        {
            return;
        }
        lock (diagnosticLock)
        {
            diagnostic.AppendLine(line);
        }
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
            content.Append(diagnostic);
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
            string script = Path.Combine(
                directory.FullName,
                "scripts",
                "start_quota_watch.ps1"
            );
            if (File.Exists(script))
            {
                return directory.FullName;
            }
            directory = directory.Parent;
        }
        return null;
    }

    private static string QuoteArgument(string value)
    {
        if (value.Length > 0 &&
            value.IndexOfAny(new[] { ' ', '\t', '\n', '\v', '"' }) < 0)
        {
            return value;
        }

        var quoted = new StringBuilder();
        quoted.Append('"');
        int backslashes = 0;
        foreach (char character in value)
        {
            if (character == '\\')
            {
                backslashes++;
                continue;
            }
            if (character == '"')
            {
                quoted.Append('\\', backslashes * 2 + 1);
                quoted.Append('"');
                backslashes = 0;
                continue;
            }
            quoted.Append('\\', backslashes);
            backslashes = 0;
            quoted.Append(character);
        }
        quoted.Append('\\', backslashes * 2);
        quoted.Append('"');
        return quoted.ToString();
    }
}
