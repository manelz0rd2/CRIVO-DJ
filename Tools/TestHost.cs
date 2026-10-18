using System;
using System.Collections.Generic;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;

internal static class TestHost
{
    [STAThread]
    private static int Main()
    {
        string root = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", ".."));
        string scriptPath = Path.Combine(root, "ODT.ps1");
        if (!File.Exists(scriptPath)) return 2;

        Directory.SetCurrentDirectory(root);
        InitialSessionState initialState = InitialSessionState.CreateDefault();
        using (Runspace runspace = RunspaceFactory.CreateRunspace(initialState))
        using (PowerShell shell = PowerShell.Create())
        {
            runspace.ApartmentState = ApartmentState.STA;
            runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
            runspace.Open();
            shell.Runspace = runspace;
            string escapedRoot = root.Replace("'", "''");
            string escapedScript = scriptPath.Replace("'", "''");
            shell.AddScript("Set-Location -LiteralPath '" + escapedRoot + "'; & '" + escapedScript + "'");
            shell.Invoke();
            if (shell.HadErrors)
            {
                var errors = new List<string>();
                foreach (var item in shell.Streams.Error) errors.Add(item.ToString());
                File.WriteAllLines(Path.Combine(root, "Tests", "UiHost", "host-errors.txt"), errors.ToArray());
                return 1;
            }
        }
        return 0;
    }
}
