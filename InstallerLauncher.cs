using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Windows.Forms;

class Program
{
    const string Repo = "Meno1337/backuper";

    static string lastError = "";

    static void Main()
    {
        // GitHub requires TLS 1.2; .NET Framework defaults to TLS 1.0
        ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
        ServicePointManager.Expect100Continue = false;

        string work = Path.Combine(Path.GetTempPath(), "backuper_setup_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        bool ready = false;

        // Download the current program files from GitHub (main branch source archive)
        try
        {
            string zip = Path.Combine(work, "src.zip");
            using (WebClient wc = new WebClient())
            {
                wc.Headers.Add("User-Agent", "Backuper-Installer");
                wc.DownloadFile("https://github.com/" + Repo + "/archive/refs/heads/main.zip", zip);
            }
            ZipFile.ExtractToDirectory(zip, work);
            string[] roots = Directory.GetDirectories(work, "backuper-*");
            if (roots.Length > 0) work = roots[0];
            ready = File.Exists(Path.Combine(work, "InstallerGUI.ps1"));
        }
        catch (Exception ex) { lastError = ex.Message; }

        // Fallback: files next to this exe (for local/offline use)
        if (!ready)
        {
            string local = AppDomain.CurrentDomain.BaseDirectory;
            if (File.Exists(Path.Combine(local, "InstallerGUI.ps1"))) work = local;
            else
            {
                MessageBox.Show("Не удалось загрузить файлы с GitHub и не найдены локальные файлы программы." +
                    (String.IsNullOrEmpty(lastError) ? "" : "\n\nПричина: " + lastError),
                    "Backuper Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
        }

        string script = Path.Combine(work, "InstallerGUI.ps1");
        string args = "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\"";

        // Ask for administrator rights (needed for Program Files)
        try
        {
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = "powershell.exe";
            psi.Arguments = args;
            psi.WorkingDirectory = work;
            psi.UseShellExecute = true;
            psi.Verb = "runas";
            Process.Start(psi);
        }
        catch
        {
            // user cancelled UAC - try without elevation; the GUI will ask again
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "powershell.exe";
                psi.Arguments = args;
                psi.WorkingDirectory = work;
                psi.UseShellExecute = false;
                Process.Start(psi);
            }
            catch (Exception ex)
            {
                MessageBox.Show("Не удалось запустить установку: " + ex.Message,
                    "Backuper Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
}
