<#
.SYNOPSIS
    Backuper Setup - graphical installer with GitHub version check.
#>

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class BackuperSetupAppId {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
}
'@
[void][BackuperSetupAppId]::SetCurrentProcessExplicitAppUserModelID('Backuper.App.Setup')

$ErrorActionPreference = 'Stop'
$BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- self-elevate (Program Files needs admin) ---
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

$versionFile = Join-Path $BaseDir 'version.json'
$repoUrl = 'https://github.com/Meno1337/backuper'
$currentVersion = '1.0.0'
if (Test-Path -LiteralPath $versionFile) {
    try {
        $v = Get-Content -LiteralPath $versionFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $repoUrl = $v.RepoUrl
        $currentVersion = $v.Version
    } catch { }
}

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:shell="clr-namespace:System.Windows.Shell;assembly=PresentationFramework"
        Title="Backuper — установка" Height="640" Width="780"
        MinHeight="560" MinWidth="680" WindowStartupLocation="CenterScreen"
        WindowStyle="None" ResizeMode="CanResize"
        Background="#FF1E1E2E">
    <shell:WindowChrome.WindowChrome>
        <shell:WindowChrome CaptionHeight="70" CornerRadius="8" ResizeBorderThickness="6"
                            GlassFrameThickness="0" UseAeroCaptionButtons="False"/>
    </shell:WindowChrome.WindowChrome>
    <Window.Resources>
        <LinearGradientBrush x:Key="PrimaryBrush" StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#FFA6E3A1" Offset="0"/>
            <GradientStop Color="#FF74C69A" Offset="1"/>
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
                        <Border x:Name="bd" Background="{TemplateBinding Background}"
                                CornerRadius="8" Padding="{TemplateBinding Padding}">
                            <Border.Effect>
                                <DropShadowEffect Color="#000000" Opacity="0.3" BlurRadius="8" ShadowDepth="2"/>
                            </Border.Effect>
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Opacity" Value="0.88"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="bd" Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Background" Value="{StaticResource PrimaryBrush}"/>
            <Setter Property="Foreground" Value="#FF11111B"/>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#FF313244"/>
            <Setter Property="Foreground" Value="#FFCDD6F4"/>
            <Setter Property="BorderBrush" Value="#FF45475A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#FFCDD6F4"/>
        </Style>

        <!-- Window caption buttons -->
        <Style x:Key="WindowButton" TargetType="Button">
            <Setter Property="Width" Value="38"/>
            <Setter Property="Height" Value="34"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#FFCDD6F4"/>
            <Setter Property="FontSize" Value="15"/>
            <Setter Property="FontFamily" Value="Segoe UI Symbol"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="wbd" Background="{TemplateBinding Background}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="wbd" Property="Background" Value="#FF45475A"/>
                            </Trigger>
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
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="wbd" Property="Background" Value="#FFE05565"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Styled scrollbars -->
        <Style x:Key="ScrollBarPageButton" TargetType="RepeatButton">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RepeatButton"><Border Background="#00000000"/></ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="ScrollBarThumb" TargetType="Thumb">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Thumb">
                        <Border x:Name="thumb" Background="#FF585B70" CornerRadius="6" Margin="2"/>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="thumb" Property="Background" Value="#FFA6E3A1"/>
                            </Trigger>
                            <Trigger Property="IsDragging" Value="True">
                                <Setter TargetName="thumb" Property="Background" Value="#FF89B4FA"/>
                            </Trigger>
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
        <ControlTemplate x:Key="HorizontalScrollBarTemplate" TargetType="ScrollBar">
            <Grid Background="#FF11111B" Height="13">
                <Track x:Name="PART_Track" Orientation="Horizontal">
                    <Track.DecreaseRepeatButton><RepeatButton Command="ScrollBar.PageLeftCommand" Style="{StaticResource ScrollBarPageButton}"/></Track.DecreaseRepeatButton>
                    <Track.Thumb><Thumb Style="{StaticResource ScrollBarThumb}"/></Track.Thumb>
                    <Track.IncreaseRepeatButton><RepeatButton Command="ScrollBar.PageRightCommand" Style="{StaticResource ScrollBarPageButton}"/></Track.IncreaseRepeatButton>
                </Track>
            </Grid>
        </ControlTemplate>
        <Style TargetType="ScrollBar">
            <Setter Property="Template" Value="{StaticResource VerticalScrollBarTemplate}"/>
            <Style.Triggers>
                <Trigger Property="Orientation" Value="Horizontal">
                    <Setter Property="Template" Value="{StaticResource HorizontalScrollBarTemplate}"/>
                </Trigger>
            </Style.Triggers>
        </Style>
    </Window.Resources>

    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Grid Grid.Row="0" Margin="0,0,0,16">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0">
                <TextBlock Text="Backuper — установка" FontSize="24" FontWeight="Bold" Foreground="#FFA6E3A1"/>
                <TextBlock Text="Мастер установки: укажите папку сервера и место установки программы"
                           FontSize="13" Foreground="#FFA9ADC1" Margin="0,4,0,0"/>
            </StackPanel>
            <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Top"
                        shell:WindowChrome.IsHitTestVisibleInChrome="True">
                <Button x:Name="BtnWindowMin" Content="—" ToolTip="Свернуть"
                        Style="{StaticResource WindowButton}" shell:WindowChrome.IsHitTestVisibleInChrome="True"/>
                <Button x:Name="BtnWindowMax" Content="□" ToolTip="Развернуть / восстановить"
                        Style="{StaticResource WindowButton}" shell:WindowChrome.IsHitTestVisibleInChrome="True"/>
                <Button x:Name="BtnWindowClose" Content="✕" ToolTip="Выход"
                        Style="{StaticResource WindowCloseButton}" shell:WindowChrome.IsHitTestVisibleInChrome="True"/>
            </StackPanel>
        </Grid>

        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
            <StackPanel>
                <!-- Step 1 -->
                <Border Background="#FF181825" CornerRadius="10" Padding="16" Margin="0,0,0,12">
                    <StackPanel>
                        <TextBlock Text="1. Папка источника на сервере" FontSize="15" FontWeight="Bold" Foreground="#FF89B4FA"/>
                        <TextBlock Text="Откройте диалог и укажите сетевую папку, файлы которой нужно копировать."
                                   Foreground="#FFA9ADC1" FontSize="12" Margin="0,4,0,10" TextWrapping="Wrap"/>
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBox x:Name="TxtSource" Grid.Column="0"/>
                            <Button x:Name="BtnPickSource" Grid.Column="1" Content="📁  Выбрать папку"
                                    Margin="8,0,0,0" Width="160"/>
                        </Grid>
                    </StackPanel>
                </Border>

                <!-- Step 2 -->
                <Border Background="#FF181825" CornerRadius="10" Padding="16" Margin="0,0,0,12">
                    <StackPanel>
                        <TextBlock Text="2. Папка установки" FontSize="15" FontWeight="Bold" Foreground="#FF89B4FA"/>
                        <TextBlock Text="По умолчанию C:\Program Files (x86)\Backuper. Требуются права администратора."
                                   Foreground="#FFA9ADC1" FontSize="12" Margin="0,4,0,10" TextWrapping="Wrap"/>
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBox x:Name="TxtInstall" Grid.Column="0" Text="C:\Program Files (x86)\Backuper"/>
                            <Button x:Name="BtnPickInstall" Grid.Column="1" Content="📁  Выбрать папку"
                                    Margin="8,0,0,0" Width="160"/>
                        </Grid>
                    </StackPanel>
                </Border>

                <!-- Step 3 -->
                <Border Background="#FF181825" CornerRadius="10" Padding="16" Margin="0,0,0,12">
                    <StackPanel>
                        <TextBlock Text="3. Дополнительно" FontSize="15" FontWeight="Bold" Foreground="#FF89B4FA"/>
                        <CheckBox x:Name="ChkShortcut" IsChecked="True" Margin="0,10,0,0"
                                  Foreground="#FFCDD6F4" Content=" Создать ярлык Backuper на рабочем столе"/>
                        <TextBlock Text="Будут зарегистрированы задачи: копирование каждые 2 часа, слежение за папкой и еженедельная очистка."
                                   Foreground="#FFA9ADC1" FontSize="12" Margin="0,10,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                </Border>

                <!-- GitHub -->
                <Border Background="#FF181825" CornerRadius="10" Padding="16" Margin="0,0,0,12">
                    <StackPanel>
                        <TextBlock Text="Репозиторий GitHub" FontSize="15" FontWeight="Bold" Foreground="#FF89B4FA"/>
                        <TextBlock x:Name="RepoText" Text="" Foreground="#FFA9ADC1" FontSize="12"
                                   Margin="0,5,0,10" TextWrapping="Wrap"/>
                        <StackPanel Orientation="Horizontal">
                            <Button x:Name="BtnCheckGitHub" Content="⟳  Проверить версию на GitHub" Width="240" Margin="0,0,8,0"/>
                            <Button x:Name="BtnDownloadLatest" Content="⬇  Скачать последнюю версию" Width="240"/>
                        </StackPanel>
                        <TextBlock x:Name="GitHubStatus" Text="" Foreground="#FFA6E3A1" FontSize="12"
                                   Margin="0,10,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                </Border>

                <!-- Install progress -->
                <ProgressBar x:Name="InstallProgress" Height="20" Minimum="0" Maximum="100" Value="0"
                             Foreground="#FFA6E3A1" Background="#FF313244" Margin="0,4,0,8"/>
                <TextBlock x:Name="ProgressText" Text="Готово к установке" FontSize="12"
                           Foreground="#FFA9ADC1" Margin="0,0,0,8"/>

                <!-- Install button -->
                <Button x:Name="BtnInstall" Content="✅  УСТАНОВИТЬ" Height="46" FontSize="16"
                        Style="{StaticResource PrimaryButton}" Margin="0,0,0,12"/>

                <!-- Log -->
                <Border Background="#FF11111B" CornerRadius="8" Padding="10" Height="150">
                    <ScrollViewer x:Name="LogScroll" VerticalScrollBarVisibility="Auto">
                        <TextBlock x:Name="LogBox" Text="" FontFamily="Consolas" FontSize="11"
                                   Foreground="#FFA9ADC1" TextWrapping="Wrap"/>
                    </ScrollViewer>
                </Border>
            </StackPanel>
        </ScrollViewer>

        <TextBlock Grid.Row="2" Text="Backuper Setup  |  Программа и все задачи устанавливаются под текущего пользователя."
                   FontSize="11" Foreground="#FF6C7086" Margin="0,12,0,0"/>
    </Grid>
</Window>
'@

$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
$window = [System.Windows.Markup.XamlReader]::Load($reader)
function Find($n) { $window.FindName($n) }

$txtSource = Find 'TxtSource'; $txtInstall = Find 'TxtInstall'
$btnPickSource = Find 'BtnPickSource'; $btnPickInstall = Find 'BtnPickInstall'
$chkShortcut = Find 'ChkShortcut'; $btnInstall = Find 'BtnInstall'
$btnCheckGitHub = Find 'BtnCheckGitHub'; $btnDownloadLatest = Find 'BtnDownloadLatest'
$repoText = Find 'RepoText'; $gitHubStatus = Find 'GitHubStatus'
$logBox = Find 'LogBox'; $logScroll = Find 'LogScroll'
$installProgress = Find 'InstallProgress'; $progressText = Find 'ProgressText'
$btnWindowMin = Find 'BtnWindowMin'; $btnWindowMax = Find 'BtnWindowMax'; $btnWindowClose = Find 'BtnWindowClose'

function Append-Log {
    param([string]$Text)
    $logBox.Text += "$Text`n"
    $logScroll.ScrollToEnd()
}

$btnWindowMin.Add_Click({ $window.WindowState = [System.Windows.WindowState]::Minimized })
$btnWindowMax.Add_Click({
    if ($window.WindowState -eq [System.Windows.WindowState]::Maximized) {
        $window.WindowState = [System.Windows.WindowState]::Normal
    } else {
        $window.WindowState = [System.Windows.WindowState]::Maximized
    }
})
$btnWindowClose.Add_Click({ $window.Close() })

$repoText.Text = "Источник обновлений: $repoUrl`nТекущая версия: $currentVersion"
Append-Log "Backuper Setup готов. $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$dlLog = Join-Path ([System.IO.Path]::GetTempPath()) 'backuper_download.log'
if (Test-Path -LiteralPath $dlLog) {
    foreach ($line in (Get-Content -LiteralPath $dlLog -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ($line) { Append-Log "СКАЧИВАНИЕ: $line" }
    }
}

$btnPickSource.Add_Click({
    if (Get-Command Select-ModernFolder -ErrorAction SilentlyContinue) {
        $p = Select-ModernFolder -Title 'Укажите папку на сервере для копирования'
        if ($p) { $txtSource.Text = $p; Append-Log "Источник: $p" }
    } else {
        [System.Windows.MessageBox]::Show('Модуль выбора папки не найден.', 'Ошибка', 'OK', 'Error')
    }
})

$btnPickInstall.Add_Click({
    if (Get-Command Select-ModernFolder -ErrorAction SilentlyContinue) {
        $p = Select-ModernFolder -Title 'Укажите папку установки'
        if ($p) { $txtInstall.Text = $p; Append-Log "Папка установки: $p" }
    }
})

$btnCheckGitHub.Add_Click({
    $gitHubStatus.Text = 'Проверка...'
    try {
        $api = ($repoUrl -replace 'https://github\.com/', 'https://api.github.com/repos/').TrimEnd('/') + '/releases/latest'
        $rel = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'Backuper-Setup' } -TimeoutSec 20
        $latest = $rel.tag_name
        $gitHubStatus.Text = "Доступна версия: $latest"
        Append-Log "GitHub: доступна версия $latest"
    } catch {
        $gitHubStatus.Text = "Не удалось проверить: $($_.Exception.Message)"
        Append-Log "GitHub error: $($_.Exception.Message)"
    }
})

$btnDownloadLatest.Add_Click({
    $gitHubStatus.Text = 'Загрузка...'
    try {
        $api = ($repoUrl -replace 'https://github\.com/', 'https://api.github.com/repos/').TrimEnd('/') + '/releases/latest'
        $rel = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'Backuper-Setup' } -TimeoutSec 20
        $asset = $rel.assets | Where-Object { $_.name -match '\.zip$' } | Select-Object -First 1
        if ($asset) { $downloadUrl = $asset.browser_download_url }
        else { $downloadUrl = $repoUrl.TrimEnd('/') + '/archive/refs/heads/main.zip' }
        $temp = Join-Path ([System.IO.Path]::GetTempPath()) 'backuper_setup_download'
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        $zip = Join-Path $temp 'update.zip'
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zip -TimeoutSec 120
        Expand-Archive -LiteralPath $zip -DestinationPath $temp -Force
        $roots = @(Get-ChildItem -LiteralPath $temp -Directory -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -like 'backuper-*' })
        if ($roots.Count -gt 0) { $temp = $roots[0].FullName }
        $txtSource.Text = $temp
        $gitHubStatus.Text = "Загружена версия $($rel.tag_name). Папка источников обновлена."
        Append-Log "Скачано с GitHub в $temp"
    } catch {
        $gitHubStatus.Text = "Ошибка: $($_.Exception.Message)"
        Append-Log "Download error: $($_.Exception.Message)"
    }
})

$btnInstall.Add_Click({
    if (-not $txtSource.Text) {
        [System.Windows.MessageBox]::Show('Укажите папку источника.', 'Backuper', 'OK', 'Warning')
        return
    }
    $btnInstall.IsEnabled = $false
    Append-Log 'Запуск установки...'
    $args = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $BaseDir 'Install.ps1') + '"' +
            ' -SourceFolder "' + $txtSource.Text + '"' +
            ' -InstallDir "' + $txtInstall.Text + '"' +
            ' -SourceDir "' + $BaseDir + '"' +
            ' -Silent'
    if ($chkShortcut.IsChecked) { $args += ' -CreateShortcut' } else { $args += ' -NoShortcut' }
    $out = Join-Path ([System.IO.Path]::GetTempPath()) 'backuper_install_output.txt'
    $err = Join-Path ([System.IO.Path]::GetTempPath()) 'backuper_install_error.txt'
    Remove-Item -LiteralPath $out, $err -Force -ErrorAction SilentlyContinue
    $script:installProc = Start-Process powershell.exe -ArgumentList $args -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden
    $script:installOut = $out
    $script:installErr = $err
    $script:installLive = Join-Path ([System.IO.Path]::GetTempPath()) 'backuper_install_live.log'
    $script:installLastLen = 0
    $installProgress.Value = 0
    $progressText.Text = 'Установка выполняется...'

    if (-not $script:installTimer) {
        $script:installTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:installTimer.Interval = [TimeSpan]::FromMilliseconds(400)
        $script:installTimer.Add_Tick({
            $p = $script:installProc
            if (-not $p) { return }
            $text = Get-Content -LiteralPath $script:installLive -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($text) {
                if ($text.Length -gt $script:installLastLen) {
                    $newPart = $text.Substring($script:installLastLen)
                    $script:installLastLen = $text.Length
                    foreach ($line in ($newPart -split "`r?`n")) {
                        if ($line) { Append-Log $line }
                        if ($line -match '\[PROGRESS:(\d+)\]\s*(.*)') {
                            $installProgress.Value = [int]$Matches[1]
                            $progressText.Text = $Matches[2]
                        }
                    }
                }
            }
            if (-not $p.HasExited) { return }
            # final read
            $text = Get-Content -LiteralPath $script:installLive -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($text -and $text.Length -gt $script:installLastLen) {
                foreach ($line in (($text.Substring($script:installLastLen)) -split "`r?`n")) {
                    if ($line) { Append-Log $line }
                    if ($line -match '\[PROGRESS:(\d+)\]\s*(.*)') {
                        $installProgress.Value = [int]$Matches[1]
                        $progressText.Text = $Matches[2]
                    }
                }
            }
            $script:installTimer.Stop()
            $btnInstall.IsEnabled = $true
            if ($p.ExitCode -ne 0) {
                Append-Log (Get-Content -LiteralPath $script:installErr -Raw -ErrorAction SilentlyContinue)
                $progressText.Text = 'Ошибка установки'
                [System.Windows.MessageBox]::Show('Установка завершилась с ошибкой. См. лог.', 'Ошибка', 'OK', 'Error')
            } else {
                $installProgress.Value = 100
                $progressText.Text = 'Установка завершена'
                Append-Log 'Установка завершена успешно.'
                [System.Windows.MessageBox]::Show('Backuper установлен успешно!', 'Backuper Setup', 'OK', 'Information')
            }
            $script:installProc = $null
        })
    }
    $script:installTimer.Start()
})

$window.ShowDialog() | Out-Null
