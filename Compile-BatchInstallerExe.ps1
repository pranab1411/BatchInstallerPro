# Compile-BatchInstallerExe.ps1
# Compiles BatchInstaller.ps1 into a single standalone Windows GUI executable (BatchInstaller.exe)
# Developed by Pranab Chourasiya

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

$psScriptPath = Join-Path $scriptDir "BatchInstaller.ps1"
$exePath      = Join-Path $scriptDir "BatchInstaller.exe"
$csPath       = Join-Path $scriptDir "BatchInstallerHost.cs"

if (-not (Test-Path $psScriptPath)) {
    Write-Error "BatchInstaller.ps1 not found in $scriptDir"
    exit 1
}

$psScriptContent = Get-Content -Path $psScriptPath -Raw -Encoding UTF8
$bytes = [System.Text.Encoding]::UTF8.GetBytes($psScriptContent)
$base64Script = [Convert]::ToBase64String($bytes)

$csharpSource = @"
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Text;
using System.Windows.Forms;

namespace BatchInstallerPro
{
    static class Program
    {
        [STAThread]
        static void Main()
        {
            try
            {
                string exePath = Assembly.GetExecutingAssembly().Location;
                string exeDir = Path.GetDirectoryName(exePath);
                Environment.CurrentDirectory = exeDir;

                string base64Payload = "$base64Script";
                byte[] scriptBytes = Convert.FromBase64String(base64Payload);
                string scriptText = Encoding.UTF8.GetString(scriptBytes);

                string tempEnginePath = Path.Combine(Path.GetTempPath(), "BatchInstaller_Engine.ps1");
                File.WriteAllText(tempEnginePath, scriptText, Encoding.UTF8);

                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "powershell.exe";
                psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + tempEnginePath + "\"";
                psi.WorkingDirectory = exeDir;
                psi.UseShellExecute = true;

                WindowsPrincipal principal = new WindowsPrincipal(WindowsIdentity.GetCurrent());
                if (!principal.IsInRole(WindowsBuiltInRole.Administrator))
                {
                    psi.Verb = "runas";
                }

                Process proc = Process.Start(psi);
                if (proc != null)
                {
                    proc.WaitForExit();
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show("Batch Installer Pro Launch Error:\n\n" + ex.Message, "Batch Installer Pro", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
}
"@

Set-Content -Path $csPath -Value $csharpSource -Encoding UTF8

$cscCompiler = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $cscCompiler)) {
    $cscCompiler = "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe"
}

Write-Host "Compiling BatchInstaller.exe using $cscCompiler..." -ForegroundColor Cyan

& $cscCompiler /target:winexe /out:"$exePath" /r:System.Windows.Forms.dll /r:System.dll "$csPath"

if (Test-Path $exePath) {
    Remove-Item -Path $csPath -Force -ErrorAction SilentlyContinue
    Write-Host "SUCCESS! BatchInstaller.exe successfully created at: $exePath" -ForegroundColor Green
} else {
    Write-Host "Compilation failed." -ForegroundColor Red
}
