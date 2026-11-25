<#
.SYNOPSIS
    Backuper - graphical interface for backup and restore.
    Requires: Windows PowerShell 5.1 (built into Windows). Run with:
    powershell.exe -ExecutionPolicy Bypass -File BackuperGUI.ps1
#>

param(
    [switch]$Minimized
)

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Give this process its own AppUserModelID so Windows shows OUR icon in the
# taskbar instead of the powershell.exe icon.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class BackuperAppId {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
}
'@
[void][BackuperAppId]::SetCurrentProcessExplicitAppUserModelID('Backuper.App.Main')

$ErrorActionPreference = 'Stop'
$BaseDir      = Split-Path -Parent $MyInvocation.MyCommand.Path
$BackupCore   = Join-Path $BaseDir 'BackupCore.ps1'
$VersionsModule = Join-Path $BaseDir 'Versions.ps1'
$FolderPickerModule = Join-Path $BaseDir 'FolderPicker.ps1'
$Compress7zModule   = Join-Path $BaseDir 'Compress7z.ps1'
$Archive7zModule    = Join-Path $BaseDir 'Archive7z.ps1'
$SettingsFile = Join-Path $BaseDir 'settings.json'
$UserRoot     = Join-Path $env:LOCALAPPDATA 'Backuper'
$UserSettingsFile = Join-Path $UserRoot 'settings.json'
$IconFile     = Join-Path $BaseDir 'app_icon_v2.ico'
. $VersionsModule
. $FolderPickerModule
. $Compress7zModule
. $Archive7zModule

# ---------- Settings ----------
$DefaultSettings = [PSCustomObject]@{
    Source            = '\\Lpu6011-app010\transfer\карпов'
    Destination       = 'C:\Users\karpovD\Desktop\backuper\Files'
    LogDir            = 'C:\Users\karpovD\Desktop\backuper\Logs'
    AutoRunEnabled    = $true
    IntervalHours     = 2
    LogRetentionDays  = 7
    VersionsDir       = 'C:\Users\karpovD\Desktop\backuper\Versions'
    VersionRetentionDays = 30
    AutoUpdateEnabled    = $true
    CompressEnabled      = $false
}

function Load-Settings {
    $path = if (Test-Path -LiteralPath $UserSettingsFile) { $UserSettingsFile } else { $SettingsFile }
    if (Test-Path -LiteralPath $path) {
        try {
            $s = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            # merge with defaults
            $d = $DefaultSettings.PSObject.Properties.Name
            foreach ($p in $d) {
                if ($s.PSObject.Properties.Name -notcontains $p) {
                    $s | Add-Member -NotePropertyName $p -NotePropertyValue $DefaultSettings.$p
                }
            }
            return $s
        } catch { }
    }
    return $DefaultSettings.psobject.Copy()
}

function Save-Settings {
    param([PSCustomObject]$Settings)
    try {
        $Settings | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $SettingsFile -Encoding UTF8 -ErrorAction Stop
    } catch {
        # Program Files is read-only without admin - save under the user profile
        New-Item -ItemType Directory -Path $UserRoot -Force | Out-Null
        $Settings | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $UserSettingsFile -Encoding UTF8
    }
}

function Test-Writable([string]$dir) {
    try {
        New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
        $p = Join-Path $dir ('.w_' + [guid]::NewGuid().ToString('N'))
        [System.IO.File]::WriteAllText($p, '')
        Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        return $true
    } catch { return $false }
}

$settings = Load-Settings

# ---------- XAML ----------
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:shell="clr-namespace:System.Windows.Shell;assembly=PresentationFramework"
        Title="Backuper — резервное копирование" Height="800" Width="1120"
        MinHeight="600" MinWidth="900"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None" ResizeMode="CanResize"
        Background="#FF1E1E2E">
    <shell:WindowChrome.WindowChrome>
        <shell:WindowChrome CaptionHeight="46" CornerRadius="8" ResizeBorderThickness="6"
                            GlassFrameThickness="0" UseAeroCaptionButtons="False"/>
    </shell:WindowChrome.WindowChrome>
    <Window.Resources>
        <LinearGradientBrush x:Key="PrimaryBrush" StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#FFA6E3A1" Offset="0"/>
            <GradientStop Color="#FF74C69A" Offset="1"/>
        </LinearGradientBrush>
        <LinearGradientBrush x:Key="SecondaryBrush" StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#FF45475A" Offset="0"/>
            <GradientStop Color="#FF2E3042" Offset="1"/>
        </LinearGradientBrush>
        <LinearGradientBrush x:Key="InfoBrush" StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#FF585B70" Offset="0"/>
            <GradientStop Color="#FF3B3E54" Offset="1"/>
        </LinearGradientBrush>
        <Style TargetType="Button">
            <Setter Property="Background" Value="{StaticResource SecondaryBrush}"/>
            <Setter Property="Foreground" Value="#FFCDD6F4"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="RenderTransformOrigin" Value="0.5,0.5"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}"
                                CornerRadius="8" Padding="{TemplateBinding Padding}">
                            <Border.Effect>
                                <DropShadowEffect Color="#000000" Opacity="0.35" BlurRadius="10" ShadowDepth="2"/>
                            </Border.Effect>
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Opacity" Value="0.88"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="bd" Property="Opacity" Value="0.72"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="bd" Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsPressed" Value="True">
                    <Setter Property="RenderTransform">
                        <Setter.Value><ScaleTransform ScaleX="0.97" ScaleY="0.97"/></Setter.Value>
                    </Setter>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Background" Value="{StaticResource PrimaryBrush}"/>
            <Setter Property="Foreground" Value="#FF11111B"/>
        </Style>
        <Style x:Key="InfoButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Background" Value="{StaticResource InfoBrush}"/>
        </Style>
        <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Background" Value="#FFF38BAB"/>
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
        <Style TargetType="TabItem">
            <Setter Property="Foreground" Value="#FFCDD6F4"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="18,10"/>
            <Setter Property="Background" Value="#FF313244"/>
            <Setter Property="BorderBrush" Value="#FF45475A"/>
            <Setter Property="BorderThickness" Value="1,1,1,0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border x:Name="tabBorder" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="8,8,0,0" Padding="{TemplateBinding Padding}"
                                Margin="0,0,4,0">
                            <ContentPresenter x:Name="content" HorizontalAlignment="Center"
                                              VerticalAlignment="Center"
                                              ContentSource="Header"
                                              TextElement.Foreground="{TemplateBinding Foreground}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="tabBorder" Property="Background" Value="#FF585B70"/>
                                <Setter TargetName="tabBorder" Property="BorderBrush" Value="#FFA6E3A1"/>
                                <Setter TargetName="content" Property="TextElement.Foreground" Value="#FFA6E3A1"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="tabBorder" Property="Background" Value="#FF45475A"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <!-- Кнопки верхней панели окна -->
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

        <!-- Стилизованные ползунки прокрутки -->
        <Style x:Key="ScrollBarPageButton" TargetType="RepeatButton">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RepeatButton">
                        <Border Background="#00000000"/>
                    </ControlTemplate>
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
                    <Track.DecreaseRepeatButton>
                        <RepeatButton Command="ScrollBar.PageUpCommand" Style="{StaticResource ScrollBarPageButton}"/>
                    </Track.DecreaseRepeatButton>
                    <Track.Thumb>
                        <Thumb Style="{StaticResource ScrollBarThumb}"/>
                    </Track.Thumb>
                    <Track.IncreaseRepeatButton>
                        <RepeatButton Command="ScrollBar.PageDownCommand" Style="{StaticResource ScrollBarPageButton}"/>
                    </Track.IncreaseRepeatButton>
                </Track>
            </Grid>
        </ControlTemplate>
        <ControlTemplate x:Key="HorizontalScrollBarTemplate" TargetType="ScrollBar">
            <Grid Background="#FF11111B" Height="13">
                <Track x:Name="PART_Track" Orientation="Horizontal">
                    <Track.DecreaseRepeatButton>
                        <RepeatButton Command="ScrollBar.PageLeftCommand" Style="{StaticResource ScrollBarPageButton}"/>
                    </Track.DecreaseRepeatButton>
                    <Track.Thumb>
                        <Thumb Style="{StaticResource ScrollBarThumb}"/>
                    </Track.Thumb>
                    <Track.IncreaseRepeatButton>
                        <RepeatButton Command="ScrollBar.PageRightCommand" Style="{StaticResource ScrollBarPageButton}"/>
                    </Track.IncreaseRepeatButton>
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

    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header: title on the left, status and window buttons pinned to the RIGHT edge -->
        <Grid Grid.Row="0" Margin="0,0,0,14">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" Orientation="Horizontal">
                <TextBlock Text="Backuper" FontSize="24" FontWeight="Bold" Foreground="#FFA6E3A1"/>
                <TextBlock Text="  |  Локальная копия папки сервера" FontSize="13"
                           Foreground="#FFA9ADC1" VerticalAlignment="Bottom" Margin="0,0,0,4"/>
            </StackPanel>
            <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center"
                        Margin="0,0,16,0">
                <TextBlock x:Name="VersionText" Text="версия 1.3.0" FontSize="12"
                           Foreground="#FF6C7086" VerticalAlignment="Center" Margin="0,0,10,0"/>
                <Button x:Name="BtnCheckUpdate" Content="⟳  Обновить" Width="110" FontSize="12"
                        Style="{StaticResource WindowButton}"
                        ToolTip="Проверить обновления на GitHub"
                        shell:WindowChrome.IsHitTestVisibleInChrome="True"/>
                <TextBlock x:Name="UpdateStatus" Text="" FontSize="11" Foreground="#FF89B4FA"
                           Margin="10,0,0,0" VerticalAlignment="Center"/>
                <Ellipse x:Name="StatusDot" Width="12" Height="12" Fill="#FFA6E3A1" Margin="12,0,8,0"/>
                <TextBlock x:Name="StatusText" Text="Готово" FontSize="13" VerticalAlignment="Center"/>
            </StackPanel>
            <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center"
                        shell:WindowChrome.IsHitTestVisibleInChrome="True">
                <Button x:Name="BtnWindowMin" Content="—" ToolTip="Свернуть в трей"
                        Style="{StaticResource WindowButton}"
                        shell:WindowChrome.IsHitTestVisibleInChrome="True"/>
                <Button x:Name="BtnWindowMax" Content="□" ToolTip="Развернуть / восстановить"
                        Style="{StaticResource WindowButton}"
                        shell:WindowChrome.IsHitTestVisibleInChrome="True"/>
                <Button x:Name="BtnWindowClose" Content="✕" ToolTip="Выйти из программы"
                        Style="{StaticResource WindowCloseButton}"
                        shell:WindowChrome.IsHitTestVisibleInChrome="True"/>
            </StackPanel>
        </Grid>

        <TabControl x:Name="MainTabs" Grid.Row="1" Background="#FF181825" BorderThickness="0">
            <!-- TAB 1: Dashboard -->
            <TabItem Header="Обзор" x:Name="TabDashboard">
                <Grid Margin="0,12,0,0">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <!-- Buttons -->
                    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,14">
                        <Button x:Name="BtnBackup" Content="⟳  Скопировать сейчас" Width="205" Margin="0,0,10,0"
                                Style="{StaticResource PrimaryButton}"/>
                        <Button x:Name="BtnRestore" Content="↩  Восстановить файл" Width="180" Margin="0,0,10,0"
                                Style="{StaticResource InfoButton}"/>
                        <Button x:Name="BtnOpenFolder" Content="📂  Открыть папку копии" Width="195"
                                Style="{StaticResource InfoButton}"/>
                    </StackPanel>

                    <!-- Stats cards -->
                    <Grid Grid.Row="1" Margin="0,0,0,14">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition/>
                            <ColumnDefinition/>
                            <ColumnDefinition/>
                        </Grid.ColumnDefinitions>
                        <Border Background="#FF313244" CornerRadius="8" Padding="14" Margin="0,0,8,0">
                            <StackPanel>
                                <TextBlock Text="ФАЙЛОВ В КОПИИ" FontSize="11" Foreground="#FFA9ADC1"/>
                                <TextBlock x:Name="StatFiles" Text="0" FontSize="26" FontWeight="Bold" Foreground="#FF89B4FA"/>
                            </StackPanel>
                        </Border>
                        <Border Background="#FF313244" CornerRadius="8" Padding="14" Margin="4,0,4,0">
                            <StackPanel>
                                <TextBlock Text="ПРОПАЛО НА СЕРВЕРЕ" FontSize="11" Foreground="#FFA9ADC1"/>
                                <TextBlock x:Name="StatMissing" Text="0" FontSize="26" FontWeight="Bold" Foreground="#FFF38BAB"/>
                            </StackPanel>
                        </Border>
                        <Border Background="#FF313244" CornerRadius="8" Padding="14" Margin="8,0,0,0">
                            <StackPanel>
                                <TextBlock Text="ПОСЛЕДНЕЕ КОПИРОВАНИЕ" FontSize="11" Foreground="#FFA9ADC1"/>
                                <TextBlock x:Name="StatLast" Text="никогда" FontSize="18" FontWeight="Bold" Foreground="#FFA6E3A1"/>
                            </StackPanel>
                        </Border>
                    </Grid>

                    <!-- File list -->
                    <Border Grid.Row="2" Background="#FF181825" CornerRadius="8" Padding="6">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            <TextBlock Grid.Row="0" Text="Файлы в копии:" FontSize="12" Foreground="#FFA9ADC1"
                                       Margin="8,6,0,6"/>
                            <ListBox x:Name="FileList" Grid.Row="1" Background="#FF181825"
                                     BorderBrush="#FF45475A" BorderThickness="1" Foreground="#FFCDD6F4" FontSize="12"
                                     SelectionMode="Extended">
                                <ListBox.ItemTemplate>
                                    <DataTemplate>
                                        <StackPanel Orientation="Horizontal">
                                            <TextBlock Text="  "/>
                                            <TextBlock Text="{Binding Icon}" Foreground="{Binding Color}"/>
                                            <TextBlock Text="{Binding Name}"/>
                                        </StackPanel>
                                    </DataTemplate>
                                </ListBox.ItemTemplate>
                            </ListBox>
                        </Grid>
                    </Border>

                    <GridSplitter Grid.Row="3" Height="6" HorizontalAlignment="Stretch"
                                  VerticalAlignment="Center" Background="#FF45475A" Cursor="SizeNS"/>

                    <!-- Log area (resize with the splitter above) -->
                    <Border Grid.Row="4" Background="#FF11111B" CornerRadius="8" Padding="8" Margin="0,6,0,0"
                            Height="160" MinHeight="90">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            <Grid Grid.Row="0" Margin="0,0,0,6">
                                <TextBlock Text="Лог:" FontSize="11" Foreground="#FF6C7086"
                                           VerticalAlignment="Center"/>
                                <Button x:Name="BtnCopyLogs" Content="⧉  Копировать логи" HorizontalAlignment="Right"
                                        FontSize="10" Padding="6,3" Background="Transparent"
                                        BorderThickness="0" Foreground="#FF89B4FA" Cursor="Hand"
                                        ToolTip="Скопировать содержимое логов в буфер обмена"/>
                            </Grid>
                            < ScrollViewer x:Name="LogScroll" Grid.Row="1" VerticalScrollBarVisibility="Auto">
                                <TextBlock x:Name="LogBox" Text="" FontFamily="Consolas" FontSize="11"
                                           Foreground="#FFA9ADC1" TextWrapping="Wrap"/>
                            </ScrollViewer>
                        </Grid>
                    </Border>
                </Grid>
            </TabItem>

            <!-- TAB 2: Restore -->
            <TabItem Header="Восстановление" x:Name="TabRestore">
                <Grid Margin="0,12,0,0">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Text="Файлы, которые есть в копии, но ОТСУТСТВУЮТ на сервере. Список обновляется автоматически каждые 5 секунд."
                               Foreground="#FFA9ADC1" Margin="0,0,0,10" TextWrapping="Wrap"/>
                    <Grid Grid.Row="1" Margin="0,0,0,8">
                        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                        <TextBlock Text="Поиск:" Foreground="#FFA9ADC1" VerticalAlignment="Center" Margin="0,0,8,0"/>
                        <TextBox x:Name="TxtRestoreSearch" Grid.Column="1" Height="28"
                                 ToolTip="Фильтр по названию файла"/>
                    </Grid>
                    <Border Grid.Row="2" Background="#FF181825" CornerRadius="8" Padding="8">
                        <ListBox x:Name="MissingList" Background="#FF181825" BorderBrush="#FF45475A"
                                 BorderThickness="1" Foreground="#FFCDD6F4" FontSize="13" SelectionMode="Extended"
                                 ToolTip="Можно выбрать несколько файлов: Ctrl+клик или Shift+клик"/>
                    </Border>
                    <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,12,0,0">
                        <Button x:Name="BtnRestoreSelected" Content="↩  Восстановить выбранный файл" Width="240"
                                Margin="0,0,10,0" Style="{StaticResource PrimaryButton}"/>
                        <Button x:Name="BtnRefreshMissing" Content="⟳  Обновить список" Width="170"
                                Style="{StaticResource InfoButton}"/>
                        <Button x:Name="BtnClearMissing" Content="🗑  Очистить" Width="140" Margin="10,0,0,0"
                                Style="{StaticResource DangerButton}"
                                ToolTip="Удалить выбранный файл из копии (на сервере его уже нет)"/>
                    </StackPanel>
                </Grid>
            </TabItem>

            <!-- TAB 3: Versions -->
            <TabItem Header="Версии" x:Name="TabVersions">
                <Grid Margin="0,12,0,0">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Text="Снимки изменений. Раскройте дату:  + добавлен/изменён,  − удалён с сервера. Отметьте чекбоксами несколько строк для пакетного восстановления."
                               Foreground="#FFA9ADC1" Margin="0,0,0,10" TextWrapping="Wrap"/>
                    <Grid Grid.Row="1" Margin="0,0,0,8">
                        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                        <TextBlock Text="Поиск:" Foreground="#FFA9ADC1" VerticalAlignment="Center" Margin="0,0,8,0"/>
                        <TextBox x:Name="TxtVersionSearch" Grid.Column="1" Height="28"
                                 ToolTip="Фильтр по названию файла"/>
                    </Grid>
                    <Border Grid.Row="2" Background="#FF181825" CornerRadius="8" Padding="6">
                        <TreeView x:Name="VersionTree" Background="#FF181825" BorderBrush="#FF45475A"
                                  BorderThickness="1" Foreground="#FFCDD6F4" FontSize="12">
                            <TreeView.ItemContainerStyle>
                                <Style TargetType="TreeViewItem">
                                    <Setter Property="Foreground" Value="#FFCDD6F4"/>
                                </Style>
                            </TreeView.ItemContainerStyle>
                        </TreeView>
                    </Border>
                    <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,12,0,0">
                        <Button x:Name="BtnRestoreVersionToBackup" Content="↩  В копию" Width="140" Margin="0,0,8,0"
                                Style="{StaticResource PrimaryButton}"/>
                        <Button x:Name="BtnRestoreVersionToServer" Content="↩  На сервер" Width="145" Margin="0,0,8,0"
                                Style="{StaticResource InfoButton}"/>
                        <Button x:Name="BtnOpenVersions" Content="📂  Папка версий" Width="155" Margin="0,0,8,0"
                                Style="{StaticResource InfoButton}"/>
                        <Button x:Name="BtnCleanVersions" Content="🧹  Очистить старые" Width="175" Margin="0,0,8,0"
                                Style="{StaticResource InfoButton}"/>
                        <Button x:Name="BtnDeleteSnapshot" Content="🗑  Удалить снимок" Width="170"
                                Style="{StaticResource DangerButton}"/>
                    </StackPanel>
                </Grid>
            </TabItem>

            <!-- TAB 4: Settings -->
            <TabItem Header="Настройки" x:Name="TabSettings">
                <Grid Margin="0,12,0,0">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="160"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <TextBlock Grid.Row="0" Grid.Column="0" Text="Папки источников:" VerticalAlignment="Center"
                               Foreground="#FFA9ADC1"/>
                    <StackPanel Grid.Row="0" Grid.Column="1" Margin="0,4,0,10">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBox x:Name="TxtSource"/>
                            <Button x:Name="BtnPickSource" Grid.Column="1" Content="📁  Выбрать..."
                                    Margin="8,0,0,0" Style="{StaticResource InfoButton}"
                                    ToolTip="Выбрать основную папку источника"/>
                        </Grid>
                        <StackPanel Orientation="Horizontal" Margin="0,6,0,0">
                            <ListBox x:Name="SourceList" Height="66" MinWidth="300" MaxWidth="520"
                                     Background="#FF181825" BorderBrush="#FF45475A" BorderThickness="1"
                                     Foreground="#FFCDD6F4" FontSize="12"/>
                            <StackPanel Margin="8,0,0,0">
                                <Button x:Name="BtnAddSource" Content="＋  Добавить папку" Width="150"
                                        Style="{StaticResource InfoButton}" Margin="0,0,0,4"/>
                                <Button x:Name="BtnRemoveSource" Content="－  Удалить" Width="150"
                                        Style="{StaticResource DangerButton}"/>
                            </StackPanel>
                        </StackPanel>
                        <TextBlock x:Name="SourceSizes" Text="Размер папок: вычисление..."
                                   FontSize="11" Foreground="#FF89B4FA" Margin="0,4,0,0" TextWrapping="Wrap"/>
                        <StackPanel Orientation="Horizontal" Margin="0,6,0,0">
                            <CheckBox x:Name="ChkCompress" Foreground="#FFCDD6F4" FontSize="11"
                                      Content=" Сжимать копии в архивы 7z после копирования"/>
                            <Button x:Name="BtnCompressNow" Content="Сжать в 7z" Width="110" Margin="12,0,0,0"
                                    FontSize="10" Padding="6,3" Style="{StaticResource InfoButton}"
                                    ToolTip="Создать/обновить .7z-архивы для каждой папки копий"/>
                        </StackPanel>
                        <TextBlock Text="Каждая папка копируется в отдельную подпапку в Files."
                                   FontSize="11" Foreground="#FF6C7086" Margin="0,4,0,0"/>
                    </StackPanel>

                    <TextBlock Grid.Row="1" Grid.Column="0" Text="Папка копии:" VerticalAlignment="Center"
                               Foreground="#FFA9ADC1"/>
                    <Grid Grid.Row="1" Grid.Column="1" Margin="0,4,0,10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="TxtDest"/>
                        <Button x:Name="BtnPickDest" Grid.Column="1" Content="📁  Выбрать..."
                                Margin="8,0,0,0" Style="{StaticResource InfoButton}"/>
                    </Grid>

                    <TextBlock Grid.Row="2" Grid.Column="0" Text="Папка логов:" VerticalAlignment="Center"
                               Foreground="#FFA9ADC1"/>
                    <Grid Grid.Row="2" Grid.Column="1" Margin="0,4,0,10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="TxtLogs"/>
                        <Button x:Name="BtnPickLogs" Grid.Column="1" Content="📁  Выбрать..."
                                Margin="8,0,0,0" Style="{StaticResource InfoButton}"/>
                    </Grid>

                    <TextBlock Grid.Row="3" Grid.Column="0" Text="Копировать каждые:" VerticalAlignment="Center"
                               Foreground="#FFA9ADC1"/>
                    <StackPanel Grid.Row="3" Grid.Column="1" Orientation="Horizontal" Margin="0,4,0,10">
                        <TextBox x:Name="TxtInterval" Width="60" Text="2"/>
                        <TextBlock Text="часов" VerticalAlignment="Center" Margin="8,0,0,0" Foreground="#FFA9ADC1"/>
                        <CheckBox x:Name="ChkAuto" Content=" Включить расписание" IsChecked="True"
                                  Margin="30,0,0,0" Foreground="#FFCDD6F4" VerticalAlignment="Center"/>
                    </StackPanel>

                    <TextBlock Grid.Row="4" Grid.Column="0" Text="Хранить логи (дней):" VerticalAlignment="Center"
                               Foreground="#FFA9ADC1"/>
                    <StackPanel Grid.Row="4" Grid.Column="1" Orientation="Horizontal" Margin="0,4,0,10">
                        <TextBox x:Name="TxtLogDays" Width="60" Text="7"/>
                        <TextBlock Text="дней (очистка каждое воскресенье)" VerticalAlignment="Center"
                                   Margin="8,0,0,0" Foreground="#FFA9ADC1"/>
                        <Button x:Name="BtnCleanLogs" Content="🧹  Очистить сейчас" Width="160" Margin="20,0,0,0"
                                Style="{StaticResource InfoButton}"/>
                    </StackPanel>

                    <TextBlock Grid.Row="5" Grid.Column="0" Text="Папка версий:" VerticalAlignment="Center"
                               Foreground="#FFA9ADC1"/>
                    <Grid Grid.Row="5" Grid.Column="1" Margin="0,4,0,10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="TxtVersionsDir"/>
                        <Button x:Name="BtnPickVersions" Grid.Column="1" Content="📁  Выбрать..."
                                Margin="8,0,0,0" Style="{StaticResource InfoButton}"/>
                    </Grid>

                    <TextBlock Grid.Row="6" Grid.Column="0" Text="Хранить версии (дней):" VerticalAlignment="Center"
                               Foreground="#FFA9ADC1"/>
                    <StackPanel Grid.Row="6" Grid.Column="1" Orientation="Horizontal" Margin="0,4,0,10">
                        <TextBox x:Name="TxtVersionDays" Width="60" Text="30"/>
                        <TextBlock Text="дней" VerticalAlignment="Center" Margin="8,0,0,0" Foreground="#FFA9ADC1"/>
                    </StackPanel>

                    <TextBlock Grid.Row="8" Grid.Column="0" Text="Автообновление:" VerticalAlignment="Center"
                               Foreground="#FFA9ADC1"/>
                    <StackPanel Grid.Row="8" Grid.Column="1" Margin="0,4,0,8">
                        <CheckBox x:Name="ChkAutoUpdate" IsChecked="True" Foreground="#FFCDD6F4"
                                  Content=" Разрешить автоматическую установку обновлений с GitHub"/>
                        <TextBlock Text="Если версия не последняя, недостающие файлы будут скачаны и заменены при запуске панели. Ваши настройки, бэкапы, логи и версии сохранятся."
                                   FontSize="11" Foreground="#FF6C7086" Margin="0,4,0,0" TextWrapping="Wrap"/>
                    </StackPanel>

                    <StackPanel Grid.Row="9" Grid.Column="0" Grid.ColumnSpan="2" Orientation="Horizontal"
                                VerticalAlignment="Bottom" Margin="0,0,0,4">
                        <Button x:Name="BtnSaveSettings" Content="💾  Сохранить настройки" Width="200" Margin="0,0,10,0"
                                Style="{StaticResource PrimaryButton}"/>
                        <Button x:Name="BtnInstallTask" Content="⏰  Применить расписание" Width="205"
                                Style="{StaticResource InfoButton}"/>
                    </StackPanel>

                </Grid>
            </TabItem>
        </TabControl>

        <!-- Footer -->
        <TextBlock Grid.Row="2" Text="Backuper  |  Файлы никогда не удаляются из копии.  Сворачивание — в трей, правый клик по иконке — выход."
                   FontSize="11" Foreground="#FF6C7086" Margin="0,12,0,0"/>
    </Grid>
</Window>
'@

# Strip the stray space in "< ScrollViewer"
$xaml = $xaml -replace '< ScrollViewer', '<ScrollViewer'

$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# use our own icon for the window and taskbar instead of PowerShell's
if (Test-Path -LiteralPath $IconFile) {
    try { $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]$IconFile) } catch { }
}

function Find($name) { return $window.FindName($name) }

$btnBackup        = Find 'BtnBackup'
$btnRestore       = Find 'BtnRestore'
$btnOpenFolder    = Find 'BtnOpenFolder'
$btnRestoreSelected = Find 'BtnRestoreSelected'
$btnRefreshMissing = Find 'BtnRefreshMissing'
$btnClearMissing  = Find 'BtnClearMissing'
$btnCopyLogs      = Find 'BtnCopyLogs'
$btnSaveSettings  = Find 'BtnSaveSettings'
$btnInstallTask   = Find 'BtnInstallTask'
$btnCleanLogs     = Find 'BtnCleanLogs'
$btnPickSource    = Find 'BtnPickSource'
$btnPickDest      = Find 'BtnPickDest'
$btnPickLogs      = Find 'BtnPickLogs'
$btnPickVersions  = Find 'BtnPickVersions'
$btnWindowMin     = Find 'BtnWindowMin'
$btnWindowMax     = Find 'BtnWindowMax'
$btnWindowClose   = Find 'BtnWindowClose'
$btnCheckUpdate   = Find 'BtnCheckUpdate'
$versionText      = Find 'VersionText'
$updateStatus     = Find 'UpdateStatus'
$btnRestoreVersionToBackup = Find 'BtnRestoreVersionToBackup'
$btnRestoreVersionToServer = Find 'BtnRestoreVersionToServer'
$btnOpenVersions  = Find 'BtnOpenVersions'
$btnCleanVersions = Find 'BtnCleanVersions'
$btnDeleteSnapshot = Find 'BtnDeleteSnapshot'
$sourceList       = Find 'SourceList'
$btnAddSource     = Find 'BtnAddSource'
$btnRemoveSource  = Find 'BtnRemoveSource'
$txtSource        = Find 'TxtSource'
$txtDest          = Find 'TxtDest'
$txtLogs          = Find 'TxtLogs'
$txtInterval      = Find 'TxtInterval'
$txtLogDays       = Find 'TxtLogDays'
$txtVersionsDir   = Find 'TxtVersionsDir'
$txtVersionDays   = Find 'TxtVersionDays'
$chkAuto          = Find 'ChkAuto'
$chkAutoUpdate    = Find 'ChkAutoUpdate'
$statusDot        = Find 'StatusDot'
$statusText       = Find 'StatusText'
$statFiles        = Find 'StatFiles'
$statMissing      = Find 'StatMissing'
$statLast         = Find 'StatLast'
$fileList         = Find 'FileList'
$missingList      = Find 'MissingList'
$txtRestoreSearch = Find 'TxtRestoreSearch'
$txtVersionSearch = Find 'TxtVersionSearch'
$chkCompress      = Find 'ChkCompress'
$btnCompressNow   = Find 'BtnCompressNow'
$versionTree      = Find 'VersionTree'
$tabRestore       = Find 'TabRestore'
$tabVersions      = Find 'TabVersions'
$tabSettings      = Find 'TabSettings'
$mainTabs         = Find 'MainTabs'
$sourceSizes      = Find 'SourceSizes'
$logBox           = Find 'LogBox'
$logScroll        = Find 'LogScroll'

# ---------- Helpers ----------
function Get-SourceFolderName([string]$path) {
    $name = ($path.TrimEnd('\', '/') -split '[\\/]')[-1]
    if (-not $name) { $name = 'source' }
    return ($name -replace '[<>:"|?*]', '_')
}

function Get-SourcePaths {
    $paths = [System.Collections.Generic.List[string]]::new()
    if ($txtSource.Text) { [void]$paths.Add($txtSource.Text) }
    foreach ($item in $sourceList.Items) {
        $p = [string]$item
        if ($p -and -not $paths.Contains($p)) { [void]$paths.Add($p) }
    }
    if ($paths.Count -eq 0) { [void]$paths.Add($DefaultSettings.Source) }
    return $paths.ToArray()
}

function Apply-RestoreSearch {
    $q = $txtRestoreSearch.Text.Trim()
    $items = if ($q) { @($script:allMissing | Where-Object { $_ -like "*$q*" }) } else { @($script:allMissing) }
    $missingList.Items.Clear()
    foreach ($m in $items) { [void]$missingList.Items.Add($m) }
    $statMissing.Text = "$($items.Count)$(if ($q) { " / $($script:allMissing.Count)" })"
}

$txtRestoreSearch.Add_TextChanged({ Apply-RestoreSearch })
$txtVersionSearch.Add_TextChanged({ Refresh-Versions })

$script:sizeJob = $null
function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { return ([math]::Round($Bytes / 1GB, 2)).ToString().Replace('.', ',') + ' ГБ' }
    if ($Bytes -ge 1MB) { return ([math]::Round($Bytes / 1MB, 1)).ToString().Replace('.', ',') + ' МБ' }
    if ($Bytes -ge 1KB) { return ([math]::Round($Bytes / 1KB, 1)).ToString().Replace('.', ',') + ' КБ' }
    return "$([int]$Bytes) Б"
}

function Update-SourceSizes {
    $paths = @(Get-SourcePaths)
    $used = @{}
    $pairs = [System.Collections.Generic.List[string]]::new()
    foreach ($s in $paths) {
        $n = Get-SourceFolderName $s
        if ($used.ContainsKey($n)) { $used[$n]++; $n = "$n-$($used[$n])" } else { $used[$n] = 1 }
        [void]$pairs.Add("$n|$(Join-Path $txtDest.Text $n)")
    }
    $sourceSizes.Text = 'Размер папок: вычисление...'
    if ($script:sizeJob -and $script:sizeJob.State -eq 'Running') { return }
    try {
        $archiveMode = [bool]$chkCompress.IsChecked
        $script:sizeJob = Start-Job -ScriptBlock {
            param([string[]]$folderPairs, [bool]$archiveMode)
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CompSize {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern uint GetCompressedFileSizeW(string path, out uint high);
}
'@
            $lines = [System.Collections.Generic.List[string]]::new()
            foreach ($pair in $folderPairs) {
                $p = $pair -split '\|', 2
                $name = $p[0]; $path = $p[1]
                $count = 0; $logical = 0.0; $compressed = 0.0
                $indexFile = Join-Path (Split-Path -Parent $path) ((Split-Path -Leaf $path) + '.index.json')
                if ($archiveMode -and (Test-Path -LiteralPath $indexFile)) {
                    try {
                        $idx = Get-Content -LiteralPath $indexFile -Raw -Encoding UTF8 | ConvertFrom-Json
                        foreach ($p in $idx.PSObject.Properties) {
                            $count++
                            $v = [string]$p.Value -split ':', 2
                            if ($v.Length -gt 0) { $logical += [double]$v[0] }
                        }
                    } catch { }
                } else {
                Get-ChildItem -LiteralPath $path -File -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    $count++
                    $logical += $_.Length
                    $hi = [uint32]0
                    $lo = [CompSize]::GetCompressedFileSizeW($_.FullName, [ref]$hi)
                    if ($lo -eq 0xFFFFFFFF -and $hi -eq 0xFFFFFFFF) { $compressed += $_.Length }
                    else { $compressed += ([int64]$hi * 4294967296 + $lo) }
                }
                }
                $archive = Join-Path (Split-Path -Parent $path) ((Split-Path -Leaf $path) + '.7z')
                if (Test-Path -LiteralPath $archive) { $compressed = (Get-Item -LiteralPath $archive).Length }
                [void]$lines.Add("$name|$count|$logical|$compressed")
            }
            return $lines.ToArray()
        } -ArgumentList (, $pairs.ToArray()), $archiveMode
    } catch { $sourceSizes.Text = 'Размер папок: недоступно' }
}

$sizeTimer = New-Object System.Windows.Threading.DispatcherTimer
$sizeTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$sizeTimer.Add_Tick({
    $j = $script:sizeJob
    if (-not $j -or $j.State -eq 'Running') { return }
    try {
        $lines = @(Receive-Job $j)
        $totalCount = 0; $totalBytes = 0.0; $totalComp = 0.0
        $parts = [System.Collections.Generic.List[string]]::new()
        foreach ($line in $lines) {
            $p = [string]$line -split '\|', 4
            if ($p.Count -lt 4) { continue }
            $cnt = [int]$p[1]; $bytes = [double]$p[2]; $comp = [double]$p[3]
            $totalCount += $cnt; $totalBytes += $bytes; $totalComp += $comp
            $ratio = if ($bytes -gt 0) { [int](100 * (1 - $comp / $bytes)) } else { 0 }
            $note = if ($ratio -gt 0) { " → $(Format-Size $comp) (−$ratio%)" } else { ' (без сжатия)' }
            [void]$parts.Add("$($p[0]): $cnt файл., $(Format-Size $bytes)$note")
        }
        if ($parts.Count -gt 0) {
            $allRatio = if ($totalBytes -gt 0) { [int](100 * (1 - $totalComp / $totalBytes)) } else { 0 }
            $allNote = if ($allRatio -gt 0) { " → $(Format-Size $totalComp) (−$allRatio%)" } else { '' }
            $sourceSizes.Text = 'Размер папок: ' + ($parts -join '  •  ') +
                "  |  ВСЕГО: $totalCount файл., $(Format-Size $totalBytes)$allNote"
        } else { $sourceSizes.Text = 'Размер папок: недоступно' }
    } catch { $sourceSizes.Text = 'Размер папок: недоступно' }
    try { Remove-Job $j -Force -ErrorAction SilentlyContinue } catch { }
    $script:sizeJob = $null
})
$sizeTimer.Start()

function Set-Status {
    param([string]$Text, [string]$Color = '#FFA6E3A1')
    $statusText.Text = $Text
    $statusDot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Color)
}

function Append-Log {
    param([string]$Text)
    $logBox.Text += "$Text`n"
    $logScroll.ScrollToEnd()
}

function Get-MissingFiles {
    param([string]$Src, [string]$Dst)
    $res = [System.Collections.Generic.List[string]]::new()
    $used = @{}

    if ($chkCompress.IsChecked) {
        foreach ($s in @(Get-SourcePaths)) {
            $name = Get-SourceFolderName $s
            if ($used.ContainsKey($name)) { $used[$name]++; $name = "$name-$($used[$name])" } else { $used[$name] = 1 }
            $idx = Get-IndexPath -DestRoot $Dst -FolderName $name
            if (-not (Test-Path -LiteralPath $idx)) { continue }
            $sourceSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            if (Test-Path -LiteralPath $s) {
                Get-ChildItem -LiteralPath $s -File -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    [void]$sourceSet.Add($_.FullName.Substring($s.Length).TrimStart('\', '/'))
                }
            }
            try {
                $raw = Get-Content -LiteralPath $idx -Raw -Encoding UTF8 | ConvertFrom-Json
                foreach ($p in $raw.PSObject.Properties) {
                    if (-not $sourceSet.Contains($p.Name)) { [void]$res.Add("$name\$($p.Name)") }
                }
            } catch { }
        }
        return $res.ToArray()
    }
    foreach ($s in @(Get-SourcePaths)) {
        $name = Get-SourceFolderName $s
        if ($used.ContainsKey($name)) { $used[$name]++; $name = "$name-$($used[$name])" } else { $used[$name] = 1 }
        $target = Join-Path $Dst $name
        if (-not (Test-Path -LiteralPath $s)) { continue }
        $sourceSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        Get-ChildItem -LiteralPath $s -File -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            [void]$sourceSet.Add($_.FullName.Substring($s.Length).TrimStart('\', '/'))
        }
        if (Test-Path -LiteralPath $target) {
            Get-ChildItem -LiteralPath $target -File -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                $rel = $_.FullName.Substring($target.Length).TrimStart('\', '/')
                if (-not $sourceSet.Contains($rel)) { [void]$res.Add("$name\$rel") }
            }
        }
    }
    return $res.ToArray()
}

function Refresh-Dashboard {
    Append-Log "Обновление данных..."
    $dst = $txtDest.Text
    $n = 0
    $items = [System.Collections.Generic.List[object]]::new()
    if ($chkCompress.IsChecked) {
        $usedNames = @{}
        foreach ($s in @(Get-SourcePaths)) {
            $name = Get-SourceFolderName $s
            if ($usedNames.ContainsKey($name)) { $usedNames[$name]++; $name = "$name-$($usedNames[$name])" } else { $usedNames[$name] = 1 }
            $idx = Get-IndexPath -DestRoot $dst -FolderName $name
            if (-not (Test-Path -LiteralPath $idx)) { continue }
            try {
                $raw = Get-Content -LiteralPath $idx -Raw -Encoding UTF8 | ConvertFrom-Json
                foreach ($p in $raw.PSObject.Properties) {
                    $n++
                    [void]$items.Add([PSCustomObject]@{ Name = "$name\$($p.Name)"; Icon = [char]0x25A1; Color = '#FF89B4FA' })
                }
            } catch { }
        }
    } elseif (Test-Path -LiteralPath $dst) {
        Get-ChildItem -LiteralPath $dst -File -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $n++
            $rel = $_.FullName.Substring($dst.Length).TrimStart('\', '/')
            [void]$items.Add([PSCustomObject]@{
                Name = $rel
                Icon = [char]0x25A1
                Color = '#FF89B4FA'
            })
        }
    }
    $fileList.ItemsSource = $items
    $statFiles.Text = $n

    $script:allMissing = @(Get-MissingFiles -Src $txtSource.Text -Dst $dst)
    Apply-RestoreSearch

    # last backup time from newest log file
    $last = 'never'
    if (Test-Path -LiteralPath $txtLogs.Text) {
        $newest = Get-ChildItem -LiteralPath $txtLogs.Text -File -Filter 'backup_*.log' -ErrorAction SilentlyContinue |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($newest) { $last = $newest.LastWriteTime.ToString('dd.MM.yyyy HH:mm') }
    }
    $statLast.Text = $last
    Set-Status 'Готово'
    Append-Log "Обновлено. Файлов в копии: $n, пропало на сервере: $($missing.Count)"
    Refresh-Versions
}

$script:checkedVersions = @{}

function Refresh-Versions {
    # remember expanded snapshots and selected file so auto-refresh does not reset the view
    $expanded = @{}
    $selectedKey = ''
    $oldSelected = $versionTree.SelectedItem
    if ($oldSelected -and $oldSelected.Tag -and -not $oldSelected.Tag.IsSnapshot) {
        $selectedKey = "$($oldSelected.Tag.SnapshotPath)|$($oldSelected.Tag.Name)"
    }
    foreach ($item in $versionTree.Items) {
        if ($item -is [System.Windows.Controls.TreeViewItem] -and $item.Tag -and
            $item.Tag.IsSnapshot -and $item.IsExpanded) {
            $expanded[$item.Tag.SnapshotPath] = $true
        }
    }

    $versionTree.Items.Clear()
    $snaps = @(Get-VersionSnapshots -VersionsDir $txtVersionsDir.Text)
    if ($snaps.Count -eq 0) {
        $empty = New-Object System.Windows.Controls.TreeViewItem
        $empty.Header = 'Снимков пока нет. Они появятся здесь после добавления или изменения файлов на сервере.'
        $empty.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#FF6C7086')
        [void]$versionTree.Items.Add($empty)
        return
    }

    $first = $true
    $vq = $txtVersionSearch.Text.Trim()
    foreach ($s in $snaps) {
        $visibleChanges = if ($vq) { @($s.Changes | Where-Object { $_.Name -like "*$vq*" }) } else { @($s.Changes) }
        if ($vq -and $visibleChanges.Count -eq 0) { continue }
        $node = New-Object System.Windows.Controls.TreeViewItem
        $node.Header = "$($s.When.ToString('dd.MM.yyyy HH:mm'))   $($s.Name)"
        $node.Tag = [PSCustomObject]@{ SnapshotPath = $s.Path; IsSnapshot = $true }
        $node.IsExpanded = ($first -or $expanded.ContainsKey($s.Path))
        foreach ($c in $visibleChanges) {
            $child = New-Object System.Windows.Controls.TreeViewItem
            $tag = [PSCustomObject]@{
                SnapshotPath = $s.Path
                Name         = $c.Name
                Sign         = $c.Sign
                Time         = $c.Time
                IsSnapshot   = $false
            }
            $child.Tag = $tag
            $key = "$($s.Path)|$($c.Name)"
            $color = if ($c.Sign -eq '+') { '#FFA6E3A1' } else { '#FFF38BAB' }

            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = "$($c.Sign) $($c.Time)   $($c.Name)"
            $cb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)
            $cb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            $cb.Tag = $tag
            $cb.IsChecked = $script:checkedVersions.ContainsKey($key)
            $cb.add_Checked({
                $t = $this.Tag
                $script:checkedVersions["$($t.SnapshotPath)|$($t.Name)"] = $t
            })
            $cb.add_Unchecked({
                $t = $this.Tag
                $script:checkedVersions.Remove("$($t.SnapshotPath)|$($t.Name)") | Out-Null
            })
            $child.Header = $cb
            if ($selectedKey -eq $key) { $child.IsSelected = $true }
            [void]$node.Items.Add($child)
        }
        [void]$versionTree.Items.Add($node)
        $first = $false
    }
}

function Select-Folder {
    param([string]$Title, [string]$Initial)
    # Only the modern Explorer-style dialog. No legacy dialog is ever opened.
    $modern = Select-ModernFolder -Title $Title
    if ($modern) { return $modern }
    if ($script:FolderPickerError) {
        [System.Windows.MessageBox]::Show(
            "Не удалось открыть диалог выбора папки:`n$($script:FolderPickerError)",
            'Ошибка', 'OK', 'Error')
    }
    return $null
}

# ---------- Events ----------
$btnAddSource.Add_Click({
    $p = Select-Folder -Title 'Добавить ещё одну папку источника' -Initial ''
    if (-not $p) { return }
    $existing = @(Get-SourcePaths)
    if ($existing -contains $p) {
        [System.Windows.MessageBox]::Show('Эта папка уже добавлена.', 'Backuper', 'OK', 'Information')
        return
    }
    [void]$sourceList.Items.Add($p)
    Append-Log "Добавлена папка источника: $p"
    Update-SourceSizes
})

$btnRemoveSource.Add_Click({
    $sel = $sourceList.SelectedItem
    if (-not $sel) {
        [System.Windows.MessageBox]::Show('Выберите папку в списке.', 'Backuper', 'OK', 'Information')
        return
    }
    [void]$sourceList.Items.Remove($sel)
    Append-Log "Удалена папка источника: $sel"
    Update-SourceSizes
})

$btnPickSource.Add_Click({
    $p = Select-Folder -Title 'Выберите папку источника (сетевой путь можно вставить в диалоге)' -Initial $txtSource.Text
    if ($p) {
        $txtSource.Text = $p
        Append-Log "Источник выбран: $p"
        Update-SourceSizes
        Refresh-Dashboard
        $apply = [System.Windows.MessageBox]::Show(
            "Источник изменён:`n$p`n`nПрименить его для автоматического копирования сейчас?",
            'Backuper', 'YesNo', 'Question')
        if ($apply -eq 'Yes') {
            $btnInstallTask.RaiseEvent([System.Windows.RoutedEventArgs]::new(
                [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        }
    }
})

$btnPickDest.Add_Click({
    $p = Select-Folder -Title 'Выберите папку для копий' -Initial $txtDest.Text
    if ($p) {
        $txtDest.Text = $p
        Append-Log "Папка копии выбрана: $p"
        Refresh-Dashboard
    }
})

$btnPickLogs.Add_Click({
    $p = Select-Folder -Title 'Выберите папку для логов' -Initial $txtLogs.Text
    if ($p) {
        $txtLogs.Text = $p
        Append-Log "Папка логов выбрана: $p"
    }
})

$btnPickVersions.Add_Click({
    $p = Select-Folder -Title 'Выберите папку для версий' -Initial $txtVersionsDir.Text
    if ($p) {
        $txtVersionsDir.Text = $p
        Append-Log "Папка версий выбрана: $p"
        Refresh-Versions
    }
})

$btnBackup.Add_Click({
    $btnBackup.IsEnabled = $false
    try {
        Set-Status 'Копирование...' '#FF89B4FA'
        Append-Log "Копирование из $($txtSource.Text) ..."
        $window.Dispatcher.Invoke([Action]{}, 'Normal')

        # synchronous call: no background job, so a failure can never kill the window
        $paths = @(Get-SourcePaths)
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $BackupCore,
                     '-Destination', $txtDest.Text, '-LogDir', $txtLogs.Text,
                     '-VersionsDir', $txtVersionsDir.Text,
                     '-Sources', ($paths -join '|'))
        if ($chkCompress.IsChecked) { $argList += '-Compress' }
        $out = & powershell.exe @argList 2>&1 | Out-String

        $r = $out | ConvertFrom-Json
        foreach ($m in $r.Messages) { Append-Log $m }
        if ($r.Ok) {
            Set-Status "Готово. Скопировано: $($r.Copied)" '#FFA6E3A1'
            Append-Log "Успешно. Скопировано файлов: $($r.Copied). Пропавших на сервере: $($r.MissingCount)"
        } else {
            Set-Status 'Ошибка' '#FFF38BAB'
            Append-Log "ОШИБКА: $($r.Error)"
        }
    } catch {
        Set-Status 'Ошибка' '#FFF38BAB'
        Append-Log "ОШИБКА копирования: $($_.Exception.Message)"
    } finally {
        Refresh-Dashboard
        $btnBackup.IsEnabled = $true
    }
})

$btnCopyLogs.Add_Click({
    try {
        $sb = [System.Text.StringBuilder]::new()
        $files = @(Get-ChildItem -LiteralPath $txtLogs.Text -File -ErrorAction SilentlyContinue |
                   Where-Object { $_.Extension -eq '.log' } | Sort-Object LastWriteTime -Descending)
        foreach ($f in $files) {
            [void]$sb.AppendLine("===== $($f.Name) =====")
            $lines = @(Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)
            $start = [Math]::Max(0, $lines.Count - 300)
            for ($i = $start; $i -lt $lines.Count; $i++) { [void]$sb.AppendLine($lines[$i]) }
            [void]$sb.AppendLine()
        }
        if ($sb.Length -eq 0) { [void]$sb.AppendLine('Логи пока пусты.') }
        [System.Windows.Forms.Clipboard]::SetText($sb.ToString())
        Append-Log "Логи скопированы в буфер обмена ($($files.Count) файл.)."
    } catch {
        [System.Windows.MessageBox]::Show("Не удалось скопировать логи: $($_.Exception.Message)", 'Ошибка', 'OK', 'Error')
    }
})

$script:compressJob = $null
$compressTimer = New-Object System.Windows.Threading.DispatcherTimer
$compressTimer.Interval = [TimeSpan]::FromSeconds(2)
$compressTimer.Add_Tick({
    $j = $script:compressJob
    if (-not $j -or $j.State -eq 'Running') { return }
    $compressTimer.Stop()
    try { $out = Receive-Job $j } catch { $out = '' }
    try { Remove-Job $j -Force -ErrorAction SilentlyContinue } catch { }
    $script:compressJob = $null
    foreach ($line in @($out)) { if ($line) { Append-Log $line } }
    Append-Log "Архивация завершена."
    Update-SourceSizes
})

$btnCompressNow.Add_Click({
    $btnCompressNow.IsEnabled = $false
    Append-Log 'Архивация копий в 7z запущена...'
    $srcPaths = @(Get-SourcePaths)
    $script:compressJob = Start-Job -ScriptBlock {
        param([string]$module, [string]$dest, [string[]]$srcs)
        . $module
        $out = [System.Collections.Generic.List[string]]::new()
        $used = @{}
        foreach ($s in $srcs) {
            $name = ($s.TrimEnd('\', '/') -split '[\\/]')[-1]
            if ($used.ContainsKey($name)) { $used[$name]++; $name = "$name-$($used[$name])" } else { $used[$name] = 1 }
            $archive = Get-ArchivePath -DestRoot $dest -FolderName $name
            $idxFile = Get-IndexPath -DestRoot $dest -FolderName $name
            [void]$out.Add("Архивация: $name")
            foreach ($l in @(Update-ArchiveFromFolder -Archive $archive -SourceFolder $s)) { [void]$out.Add("  $l") }
            $idx = [ordered]@{}
            if (Test-Path -LiteralPath $s) {
                Get-ChildItem -LiteralPath $s -File -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    $rel = $_.FullName.Substring($s.Length).TrimStart('\', '/')
                    $idx[$rel] = "$($_.Length):$($_.LastWriteTimeUtc.Ticks)"
                }
            }
            $idx | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $idxFile -Encoding UTF8
        }
        return $out.ToArray()
    } -ArgumentList $Archive7zModule, $txtDest.Text, $srcPaths
    $compressTimer.Start()
    $btnCompressNow.IsEnabled = $true
})

$btnRefreshMissing.Add_Click({ Refresh-Dashboard })

$btnClearMissing.Add_Click({
    $items = @($missingList.SelectedItems)
    if ($items.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Сначала выберите один или несколько файлов (Ctrl/Shift+клик).', 'Backuper', 'OK', 'Information')
        return
    }
    $list = ($items | ForEach-Object { "  $_" }) -join "`n"
    $res = [System.Windows.MessageBox]::Show(
        "Удалить выбранные файлы из копии?`n`n$list`n`nНа сервере их уже нет — из резервной копии они будут удалены безвозвратно.",
        'Подтверждение очистки', 'YesNo', 'Question')
    if ($res -ne 'Yes') { return }
    $done = 0
    foreach ($sel in $items) {
        try {
            $path = Join-Path $txtDest.Text ([string]$sel)
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force; $done++ }
            Append-Log "ОЧИЩЕНО: $sel"
        } catch {
            Append-Log "Ошибка очистки $sel : $($_.Exception.Message)"
        }
    }
    Refresh-Dashboard
})

$btnRestore.Add_Click({ Refresh-Dashboard; $tab = Find 'TabRestore'; $tab.IsSelected = $true })

$btnRestoreSelected.Add_Click({
    $items = @($missingList.SelectedItems)
    if ($items.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Сначала выберите один или несколько файлов (Ctrl/Shift+клик).', 'Backuper',
            'OK', 'Information')
        return
    }
    $list = ($items | ForEach-Object { "  $_" }) -join "`n"
    $res = [System.Windows.MessageBox]::Show("Восстановить выбранные файлы на сервере?`n`n$list",
        'Подтверждение восстановления', 'YesNo', 'Question')
    if ($res -ne 'Yes') { return }

    $done = 0
    foreach ($sel in $items) {
        # $sel looks like "FolderName\relative\path" - map back to the right source
        $parts = [string]$sel -split '[\\/]', 2
        $folderName = $parts[0]
        $relPath = if ($parts.Count -gt 1) { $parts[1] } else { '' }
        $src = $txtSource.Text
        foreach ($s in @(Get-SourcePaths)) {
            if ((Get-SourceFolderName $s) -eq $folderName) { $src = $s; break }
        }
        $target = if ($relPath) { Join-Path $src $relPath } else { $src }
        try {
            $dir = Split-Path -Parent $target
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            if ($chkCompress.IsChecked) {
                $archive = Get-ArchivePath -DestRoot $txtDest.Text -FolderName $folderName
                Extract-ArchiveFile -Archive $archive -EntryPath $relPath -TargetPath $target | Out-Null
            } else {
                $backupFile = Join-Path $txtDest.Text ([string]$sel)
                if (-not (Test-Path -LiteralPath $backupFile)) {
                    Append-Log "НЕ НАЙДЕН ФАЙЛ КОПИИ: $backupFile"
                    continue
                }
                Copy-Item -LiteralPath $backupFile -Destination $target -Force
            }
            $done++
            Append-Log "ВОССТАНОВЛЕНО: $sel → $target"
        } catch {
            Append-Log "Ошибка восстановления $sel : $($_.Exception.Message)"
        }
    }
    Set-Status "Восстановлено: $done" '#FFA6E3A1'
    Refresh-Dashboard
})

$btnOpenFolder.Add_Click({
    $p = $txtDest.Text
    if (Test-Path -LiteralPath $p) { Start-Process explorer.exe $p }
    else { [System.Windows.MessageBox]::Show("Папка не найдена:`n$p", 'Backuper', 'OK', 'Warning') }
})

$btnCleanLogs.Add_Click({
    $days = [int]$txtLogDays.Text
    if ($days -lt 1) { $days = 1 }
    try {
        $vdays = [int]$txtVersionDays.Text
        if ($vdays -lt 1) { $vdays = 1 }
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $BaseDir 'CleanLogs.ps1') `
            -LogDir $txtLogs.Text -RetentionDays $days -VersionsDir $txtVersionsDir.Text -VersionRetentionDays $vdays 2>&1
        Append-Log ($out -join ' ')
        [System.Windows.MessageBox]::Show(($out -join "`n"), 'Backuper: очистка логов', 'OK', 'Information')
    } catch {
        [System.Windows.MessageBox]::Show("Ошибка очистки:`n$($_.Exception.Message)", 'Ошибка', 'OK', 'Error')
    }
})

function Get-SelectedVersions {
    $items = @($script:checkedVersions.Values)
    if ($items.Count -gt 0) { return $items }
    $item = $versionTree.SelectedItem
    if ($item -and $item.Tag -and -not $item.Tag.IsSnapshot) { return @($item.Tag) }
    return @()
}

$btnRestoreVersionToBackup.Add_Click({
    $items = @(Get-SelectedVersions)
    if ($items.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Отметьте одну или несколько строк файлов в дереве снимков.', 'Backuper', 'OK', 'Information')
        return
    }
    $list = ($items | ForEach-Object { "  $($_.Sign) $($_.Time)  $($_.Name)" }) -join "`n"
    $res = [System.Windows.MessageBox]::Show("Заменить текущие копии выбранными версиями?`n`n$list", 'Подтверждение', 'YesNo', 'Question')
    if ($res -ne 'Yes') { return }
    $done = 0
    foreach ($v in $items) {
        $src = Join-Path $v.SnapshotPath $v.Name
        if (-not (Test-Path -LiteralPath $src)) { $src = Join-Path $txtDest.Text $v.Name }
        $target = Join-Path $txtDest.Text $v.Name
        try {
            if (-not (Test-Path -LiteralPath $src)) { Append-Log "НЕТ ФАЙЛА ВЕРСИИ: $src"; continue }
            $dir = Split-Path -Parent $target
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            Copy-Item -LiteralPath $src -Destination $target -Force
            $done++
            Append-Log "ВЕРСИЯ → КОПИЯ: $($v.Sign) $($v.Time) $($v.Name)"
        } catch { Append-Log "Ошибка: $($_.Exception.Message)" }
    }
    Set-Status "Восстановлено в копию: $done" '#FFA6E3A1'
    Refresh-Dashboard
})

$btnRestoreVersionToServer.Add_Click({
    $items = @(Get-SelectedVersions)
    if ($items.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Отметьте одну или несколько строк файлов в дереве снимков.', 'Backuper', 'OK', 'Information')
        return
    }
    $list = ($items | ForEach-Object { "  $($_.Sign) $($_.Time)  $($_.Name)" }) -join "`n"
    $res = [System.Windows.MessageBox]::Show("Восстановить выбранные версии на СЕРВЕР?`n`n$list", 'Подтверждение восстановления', 'YesNo', 'Question')
    if ($res -ne 'Yes') { return }
    $done = 0
    foreach ($v in $items) {
        $src = Join-Path $v.SnapshotPath $v.Name
        if (-not (Test-Path -LiteralPath $src)) { $src = Join-Path $txtDest.Text $v.Name }
        $vparts = [string]$v.Name -split '[\\/]', 2
        $folderName = $vparts[0]
        $relPath = if ($vparts.Count -gt 1) { $vparts[1] } else { [string]$v.Name }
        $srcRoot = $txtSource.Text
        foreach ($s in @(Get-SourcePaths)) {
            if ((Get-SourceFolderName $s) -eq $folderName) { $srcRoot = $s; break }
        }
        $target = Join-Path $srcRoot $relPath
        try {
            if (-not (Test-Path -LiteralPath $src)) { Append-Log "НЕТ ФАЙЛА ВЕРСИИ: $src"; continue }
            $dir = Split-Path -Parent $target
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            Copy-Item -LiteralPath $src -Destination $target -Force
            $done++
            Append-Log "ВЕРСИЯ → СЕРВЕР: $($v.Sign) $($v.Time) $($v.Name)"
        } catch { Append-Log "Ошибка: $($_.Exception.Message)" }
    }
    Set-Status "Восстановлено на сервере: $done" '#FFA6E3A1'
    Refresh-Dashboard
})

$btnOpenVersions.Add_Click({
    $p = $txtVersionsDir.Text
    if (Test-Path -LiteralPath $p) { Start-Process explorer.exe $p }
    else { [System.Windows.MessageBox]::Show("Папка не найдена:`n$p", 'Backuper', 'OK', 'Warning') }
})

$btnCleanVersions.Add_Click({
    $vdays = [int]$txtVersionDays.Text
    if ($vdays -lt 1) { $vdays = 1 }
    try {
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $BaseDir 'CleanLogs.ps1') `
            -LogDir $txtLogs.Text -RetentionDays ([int]$txtLogDays.Text) `
            -VersionsDir $txtVersionsDir.Text -VersionRetentionDays $vdays 2>&1
        Append-Log ($out -join ' ')
        [System.Windows.MessageBox]::Show(($out -join "`n"), 'Backuper: очистка версий', 'OK', 'Information')
        Refresh-Versions
    } catch {
        [System.Windows.MessageBox]::Show("Ошибка очистки:`n$($_.Exception.Message)", 'Ошибка', 'OK', 'Error')
    }
})

$btnDeleteSnapshot.Add_Click({
    $item = $versionTree.SelectedItem
    if (-not $item -or -not $item.Tag) {
        [System.Windows.MessageBox]::Show('Сначала выберите снимок.', 'Backuper', 'OK', 'Information')
        return
    }
    $path = $item.Tag.SnapshotPath
    $res = [System.Windows.MessageBox]::Show("Удалить этот снимок и все его версии?`n`n$path", 'Подтверждение', 'YesNo', 'Question')
    if ($res -ne 'Yes') { return }
    try {
        Remove-Item -LiteralPath $path -Recurse -Force
        Append-Log "СНИМОК УДАЛЁН: $path"
        Refresh-Versions
    } catch {
        [System.Windows.MessageBox]::Show("Ошибка: $($_.Exception.Message)", 'Ошибка', 'OK', 'Error')
    }
})

$btnSaveSettings.Add_Click({
    $settings.Source      = $txtSource.Text
    $settings.Sources     = @(Get-SourcePaths)
    $settings.Destination = $txtDest.Text
    $settings.LogDir      = $txtLogs.Text
    $settings.IntervalHours = [int]$txtInterval.Text
    $settings.LogRetentionDays = [int]$txtLogDays.Text
    $settings.VersionsDir = $txtVersionsDir.Text
    $settings.VersionRetentionDays = [int]$txtVersionDays.Text
    $settings.AutoRunEnabled = [bool]$chkAuto.IsChecked
    $settings.AutoUpdateEnabled = [bool]$chkAutoUpdate.IsChecked
    $settings.CompressEnabled = [bool]$chkCompress.IsChecked
    Save-Settings $settings
    Append-Log 'Настройки сохранены.'
    Set-Status 'Настройки сохранены' '#FFA6E3A1'
    if ($chkAutoUpdate.IsChecked) {
        $updateStatus.Text = 'проверка обновлений...'
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $BaseDir 'UpdateWindow.ps1'),
            '-InstallDir', $BaseDir, '-AutoClose'
        )
    }
})

$btnInstallTask.Add_Click({
    $hours = [int]$txtInterval.Text
    if ($hours -lt 1) { $hours = 1 }
    $days = [int]$txtLogDays.Text
    if ($days -lt 1) { $days = 1 }
    $vdays = [int]$txtVersionDays.Text
    if ($vdays -lt 1) { $vdays = 1 }
    $vdir = $txtVersionsDir.Text
    try {
        $dir = $BaseDir
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument ("-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dir\Backup.ps1`" " +
                "-Sources `"" + ((@(Get-SourcePaths)) -join '|') + "`" " +
                " -Destination `"$($txtDest.Text)`" -LogDir `"$($txtLogs.Text)`" -LogRetentionDays $days -VersionsDir `"$vdir`"" +
                $(if ($chkCompress.IsChecked) { ' -Compress' } else { '' })) `
            -WorkingDirectory $dir
        $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddHours($hours)) `
            -RepetitionInterval (New-TimeSpan -Hours $hours) -RepetitionDuration (New-TimeSpan -Days 3650)
        $logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $taskSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 15) `
            -StartWhenAvailable -MultipleInstances IgnoreNew
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
        Unregister-ScheduledTask -TaskName 'BackuperHourly' -Confirm:$false -ErrorAction SilentlyContinue
        Register-ScheduledTask -TaskName 'BackuperHourly' -Action $action -Trigger @($trigger, $logonTrigger) `
            -Settings $taskSettings -Principal $principal -Description 'Backuper: automatic copy + notification' | Out-Null
        # make sure the live watcher is running too
        try {
            Stop-ScheduledTask -TaskName 'BackuperWatcher' -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            Start-ScheduledTask -TaskName 'BackuperWatcher' -ErrorAction SilentlyContinue
        } catch { }

        # Weekly log cleanup, Sunday 23:00
        $cleanAction = New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dir\CleanLogs.ps1`" -LogDir `"$($txtLogs.Text)`" -RetentionDays $days -VersionsDir `"$vdir`" -VersionRetentionDays $vdays" `
            -WorkingDirectory $dir
        $weekly = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 23:00
        $cleanSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
            -StartWhenAvailable -MultipleInstances IgnoreNew
        $cleanPrincipal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
        Unregister-ScheduledTask -TaskName 'BackuperLogCleanup' -Confirm:$false -ErrorAction SilentlyContinue
        Register-ScheduledTask -TaskName 'BackuperLogCleanup' -Action $cleanAction -Trigger $weekly `
            -Settings $cleanSettings -Principal $cleanPrincipal -Description 'Backuper: weekly log cleanup' | Out-Null

        # panel autorun at logon (straight into tray)
        $startAction = New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dir\BackuperStart.ps1`"" `
            -WorkingDirectory $dir
        $startTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $startSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
        Unregister-ScheduledTask -TaskName 'BackuperStartup' -Confirm:$false -ErrorAction SilentlyContinue
        Register-ScheduledTask -TaskName 'BackuperStartup' -Action $startAction -Trigger $startTrigger `
            -Settings $startSettings -Principal $principal -Description 'Backuper: панель при входе в Windows' | Out-Null

        Append-Log "Задача установлена: копирование каждые $hours ч. + при входе. Логи: $days дн., версии: $vdays дн., очистка по воскресеньям. Слежение перезапущено."
        [System.Windows.MessageBox]::Show("Задача установлена.`nКопирование каждые $hours ч.`nЛоги старше $days дн. и версии старше $vdays дн. удаляются по воскресеньям.",
            'Backuper', 'OK', 'Information')
    } catch {
        [System.Windows.MessageBox]::Show("Ошибка установки задачи:`n$($_.Exception.Message)",
            'Ошибка', 'OK', 'Error')
    }
})

# ---------- Init ----------
$sourceList.Items.Clear()
if ($settings.Sources -and $settings.Sources.Count -gt 1) {
    $txtSource.Text = $settings.Sources[0]
    foreach ($s in ($settings.Sources | Select-Object -Skip 1)) { [void]$sourceList.Items.Add([string]$s) }
} else {
    $txtSource.Text = $settings.Source
}
$txtDest.Text   = $settings.Destination
$txtLogs.Text   = $settings.LogDir
$txtVersionsDir.Text = $settings.VersionsDir
# non-elevated panel cannot write into Program Files - switch to user profile
if (-not (Test-Writable $txtDest.Text)) { $txtDest.Text = Join-Path $UserRoot 'Files' }
if (-not (Test-Writable $txtLogs.Text)) { $txtLogs.Text = Join-Path $UserRoot 'Logs' }
if (-not (Test-Writable $txtVersionsDir.Text)) { $txtVersionsDir.Text = Join-Path $UserRoot 'Versions' }
$txtInterval.Text = $settings.IntervalHours
$txtLogDays.Text = $settings.LogRetentionDays
$txtVersionDays.Text = $settings.VersionRetentionDays
$chkAuto.IsChecked = $settings.AutoRunEnabled
$chkAutoUpdate.IsChecked = [bool]$settings.AutoUpdateEnabled
$chkCompress.IsChecked = [bool]$settings.CompressEnabled
$mainTabs.Add_SelectionChanged({ if ($mainTabs.SelectedItem -eq $tabSettings) { Update-SourceSizes } })
Update-SourceSizes

$vf = Join-Path $BaseDir 'version.json'
if (Test-Path -LiteralPath $vf) {
    try { $versionText.Text = 'версия ' + ((Get-Content -LiteralPath $vf -Raw -Encoding UTF8 | ConvertFrom-Json).Version) } catch { }
}

$btnCheckUpdate.Add_Click({
    try {
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $BaseDir 'UpdateWindow.ps1'),
            '-InstallDir', $BaseDir
        )
        $updateStatus.Text = 'проверка обновлений...'
        Append-Log 'Открыто окно обновления.'
    } catch {
        [System.Windows.MessageBox]::Show("Ошибка запуска обновления:`n$($_.Exception.Message)",
            'Ошибка', 'OK', 'Error')
    }
})

Append-Log "Backuper запущен. $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Refresh-Dashboard

# ---------- Custom title bar buttons ----------
$btnWindowMin.Add_Click({
    $window.WindowState = [System.Windows.WindowState]::Minimized
})
$btnWindowMax.Add_Click({
    if ($window.WindowState -eq [System.Windows.WindowState]::Maximized) {
        $window.WindowState = [System.Windows.WindowState]::Normal
    } else {
        $window.WindowState = [System.Windows.WindowState]::Maximized
    }
})
$btnWindowClose.Add_Click({
    # X = quit the application completely (minus button sends it to tray)
    $script:reallyExit = $true
    try { $window.Close() } catch { }
    $window.Dispatcher.InvokeShutdown()
})

# ---------- Auto-refresh of Restore and Versions lists (every 5 s) ----------
$autoTimer = New-Object System.Windows.Threading.DispatcherTimer
$autoTimer.Interval = [TimeSpan]::FromSeconds(5)
$autoTimer.Add_Tick({
    try {
        if ($tabRestore.IsSelected) {
            Refresh-Dashboard
        } elseif ($tabVersions.IsSelected) {
            Refresh-Versions
        }
    } catch { }
})
$autoTimer.Start()

# ---------- Silent update check on every launch (background job) ----------
$script:updateCheckJob = $null
$script:updateCheckDone = $false
$script:autoUpdateInProgress = $false
$script:checkDots = 0
$updateStatus.Text = 'проверка обновлений...'
try {
    $script:updateCheckJob = Start-Job -ScriptBlock {
        param($base)
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $base 'Update.ps1') `
            -Check -InstallDir $base 2>&1 | Out-String
    } -ArgumentList $BaseDir
} catch { }

$updateTimer = New-Object System.Windows.Threading.DispatcherTimer
$updateTimer.Interval = [TimeSpan]::FromMilliseconds(600)
$updateTimer.Add_Tick({
    if (-not $script:updateCheckJob -or $script:updateCheckDone) { return }
    if ($script:updateCheckJob.State -eq 'Running') {
        $script:checkDots = ($script:checkDots + 1) % 4
        $updateStatus.Text = 'проверка обновлений' + ('.' * $script:checkDots)
        return
    }
    $script:updateCheckDone = $true
    $updateTimer.Stop()
    try {
        $res = Receive-Job $script:updateCheckJob
        $text = ($res | Out-String).Trim()
        if ($text -match 'Доступна версия\s+(\S+)') {
            $newVer = $Matches[1]
            if ($chkAutoUpdate.IsChecked) {
                Append-Log "Доступна версия $newVer. Автообновление включено - открываю окно обновления."
                $updateStatus.Text = 'установка обновления...'
                Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
                    '-NoProfile', '-ExecutionPolicy', 'Bypass',
                    '-File', (Join-Path $BaseDir 'UpdateWindow.ps1'),
                    '-InstallDir', $BaseDir, '-AutoClose'
                )
            } else {
                $updateStatus.Text = "доступна версия $newVer"
                $versionText.Text = "версия $currentVersion  •  доступна $newVer"
                $versionText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#FFF38BAB')
                Append-Log "Доступна версия $newVer. Включите автообновление или нажмите «Обновить»."
                if ($trayIcon) {
                    $trayIcon.ShowBalloonTip(10000, 'Backuper: обновление',
                        "Доступна версия $newVer", [System.Windows.Forms.ToolTipIcon]::Info)
                }
            }
        } else {
            $updateStatus.Text = 'версия актуальна'
            Append-Log "Проверка обновлений при запуске: $text"
        }
    } catch { }
    try { Remove-Job $script:updateCheckJob -Force -ErrorAction SilentlyContinue } catch { }
})
$updateTimer.Start()

# ---------- System tray ----------
$script:reallyExit = $false

$trayIcon = New-Object System.Windows.Forms.NotifyIcon
if (Test-Path -LiteralPath $IconFile) {
    try { $trayIcon.Icon = New-Object System.Drawing.Icon($IconFile) }
    catch { $trayIcon.Icon = [System.Drawing.SystemIcons]::Application }
} else {
    $trayIcon.Icon = [System.Drawing.SystemIcons]::Application
}
$trayIcon.Text = 'Backuper — резервное копирование'
$trayIcon.Visible = $true

function Show-Window {
    $window.Show()
    $window.WindowState = [System.Windows.WindowState]::Normal
    $window.Activate()
}

$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$miOpen = $trayMenu.Items.Add('Открыть панель')
$miCopy = $trayMenu.Items.Add('Копировать сейчас')
[void]$trayMenu.Items.Add('-')
$miExit = $trayMenu.Items.Add('Выход')

$miOpen.add_Click({ Show-Window })
$miCopy.add_Click({
    # Reuse the same Copy-now handler even when the window is hidden
    $btnBackup.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
})
$miExit.add_Click({
    $script:reallyExit = $true
    try { $window.Close() } catch { }
    $window.Dispatcher.InvokeShutdown()
})
$trayIcon.ContextMenuStrip = $trayMenu
# open the panel on a single click as well as a double click
$trayIcon.add_Click({ Show-Window })
$trayIcon.add_MouseDoubleClick({ Show-Window })

# Minimize button -> hide completely (tray only)
$window.add_StateChanged({
    if ($window.WindowState -eq [System.Windows.WindowState]::Minimized) {
        $window.Hide()
    }
})

# Close button -> also hide into tray; real exit is via tray menu
$window.add_Closing({
    param($sender, $e)
    if (-not $script:reallyExit) {
        $e.Cancel = $true
        $window.Hide()
    }
})

# Show() + our own dispatcher loop: hiding the window must NOT end the process,
# otherwise the tray icon disappears.
$window.Show()
if ($Minimized) { $window.WindowState = [System.Windows.WindowState]::Minimized }
try {
    # make sure the window is fully visible on the primary screen
    $workArea = [System.Windows.SystemParameters]::WorkArea
    $window.Left = $workArea.Left + ($workArea.Width - $window.ActualWidth) / 2
    $window.Top  = $workArea.Top + ($workArea.Height - $window.ActualHeight) / 2
    [System.Windows.Threading.Dispatcher]::Run()
} finally {
    $autoTimer.Stop()
    $trayIcon.Visible = $false
    $trayIcon.Dispose()
    $trayMenu.Dispose()
}

