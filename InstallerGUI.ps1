<#
.SYNOPSIS
    Backuper Setup - graphical installer with GitHub version check.
#>

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

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
        Title="Backuper — установка" Height="640" Width="780"
        MinHeight="560" MinWidth="680" WindowStartupLocation="CenterScreen"
        Background="#FF1E1E2E">
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
    </Window.Resources>

    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0" Margin="0,0,0,16">
            <TextBlock Text="Backuper — установка" FontSize="24" FontWeight="Bold" Foreground="#FFA6E3A1"/>
            <TextBlock Text="Мастер установки: укажите папку сервера и место установки программы"
                       FontSize="13" Foreground="#FFA9ADC1" Margin="0,4,0,0"/>
        </StackPanel>

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

                <!-- Install button -->
                <Button x:Name="BtnInstall" Content="✅  УСТАНОВИТЬ" Height="46" FontSize="16"
                        Style="{StaticResource PrimaryButton}" Margin="0,4,0,12"/>

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

function Append-Log {
    param([string]$Text)
    $logBox.Text += "$Text`n"
    $logScroll.ScrollToEnd()
}

$repoText.Text = "Источник обновлений: $repoUrl`nТекущая версия: $currentVersion"
Append-Log "Backuper Setup готов. $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

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
        if (-not $asset) { throw 'В релизе нет ZIP-архива' }
        $temp = Join-Path ([System.IO.Path]::GetTempPath()) 'backuper_setup_download'
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        $zip = Join-Path $temp 'update.zip'
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -TimeoutSec 120
        Expand-Archive -LiteralPath $zip -DestinationPath $temp -Force
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
    if (-not $chkShortcut.IsChecked) { $args += ' -NoShortcut' }
    $out = Join-Path ([System.IO.Path]::GetTempPath()) 'backuper_install_output.txt'
    $err = Join-Path ([System.IO.Path]::GetTempPath()) 'backuper_install_error.txt'
    $proc = Start-Process powershell.exe -ArgumentList $args -Wait -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden
    Append-Log (Get-Content -LiteralPath $out -Raw -ErrorAction SilentlyContinue)
    if ($proc.ExitCode -ne 0) {
        Append-Log (Get-Content -LiteralPath $err -Raw -ErrorAction SilentlyContinue)
        [System.Windows.MessageBox]::Show('Установка завершилась с ошибкой. См. лог.', 'Ошибка', 'OK', 'Error')
    } else {
        Append-Log 'Установка завершена успешно.'
        [System.Windows.MessageBox]::Show('Backuper установлен успешно!', 'Backuper Setup', 'OK', 'Information')
    }
    $btnInstall.IsEnabled = $true
})

$window.ShowDialog() | Out-Null
