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
        ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
        ServicePointManager.Expect100Continue = false;

        string work = Path.Combine(Path.GetTempPath(), "backuper_uninstall_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        bool ready = false;
        try
        {
            string zip = Path.Combine(work, "src.zip");
            using (WebClient wc = new WebClient())
            {
                wc.Headers.Add("User-Agent", "Backuper-Uninstaller");
                wc.DownloadFile("https://github.com/" + Repo + "/archive/refs/heads/main.zip", zip);
            }
            ZipFile.ExtractToDirectory(zip, work);
            string[] roots = Directory.GetDirectories(work, "backuper-*");
            if (roots.Length > 0) work = roots[0];
            ready = File.Exists(Path.Combine(work, "UninstallerGUI.ps1"));
        }
        catch (Exception ex) { lastError = ex.Message; }

        if (!ready)
        {
            string local = AppDomain.CurrentDomain.BaseDirectory;
            if (File.Exists(Path.Combine(local, "UninstallerGUI.ps1"))) work = local;
            else
            {
                MessageBox.Show("Не удалось загрузить файлы с GitHub и не найдены локальные файлы." +
                    (String.IsNullOrEmpty(lastError) ? "" : "\n\nПричина: " + lastError),
                    "Backuper Uninstaller", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
        }

        string args = "-NoProfile -ExecutionPolicy Bypass -File \"" +
                      Path.Combine(work, "UninstallerGUI.ps1") + "\"";
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
                MessageBox.Show("Не удалось запустить удаление: " + ex.Message,
                    "Backuper Uninstaller", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
}
