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
$SettingsFile = Join-Path $BaseDir 'settings.json'
$IconFile     = Join-Path $BaseDir 'app_icon_v2.ico'
. $VersionsModule
. $FolderPickerModule

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
}

function Load-Settings {
    if (Test-Path -LiteralPath $SettingsFile) {
        try {
            $s = Get-Content -LiteralPath $SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
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
    $Settings | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $SettingsFile -Encoding UTF8
}

$settings = Load-Settings

# ---------- XAML ----------
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:shell="clr-namespace:System.Windows.Shell;assembly=PresentationFramework"
        Title="Backuper — резервное копирование" Height="620" Width="900"
        MinHeight="480" MinWidth="700"
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
                <Ellipse x:Name="StatusDot" Width="12" Height="12" Fill="#FFA6E3A1" Margin="0,0,8,0"/>
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

        <TabControl Grid.Row="1" Background="#FF181825" BorderThickness="0">
            <!-- TAB 1: Dashboard -->
            <TabItem Header="Обзор" x:Name="TabDashboard">
                <Grid Margin="0,12,0,0">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <!-- Buttons -->
                    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,14">
                        <Button x:Name="BtnBackup" Content="⟳  Скопировать сейчас" Width="165" Margin="0,0,10,0"
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

                    <!-- Log area -->
                    <Border Grid.Row="3" Background="#FF11111B" CornerRadius="8" Padding="8" Margin="0,12,0,0"
                            Height="130">
                        < ScrollViewer x:Name="LogScroll" VerticalScrollBarVisibility="Auto">
                            <TextBlock x:Name="LogBox" Text="" FontFamily="Consolas" FontSize="11"
                                       Foreground="#FFA9ADC1" TextWrapping="Wrap"/>
                        </ScrollViewer>
                    </Border>
                </Grid>
            </TabItem>

            <!-- TAB 2: Restore -->
            <TabItem Header="Восстановление" x:Name="TabRestore">
                <Grid Margin="0,12,0,0">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Text="Файлы, которые есть в копии, но ОТСУТСТВУЮТ на сервере. Список обновляется автоматически каждые 5 секунд."
                               Foreground="#FFA9ADC1" Margin="0,0,0,10" TextWrapping="Wrap"/>
                    <Border Grid.Row="1" Background="#FF181825" CornerRadius="8" Padding="8">
                        <ListBox x:Name="MissingList" Background="#FF181825" BorderBrush="#FF45475A"
                                 BorderThickness="1" Foreground="#FFCDD6F4" FontSize="13" SelectionMode="Single"/>
                    </Border>
                    <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,12,0,0">
                        <Button x:Name="BtnRestoreSelected" Content="↩  Восстановить выбранный файл" Width="240"
                                Margin="0,0,10,0" Style="{StaticResource PrimaryButton}"/>
                        <Button x:Name="BtnRefreshMissing" Content="⟳  Обновить список" Width="170"
                                Style="{StaticResource InfoButton}"/>
                    </StackPanel>
                </Grid>
            </TabItem>

            <!-- TAB 3: Versions -->
            <TabItem Header="Версии" x:Name="TabVersions">
                <Grid Margin="0,12,0,0">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Text="Снимки изменений. Раскройте дату:  + добавлен/изменён,  − удалён с сервера (время указано рядом). Выберите строку, чтобы восстановить версию. Список обновляется каждые 5 секунд."
                               Foreground="#FFA9ADC1" Margin="0,0,0,10" TextWrapping="Wrap"/>
                    <Border Grid.Row="1" Background="#FF181825" CornerRadius="8" Padding="6">
                        <TreeView x:Name="VersionTree" Background="#FF181825" BorderBrush="#FF45475A"
                                  BorderThickness="1" Foreground="#FFCDD6F4" FontSize="12">
                            <TreeView.ItemContainerStyle>
                                <Style TargetType="TreeViewItem">
                                    <Setter Property="Foreground" Value="#FFCDD6F4"/>
                                </Style>
                            </TreeView.ItemContainerStyle>
                        </TreeView>
                    </Border>
                    <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,12,0,0">
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
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="160"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <TextBlock Grid.Row="0" Grid.Column="0" Text="Папка источника:" VerticalAlignment="Center"
                               Foreground="#FFA9ADC1"/>
                    <Grid Grid.Row="0" Grid.Column="1" Margin="0,4,0,10">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="TxtSource"/>
                        <Button x:Name="BtnPickSource" Grid.Column="1" Content="📁  Выбрать..."
                                Margin="8,0,0,0" Style="{StaticResource InfoButton}"
                                ToolTip="Выбрать папку источника (сетевой путь можно ввести в диалоге)"/>
                    </Grid>

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

                    <StackPanel Grid.Row="7" Grid.Column="0" Grid.ColumnSpan="2" Orientation="Horizontal"
                                VerticalAlignment="Bottom" Margin="0,0,0,4">
                        <Button x:Name="BtnSaveSettings" Content="💾  Сохранить настройки" Width="200" Margin="0,0,10,0"
                                Style="{StaticResource PrimaryButton}"/>
                        <Button x:Name="BtnInstallTask" Content="⏰  Применить расписание" Width="205"
                                Style="{StaticResource InfoButton}"/>
                    </StackPanel>

                    <TextBlock Grid.Row="8" Grid.Column="0" Text="Обновление:" VerticalAlignment="Center"
                               Foreground="#FFA9ADC1"/>
                    <StackPanel Grid.Row="8" Grid.Column="1" Orientation="Horizontal" Margin="0,4,0,4">
                        <Button x:Name="BtnCheckUpdate" Content="⬆  Проверить обновления" Width="220"
                                Style="{StaticResource InfoButton}"/>
                        <TextBlock Text="версия 1.0.0" x:Name="VersionText" Margin="12,0,0,0"
                                   VerticalAlignment="Center" Foreground="#FF6C7086"/>
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
$btnRestoreVersionToBackup = Find 'BtnRestoreVersionToBackup'
$btnRestoreVersionToServer = Find 'BtnRestoreVersionToServer'
$btnOpenVersions  = Find 'BtnOpenVersions'
$btnCleanVersions = Find 'BtnCleanVersions'
$btnDeleteSnapshot = Find 'BtnDeleteSnapshot'
$txtSource        = Find 'TxtSource'
$txtDest          = Find 'TxtDest'
$txtLogs          = Find 'TxtLogs'
$txtInterval      = Find 'TxtInterval'
$txtLogDays       = Find 'TxtLogDays'
$txtVersionsDir   = Find 'TxtVersionsDir'
$txtVersionDays   = Find 'TxtVersionDays'
$chkAuto          = Find 'ChkAuto'
$statusDot        = Find 'StatusDot'
$statusText       = Find 'StatusText'
$statFiles        = Find 'StatFiles'
$statMissing      = Find 'StatMissing'
$statLast         = Find 'StatLast'
$fileList         = Find 'FileList'
$missingList      = Find 'MissingList'
$versionTree      = Find 'VersionTree'
$tabRestore       = Find 'TabRestore'
$tabVersions      = Find 'TabVersions'
$logBox           = Find 'LogBox'
$logScroll        = Find 'LogScroll'

# ---------- Helpers ----------
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
    if (-not (Test-Path -LiteralPath $Src)) { return @() }
    $sourceSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    Get-ChildItem -LiteralPath $Src -File -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        [void]$sourceSet.Add($_.FullName.Substring($Src.Length).TrimStart('\', '/'))
    }
    $res = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $Dst) {
        Get-ChildItem -LiteralPath $Dst -File -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $rel = $_.FullName.Substring($Dst.Length).TrimStart('\', '/')
            if (-not $sourceSet.Contains($rel)) { [void]$res.Add($rel) }
        }
    }
    return $res.ToArray()
}

function Refresh-Dashboard {
    Append-Log "Обновление данных..."
    $dst = $txtDest.Text
    $n = 0
    $items = [System.Collections.Generic.List[object]]::new()
    if (Test-Path -LiteralPath $dst) {
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

    $missing = @(Get-MissingFiles -Src $txtSource.Text -Dst $dst)
    $statMissing.Text = $missing.Count
    $missingList.Items.Clear()
    foreach ($m in $missing) { [void]$missingList.Items.Add($m) }

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
    foreach ($s in $snaps) {
        $node = New-Object System.Windows.Controls.TreeViewItem
        $node.Header = "$($s.When.ToString('dd.MM.yyyy HH:mm'))   $($s.Name)"
        $node.Tag = [PSCustomObject]@{ SnapshotPath = $s.Path; IsSnapshot = $true }
        $node.IsExpanded = ($first -or $expanded.ContainsKey($s.Path))
        foreach ($c in $s.Changes) {
            $child = New-Object System.Windows.Controls.TreeViewItem
            $child.Header = "$($c.Sign) $($c.Time)   $($c.Name)"
            $color = if ($c.Sign -eq '+') { '#FFA6E3A1' } else { '#FFF38BAB' }
            $child.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)
            $child.Tag = [PSCustomObject]@{
                SnapshotPath = $s.Path
                Name         = $c.Name
                Sign         = $c.Sign
                Time         = $c.Time
                IsSnapshot   = $false
            }
            if ($selectedKey -eq "$($child.Tag.SnapshotPath)|$($child.Tag.Name)") {
                $child.IsSelected = $true
            }
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
$btnPickSource.Add_Click({
    $p = Select-Folder -Title 'Выберите папку источника (сетевой путь можно вставить в диалоге)' -Initial $txtSource.Text
    if ($p) {
        $txtSource.Text = $p
        Append-Log "Источник выбран: $p"
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
    Set-Status 'Копирование...' '#FF89B4FA'
    Append-Log "Копирование из $($txtSource.Text) ..."
    $window.Dispatcher.Invoke([Action]{}, 'Normal')  # give UI a chance to repaint

    $job = Start-Job -ScriptBlock {
        param($core, $src, $dst, $logs)
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $core -Source $src -Destination $dst -LogDir $logs | Out-String
    } -ArgumentList $BackupCore, $txtSource.Text, $txtDest.Text, $txtLogs.Text

    while ($job.State -eq 'Running') {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 100
    }
    $out = Receive-Job $job
    Remove-Job $job

    try {
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
        Append-Log "Неожиданный ответ: $out"
    }
    Refresh-Dashboard
    $btnBackup.IsEnabled = $true
})

$btnRefreshMissing.Add_Click({ Refresh-Dashboard })

$btnRestore.Add_Click({ Refresh-Dashboard; $tab = Find 'TabRestore'; $tab.IsSelected = $true })

$btnRestoreSelected.Add_Click({
    $sel = $missingList.SelectedItem
    if (-not $sel) {
        [System.Windows.MessageBox]::Show('Сначала выберите файл из списка.', 'Backuper',
            'OK', 'Information')
        return
    }
    $src = $txtSource.Text
    $target = Join-Path $src $sel
    $msg = "Восстановить файл на сервере?`n`n$sel`n`n→ $target"
    $res = [System.Windows.MessageBox]::Show($msg, 'Подтверждение восстановления',
        'YesNo', 'Question')
    if ($res -ne 'Yes') { return }

    $backupFile = Join-Path $txtDest.Text $sel
    if (-not (Test-Path -LiteralPath $backupFile)) {
        [System.Windows.MessageBox]::Show("Файл копии не найден:`n$backupFile", 'Ошибка', 'OK', 'Error')
        return
    }
    try {
        $dir = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item -LiteralPath $backupFile -Destination $target -Force
        Set-Status 'Восстановлено' '#FFA6E3A1'
        Append-Log "ВОССТАНОВЛЕНО: $sel → $target"
        [System.Windows.MessageBox]::Show("Файл успешно восстановлен:`n$target", 'Backuper', 'OK', 'Information')
        Refresh-Dashboard
    } catch {
        [System.Windows.MessageBox]::Show("Ошибка восстановления:`n$($_.Exception.Message)", 'Ошибка', 'OK', 'Error')
    }
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

function Get-SelectedVersion {
    $item = $versionTree.SelectedItem
    if (-not $item -or -not $item.Tag -or $item.Tag.IsSnapshot) { return $null }
    return $item.Tag
}

$btnRestoreVersionToBackup.Add_Click({
    $v = Get-SelectedVersion
    if (-not $v) {
        [System.Windows.MessageBox]::Show('Сначала выберите строку файла (+ или −) в дереве снимков.', 'Backuper', 'OK', 'Information')
        return
    }
    $src = Join-Path $v.SnapshotPath $v.Name
    if (-not (Test-Path -LiteralPath $src)) {
        $src = Join-Path $txtDest.Text $v.Name
    }
    if (-not (Test-Path -LiteralPath $src)) {
        [System.Windows.MessageBox]::Show("Файл версии не найден:`n$src", 'Ошибка', 'OK', 'Error')
        return
    }
    $target = Join-Path $txtDest.Text $v.Name
    $res = [System.Windows.MessageBox]::Show("Заменить текущую копию этой версией?`n`n$($v.Sign) $($v.Time)  $($v.Name)`n`n→ $target", 'Подтверждение', 'YesNo', 'Question')
    if ($res -ne 'Yes') { return }
    try {
        $dir = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item -LiteralPath $src -Destination $target -Force
        Append-Log "ВЕРСИЯ → КОПИЯ: $($v.Sign) $($v.Time) $($v.Name)"
        Set-Status 'Версия восстановлена в копию' '#FFA6E3A1'
        Refresh-Dashboard
    } catch {
        [System.Windows.MessageBox]::Show("Ошибка: $($_.Exception.Message)", 'Ошибка', 'OK', 'Error')
    }
})

$btnRestoreVersionToServer.Add_Click({
    $v = Get-SelectedVersion
    if (-not $v) {
        [System.Windows.MessageBox]::Show('Сначала выберите строку файла (+ или −) в дереве снимков.', 'Backuper', 'OK', 'Information')
        return
    }
    $src = Join-Path $v.SnapshotPath $v.Name
    if (-not (Test-Path -LiteralPath $src)) {
        $src = Join-Path $txtDest.Text $v.Name
    }
    if (-not (Test-Path -LiteralPath $src)) {
        [System.Windows.MessageBox]::Show("Файл версии не найден:`n$src", 'Ошибка', 'OK', 'Error')
        return
    }
    $target = Join-Path $txtSource.Text $v.Name
    $res = [System.Windows.MessageBox]::Show("Восстановить эту версию на СЕРВЕР?`n`n$($v.Sign) $($v.Time)  $($v.Name)`n`n→ $target", 'Подтверждение восстановления', 'YesNo', 'Question')
    if ($res -ne 'Yes') { return }
    try {
        $dir = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item -LiteralPath $src -Destination $target -Force
        Append-Log "ВЕРСИЯ → СЕРВЕР: $($v.Sign) $($v.Time) $($v.Name)"
        Set-Status 'Версия восстановлена на сервере' '#FFA6E3A1'
        [System.Windows.MessageBox]::Show("Восстановлено на сервере:`n$target", 'Backuper', 'OK', 'Information')
        Refresh-Dashboard
    } catch {
        [System.Windows.MessageBox]::Show("Ошибка: $($_.Exception.Message)", 'Ошибка', 'OK', 'Error')
    }
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
    $settings.Destination = $txtDest.Text
    $settings.LogDir      = $txtLogs.Text
    $settings.IntervalHours = [int]$txtInterval.Text
    $settings.LogRetentionDays = [int]$txtLogDays.Text
    $settings.VersionsDir = $txtVersionsDir.Text
    $settings.VersionRetentionDays = [int]$txtVersionDays.Text
    $settings.AutoRunEnabled = [bool]$chkAuto.IsChecked
    Save-Settings $settings
    Append-Log 'Настройки сохранены.'
    Set-Status 'Настройки сохранены' '#FFA6E3A1'
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
            -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dir\Backup.ps1`" -LogRetentionDays $days -VersionsDir `"$vdir`"" `
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
$txtSource.Text = $settings.Source
$txtDest.Text   = $settings.Destination
$txtLogs.Text   = $settings.LogDir
$txtInterval.Text = $settings.IntervalHours
$txtLogDays.Text = $settings.LogRetentionDays
$txtVersionsDir.Text = $settings.VersionsDir
$txtVersionDays.Text = $settings.VersionRetentionDays
$chkAuto.IsChecked = $settings.AutoRunEnabled

$vf = Join-Path $BaseDir 'version.json'
if (Test-Path -LiteralPath $vf) {
    try { $versionText.Text = 'версия ' + ((Get-Content -LiteralPath $vf -Raw -Encoding UTF8 | ConvertFrom-Json).Version) } catch { }
}

$btnCheckUpdate.Add_Click({
    try {
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $BaseDir 'Update.ps1') `
            -Check -InstallDir $BaseDir 2>&1
        Append-Log ($out -join ' ')
        [System.Windows.MessageBox]::Show(($out -join "`n"), 'Backuper: обновления', 'OK', 'Information')
    } catch {
        [System.Windows.MessageBox]::Show("Ошибка проверки обновлений:`n$($_.Exception.Message)",
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
try {
    $script:updateCheckJob = Start-Job -ScriptBlock {
        param($base)
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $base 'Update.ps1') `
            -Check -InstallDir $base 2>&1 | Out-String
    } -ArgumentList $BaseDir
} catch { }

$updateTimer = New-Object System.Windows.Threading.DispatcherTimer
$updateTimer.Interval = [TimeSpan]::FromSeconds(2)
$updateTimer.Add_Tick({
    if (-not $script:updateCheckJob -or $script:updateCheckDone) { return }
    if ($script:updateCheckJob.State -eq 'Running') { return }
    $script:updateCheckDone = $true
    try {
        $res = Receive-Job $script:updateCheckJob
        $text = ($res | Out-String).Trim()
        if ($text -match 'Доступна версия\s+(\S+)') {
            $newVer = $Matches[1]
            $versionText.Text = "версия $currentVersion  •  доступна $newVer"
            $versionText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#FFF38BAB')
            Append-Log "Доступна новая версия $newVer. Нажмите «Проверить обновления» для подробностей."
            if ($trayIcon) {
                $trayIcon.ShowBalloonTip(10000, 'Backuper: обновление',
                    "Доступна версия $newVer", [System.Windows.Forms.ToolTipIcon]::Info)
            }
        } else {
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
