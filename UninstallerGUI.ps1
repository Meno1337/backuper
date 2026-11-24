<#
.SYNOPSIS
    Backuper Uninstaller - graphical removal wizard with progress and log.
#>

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
$BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class BackuperUninstallAppId {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
}
'@
[void][BackuperUninstallAppId]::SetCurrentProcessExplicitAppUserModelID('Backuper.App.Uninstall')

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $env:BACKUPER_SKIP_ELEVATE -and -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList `
        "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" | Out-Null
    exit
}
if (Test-Path -LiteralPath (Join-Path $BaseDir 'FolderPicker.ps1')) {
    . (Join-Path $BaseDir 'FolderPicker.ps1')
}

$defaultInstall = 'C:\Program Files (x86)\Backuper'
$cfg = Join-Path $defaultInstall 'settings.json'
if (Test-Path -LiteralPath $cfg) {
    try { $defaultInstall = (Get-Item -LiteralPath $cfg).DirectoryName } catch { }
}

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:shell="clr-namespace:System.Windows.Shell;assembly=PresentationFramework"
        Title="Backuper — удаление" Height="600" Width="760"
        MinHeight="520" MinWidth="660" WindowStartupLocation="CenterScreen"
        WindowStyle="None" ResizeMode="CanResize" Background="#FF1E1E2E">
    <shell:WindowChrome.WindowChrome>
        <shell:WindowChrome CaptionHeight="70" CornerRadius="8" ResizeBorderThickness="6"
                            GlassFrameThickness="0" UseAeroCaptionButtons="False"/>
    </shell:WindowChrome.WindowChrome>
    <Window.Resources>
        <LinearGradientBrush x:Key="DangerBrush" StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#FFE05565" Offset="0"/>
            <GradientStop Color="#FFB04050" Offset="1"/>
        </LinearGradientBrush>
        <LinearGradientBrush x:Key="InfoBrush" StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#FF585B70" Offset="0"/>
            <GradientStop Color="#FF3B3E54" Offset="1"/>
        </LinearGradientBrush>
        <Style TargetType="Button">
            <Setter Property="Background" Value="{StaticResource InfoBrush}"/>
            <Setter Property="Foreground" Value="#FFCDD6F4"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="8"
                                Padding="{TemplateBinding Padding}">
                            <Border.Effect><DropShadowEffect Color="#000000" Opacity="0.3" BlurRadius="8" ShadowDepth="2"/></Border.Effect>
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.88"/></Trigger>
                            <Trigger Property="IsEnabled" Value="False"><Setter TargetName="bd" Property="Opacity" Value="0.4"/></Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Background" Value="{StaticResource DangerBrush}"/>
            <Setter Property="Foreground" Value="#FFFFFFFF"/>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#FF313244"/>
            <Setter Property="Foreground" Value="#FFCDD6F4"/>
            <Setter Property="BorderBrush" Value="#FF45475A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>
        <Style TargetType="TextBlock"><Setter Property="Foreground" Value="#FFCDD6F4"/></Style>
        <Style x:Key="WindowButton" TargetType="Button">
            <Setter Property="Width" Value="38"/><Setter Property="Height" Value="34"/>
            <Setter Property="Background" Value="Transparent"/><Setter Property="Foreground" Value="#FFCDD6F4"/>
            <Setter Property="FontSize" Value="15"/><Setter Property="FontFamily" Value="Segoe UI Symbol"/>
            <Setter Property="Cursor" Value="Hand"/><Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="wbd" Background="{TemplateBinding Background}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="wbd" Property="Background" Value="#FF45475A"/></Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="WindowCloseButton" TargetType="Button" BasedOn="{StaticResource WindowButton}">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="wbd" Background="{TemplateBinding Background}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="wbd" Property="Background" Value="#FFE05565"/></Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="ScrollBarPageButton" TargetType="RepeatButton">
            <Setter Property="Template">
                <Setter.Value><ControlTemplate TargetType="RepeatButton"><Border Background="#00000000"/></ControlTemplate></Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="ScrollBarThumb" TargetType="Thumb">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Thumb">
                        <Border x:Name="thumb" Background="#FF585B70" CornerRadius="6" Margin="2"/>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="thumb" Property="Background" Value="#FFA6E3A1"/></Trigger>
                            <Trigger Property="IsDragging" Value="True"><Setter TargetName="thumb" Property="Background" Value="#FF89B4FA"/></Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <ControlTemplate x:Key="VerticalScrollBarTemplate" TargetType="ScrollBar">
            <Grid Background="#FF11111B" Width="13">
                <Track x:Name="PART_Track" IsDirectionReversed="True" Orientation="Vertical">
                    <Track.DecreaseRepeatButton><RepeatButton Command="ScrollBar.PageUpCommand" Style="{StaticResource ScrollBarPageButton}"/></Track.DecreaseRepeatButton>
                    <Track.Thumb><Thumb Style="{StaticResource ScrollBarThumb}"/></Track.Thumb>
                    <Track.IncreaseRepeatButton><RepeatButton Command="ScrollBar.PageDownCommand" Style="{StaticResource ScrollBarPageButton}"/></Track.IncreaseRepeatButton>
                </Track>
            </Grid>
        </ControlTemplate>
        <Style TargetType="ScrollBar">
            <Setter Property="Template" Value="{StaticResource VerticalScrollBarTemplate}"/>
        </Style>
    </Window.Resources>

    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid Grid.Row="0" Margin="0,0,0,16">
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <StackPanel>
                <TextBlock Text="Backuper — удаление" FontSize="24" FontWeight="Bold" Foreground="#FFF38BAB"/>
                <TextBlock Text="Мастер удаления: задачи, ярлык и файлы программы" FontSize="13"
                           Foreground="#FFA9ADC1" Margin="0,4,0,0"/>
            </StackPanel>
            <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Top"
                        shell:WindowChrome.IsHitTestVisibleInChrome="True">
                <Button x:Name="BtnWindowMin" Content="—" Style="{StaticResource WindowButton}" shell:WindowChrome.IsHitTestVisibleInChrome="True"/>
                <Button x:Name="BtnWindowMax" Content="□" Style="{StaticResource WindowButton}" shell:WindowChrome.IsHitTestVisibleInChrome="True"/>
                <Button x:Name="BtnWindowClose" Content="✕" Style="{StaticResource WindowCloseButton}" shell:WindowChrome.IsHitTestVisibleInChrome="True"/>
            </StackPanel>
        </Grid>

        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
            <StackPanel>
                <Border Background="#FF181825" CornerRadius="10" Padding="16" Margin="0,0,0,12">
                    <StackPanel>
                        <TextBlock Text="Папка установки" FontSize="15" FontWeight="Bold" Foreground="#FF89B4FA"/>
                        <Grid Margin="0,10,0,0">
                            <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                            <TextBox x:Name="TxtInstall"/>
                            <Button x:Name="BtnPickInstall" Grid.Column="1" Content="📁  Выбрать папку"
                                    Margin="8,0,0,0" Width="160"/>
                        </Grid>
                    </StackPanel>
                </Border>
                <Border Background="#FF181825" CornerRadius="10" Padding="16" Margin="0,0,0,12">
                    <StackPanel>
                        <TextBlock Text="Данные" FontSize="15" FontWeight="Bold" Foreground="#FF89B4FA"/>
                        <CheckBox x:Name="ChkKeepData" IsChecked="True" Margin="0,10,0,0"
                                  Foreground="#FFCDD6F4"
                                  Content=" Сохранить Files, Logs, Versions и settings.json"/>
                        <TextBlock Text="Если галочка снята — удаляется вся папка программы вместе с резервными копиями."
                                   Foreground="#FFF38BAB" FontSize="12" Margin="0,8,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                </Border>
                <ProgressBar x:Name="UninstallProgress" Height="20" Minimum="0" Maximum="100" Value="0"
                             Foreground="#FFA6E3A1" Background="#FF313244" Margin="0,4,0,8"/>
                <TextBlock x:Name="ProgressText" Text="Готово к удалению" FontSize="12"
                           Foreground="#FFA9ADC1" Margin="0,0,0,10"/>
                <Button x:Name="BtnUninstall" Content="🗑  УДАЛИТЬ BACKUPER" Height="46" FontSize="16"
                        Style="{StaticResource DangerButton}" Margin="0,0,0,12"/>
                <Border Background="#FF11111B" CornerRadius="8" Padding="10" Height="160">
                    <ScrollViewer x:Name="LogScroll" VerticalScrollBarVisibility="Auto">
                        <TextBlock x:Name="LogBox" Text="" FontFamily="Consolas" FontSize="11"
                                   Foreground="#FFA9ADC1" TextWrapping="Wrap"/>
                    </ScrollViewer>
                </Border>
            </StackPanel>
        </ScrollViewer>
        <TextBlock Grid.Row="2" Text="Backuper Uninstaller  |  Удаление задач, ярлыка и файлов программы."
                   FontSize="11" Foreground="#FF6C7086" Margin="0,12,0,0"/>
    </Grid>
</Window>
'@

$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
$window = [System.Windows.Markup.XamlReader]::Load($reader)
function Find($n) { $window.FindName($n) }

$txtInstall = Find 'TxtInstall'; $btnPickInstall = Find 'BtnPickInstall'
$chkKeepData = Find 'ChkKeepData'; $btnUninstall = Find 'BtnUninstall'
$progress = Find 'UninstallProgress'; $progressText = Find 'ProgressText'
$logBox = Find 'LogBox'; $logScroll = Find 'LogScroll'
$btnWindowMin = Find 'BtnWindowMin'; $btnWindowMax = Find 'BtnWindowMax'; $btnWindowClose = Find 'BtnWindowClose'
$txtInstall.Text = $defaultInstall

function Append-Log {
    param([string]$Text)
    $logBox.Text += "$Text`n"
    $logScroll.ScrollToEnd()
}
Append-Log "Backuper Uninstaller готов. $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$dlLog = Join-Path ([System.IO.Path]::GetTempPath()) 'backuper_download.log'
if (Test-Path -LiteralPath $dlLog) {
    foreach ($line in (Get-Content -LiteralPath $dlLog -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ($line) { Append-Log "СКАЧИВАНИЕ: $line" }
    }
}

$btnWindowMin.Add_Click({ $window.WindowState = [System.Windows.WindowState]::Minimized })
$btnWindowMax.Add_Click({
    if ($window.WindowState -eq [System.Windows.WindowState]::Maximized) {
        $window.WindowState = [System.Windows.WindowState]::Normal
    } else { $window.WindowState = [System.Windows.WindowState]::Maximized }
})
$btnWindowClose.Add_Click({ $window.Close() })

$btnPickInstall.Add_Click({
    if (Get-Command Select-ModernFolder -ErrorAction SilentlyContinue) {
        $p = Select-ModernFolder -Title 'Укажите папку установки Backuper'
        if ($p) { $txtInstall.Text = $p; Append-Log "Папка: $p" }
    }
})

$btnUninstall.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show(
        'Удалить Backuper с этого компьютера?', 'Подтверждение', 'YesNo', 'Question')
    if ($confirm -ne 'Yes') { return }
    $btnUninstall.IsEnabled = $false
    $args = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $BaseDir 'Uninstall.ps1') + '"' +
            ' -InstallDir "' + $txtInstall.Text + '" -Silent'
    if ($chkKeepData.IsChecked) { $args += ' -KeepData' }
    $out = Join-Path ([System.IO.Path]::GetTempPath()) 'backuper_uninstall_output.txt'
    $err = Join-Path ([System.IO.Path]::GetTempPath()) 'backuper_uninstall_error.txt'
    Remove-Item -LiteralPath $out, $err -Force -ErrorAction SilentlyContinue
    $script:unProc = Start-Process powershell.exe -ArgumentList $args -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden
    $script:unOut = $out; $script:unErr = $err
    $script:unLive = Join-Path ([System.IO.Path]::GetTempPath()) 'backuper_uninstall_live.log'
    $script:unLastLen = 0
    $progress.Value = 0
    $progressText.Text = 'Удаление выполняется...'

    if (-not $script:unTimer) {
        $script:unTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:unTimer.Interval = [TimeSpan]::FromMilliseconds(400)
        $script:unTimer.Add_Tick({
            $p = $script:unProc
            if (-not $p) { return }
            $text = Get-Content -LiteralPath $script:unLive -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($text -and $text.Length -gt $script:unLastLen) {
                $newPart = $text.Substring($script:unLastLen)
                $script:unLastLen = $text.Length
                foreach ($line in ($newPart -split "`r?`n")) {
                    if ($line) { Append-Log $line }
                    if ($line -match '\[PROGRESS:(\d+)\]\s*(.*)') {
                        $progress.Value = [int]$Matches[1]
                        $progressText.Text = $Matches[2]
                    }
                }
            }
            if (-not $p.HasExited) { return }
            $script:unTimer.Stop()
            $btnUninstall.IsEnabled = $true
            $finalText = Get-Content -LiteralPath $script:unLive -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($finalText -notmatch '\[PROGRESS:100\]') {
                Append-Log (Get-Content -LiteralPath $script:unErr -Raw -ErrorAction SilentlyContinue)
                $progressText.Text = 'Ошибка удаления'
                [System.Windows.MessageBox]::Show('Ошибка при удалении. См. лог.', 'Ошибка', 'OK', 'Error')
            } else {
                $progress.Value = 100
                $progressText.Text = 'Удаление завершено'
                Append-Log 'Backuper удалён.'
                [System.Windows.MessageBox]::Show('Backuper удалён с компьютера.', 'Backuper Uninstaller', 'OK', 'Information')
            }
            $script:unProc = $null
        })
    }
    $script:unTimer.Start()
})

$window.ShowDialog() | Out-Null
