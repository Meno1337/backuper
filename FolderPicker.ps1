<#
.SYNOPSIS
    Modern Windows folder picker (the same dialog as "Select folder" in Explorer).
    Uses IFileOpenDialog with FOS_PICKFOLDERS. Falls back to FolderBrowserDialog.
#>

if (-not ('Backuper.Dialogs.ModernFolderPicker' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace Backuper.Dialogs
{
    [Flags]
    public enum FOS : uint
    {
        FOS_NOCHANGEDIR      = 0x00000008,
        FOS_PICKFOLDERS      = 0x00000020,
        FOS_FORCEFILESYSTEM  = 0x00000040,
        FOS_PATHMUSTEXIST    = 0x00000800,
        FOS_DONTADDTORECENT  = 0x02000000
    }

    [ComImport, Guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7")]
    public class FileOpenDialog { }

    [ComImport, Guid("42f85136-db7e-439c-85f1-e4075d135fc8"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IFileDialog
    {
        [PreserveSig] uint Show(IntPtr hwnd);
        void SetFileTypes(uint cFileTypes, IntPtr rgFilterSpec);
        void SetFileTypeIndex(uint iFileType);
        uint GetFileTypeIndex();
        void Advise(IntPtr pfde, out uint pdwCookie);
        void Unadvise(uint dwCookie);
        void SetFlags(FOS flags);
        FOS GetFlags();
        void SetDefaultFolder(IShellItem psi);
        void SetFolder(IShellItem psi);
        void GetFolder(out IShellItem ppsi);
        void GetCurrentSelection(out IShellItem ppsi);
        void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string pszName);
        void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string pszTitle);
        void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string pszText);
        void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
        void GetResult(out IShellItem ppsi);
        void AddPlace(IShellItem psi, int alignment);
        void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string pszDefaultExtension);
        void Close(int hr);
        void SetClientGuid(ref Guid guid);
        void ClearClientData();
        void SetFilter(IntPtr pFilter);
    }

    [ComImport, Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IShellItem
    {
        void BindToHandler(IntPtr pbc, ref Guid bhid, ref Guid riid, out IntPtr ppv);
        void GetParent(out IShellItem ppsi);
        void GetDisplayName(int sigdnName,
            [MarshalAs(UnmanagedType.LPWStr)] out string ppszName);
        void GetAttributes(uint sfgaoMask, out uint psfgaoAttribs);
        void Compare(IShellItem psi, int hint, out int piOrder);
    }

    public class PickResult
    {
        public bool Cancelled;
        public string Path;
    }

    public static class ModernFolderPicker
    {
        const int SIGDN_FILESYSPATH = unchecked((int)0x80058000);

        public static PickResult Pick(string title)
        {
            FileOpenDialog raw = new FileOpenDialog();
            IFileDialog dlg = (IFileDialog)raw;
            dlg.SetFlags(FOS.FOS_PICKFOLDERS | FOS.FOS_FORCEFILESYSTEM |
                         FOS.FOS_PATHMUSTEXIST | FOS.FOS_NOCHANGEDIR);
            if (!String.IsNullOrEmpty(title)) dlg.SetTitle(title);
            uint hr;
            try { hr = dlg.Show(IntPtr.Zero); }
            catch (COMException ex)
            {
                // 0x800704C7 = ERROR_CANCELLED - the user just pressed Cancel
                if (unchecked((uint)ex.HResult) == 0x800704C7)
                    return new PickResult { Cancelled = true };
                throw;
            }
            if (hr != 0) return new PickResult { Cancelled = true };
            IShellItem item;
            dlg.GetResult(out item);
            string path;
            item.GetDisplayName(SIGDN_FILESYSPATH, out path);
            return new PickResult { Path = path ?? String.Empty };
        }
    }
}
'@
}

$script:FolderPickerError = ''

function Select-ModernFolder {
    param([string]$Title = 'Выберите папку')
    $script:FolderPickerError = ''
    try {
        $result = [Backuper.Dialogs.ModernFolderPicker]::Pick($Title)
        if ($result -and -not $result.Cancelled) { return $result.Path }
    } catch {
        $script:FolderPickerError = $_.Exception.Message
    }
    return $null
}
