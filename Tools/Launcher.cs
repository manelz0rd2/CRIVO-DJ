using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;

[assembly: AssemblyTitle("CRIVO DJ")]
[assembly: AssemblyDescription("CRIVO DJ por MANELZ0RD")]
[assembly: AssemblyProduct("CRIVO DJ")]
[assembly: AssemblyCompany("MANELZ0RD")]
[assembly: AssemblyCopyright("© MANELZ0RD")]
[assembly: AssemblyVersion("0.9.0.1")]
[assembly: AssemblyFileVersion("0.9.0.1")]

internal static class Launcher
{
    [STAThread]
    private static void Main()
    {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(root, "ODT.ps1");
        string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
        if (!File.Exists(powershell)) powershell = "powershell.exe";
        var start = new ProcessStartInfo
        {
            FileName = powershell,
            Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -File \"" + script + "\"",
            WorkingDirectory = root,
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };
        Process.Start(start);
    }
}
