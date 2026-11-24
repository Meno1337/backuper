<#
.SYNOPSIS
    Styled update window with progress bar and live log.
#>

param(
    [string]$InstallDir = $PSScriptRoot,
    [switch]$AutoClose
)

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $InstallDir) { $InstallDir = $dir }

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:shell="clr-namespace:System.Windows.Shell;assembly=PresentationFramework"
        Title="Backuper — обновление" Height="420" Width="620"
        WindowStartupLocation="CenterScreen" WindowStyle="None" ResizeMode="NoResize"
        Background="#FF1E1E2E">
    <shell:WindowChrome.WindowChrome>
        <shell:WindowChrome CaptionHeight="56" CornerRadius="8" ResizeBorderThickness="0"
                            GlassFrameThickness="0" UseAeroCaptionButtons="False"/>
    </shell:WindowChrome.WindowChrome>
    <Window.Resources>
        <Style TargetType="TextBlock"><Setter Property="Foreground" Value="#FFCDD6F4"/></Style>
        <Style x:Key="WinBtn" TargetType="Button">
            <Setter Property="Width" Value="36"/><Setter Property="Height" Value="32"/>
            <Setter Property="Background" Value="Transparent"/><Setter Property="Foreground" Value="#FFCDD6F4"/>
            <Setter Property="FontSize" Value="15"/><Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="b" Background="{TemplateBinding Background}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#FF45475A"/></Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="ScrollBarPage" TargetType="RepeatButton">
            <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="RepeatButton"><Border Background="#00000000"/></ControlTemplate></Setter.Value></Setter>
        </Style>
        <Style x:Key="Thumb" TargetType="Thumb">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Thumb">
                        <Border x:Name="t" Background="#FF585B70" CornerRadius="6" Margin="2"/>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="t" Property="Background" Value="#FFA6E3A1"/></Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <ControlTemplate x:Key="VScroll" TargetType="ScrollBar">
            <Grid Background="#FF11111B" Width="13">
                <Track x:Name="PART_Track" IsDirectionReversed="True" Orientation="Vertical">
                    <Track.DecreaseRepeatButton><RepeatButton Command="ScrollBar.PageUpCommand" Style="{StaticResource ScrollBarPage}"/></Track.DecreaseRepeatButton>
                    <Track.Thumb><Thumb Style="{StaticResource Thumb}"/></Track.Thumb>
                    <Track.IncreaseRepeatButton><RepeatButton Command="ScrollBar.PageDownCommand" Style="{StaticResource ScrollBarPage}"/></Track.IncreaseRepeatButton>
                </Track>
            </Grid>
        </ControlTemplate>
        <Style TargetType="ScrollBar"><Setter Property="Template" Value="{StaticResource VScroll}"/></Style>
        <Style TargetType="ProgressBar">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ProgressBar">
                        <Border Background="#FF313244" CornerRadius="6" Height="20">
                            <Border x:Name="PART_Indicator" Background="#FFA6E3A1"
                                    CornerRadius="6" HorizontalAlignment="Left"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid Grid.Row="0" Margin="0,0,0,14">
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <StackPanel>
                <TextBlock Text="Обновление Backuper" FontSize="21" FontWeight="Bold" Foreground="#FFA6E3A1"/>
                <TextBlock x:Name="SubTitle" Text="Проверка и установка последней версии" FontSize="12" Foreground="#FFA9ADC1" Margin="0,4,0,0"/>
            </StackPanel>
            <Button x:Name="BtnClose" Content="✕" Style="{StaticResource WinBtn}" HorizontalAlignment="Right"
                    shell:WindowChrome.IsHitTestVisibleInChrome="True"/>
        </Grid>
        <Border Grid.Row="1" Background="#FF181825" CornerRadius="10" Padding="16">
            <StackPanel>
                <TextBlock x:Name="StatusText" Text="Подготовка..." FontSize="13" Margin="0,0,0,10"/>
                <ProgressBar x:Name="Bar" Height="20" Minimum="0" Maximum="100" Value="0"/>
            </StackPanel>
        </Border>
        <Border Grid.Row="2" Background="#FF11111B" CornerRadius="8" Padding="10" Margin="0,14,0,0">
            <ScrollViewer x:Name="LogScroll" VerticalScrollBarVisibility="Auto">
                <TextBlock x:Name="LogBox" Text="" FontFamily="Consolas" FontSize="11"
                           Foreground="#FFA9ADC1" TextWrapping="Wrap"/>
            </ScrollViewer>
        </Border>
        <Button x:Name="BtnDone" Grid.Row="3" Content="Готово" Width="130" Margin="0,14,0,0"
                HorizontalAlignment="Right" IsEnabled="False" Background="#FF585B70"
                Foreground="#FFCDD6F4" FontSize="13" Padding="10,6" Cursor="Hand"/>
    </Grid>
</Window>
'@

$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
$window = [System.Windows.Markup.XamlReader]::Load($reader)
function Find($n) { $window.FindName($n) }
$bar = Find 'Bar'; $logBox = Find 'LogBox'; $logScroll = Find 'LogScroll'
$statusText = Find 'StatusText'; $btnClose = Find 'BtnClose'; $btnDone = Find 'BtnDone'; $subTitle = Find 'SubTitle'

function Append-Log([string]$Text) {
    if (-not $Text) { return }
    $logBox.Text += "$Text`n"
    $logScroll.ScrollToEnd()
}

$btnClose.Add_Click({ $window.Close() })
$btnDone.Add_Click({ $window.Close() })

$live = Join-Path ([System.IO.Path]::GetTempPath()) 'backuper_update_live.log'
Remove-Item -LiteralPath $live -Force -ErrorAction SilentlyContinue
$script:proc = Start-Process powershell.exe -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $dir 'Update.ps1'),
    '-InstallDir', $InstallDir
) -WindowStyle Hidden -PassThru
$script:lastLen = 0

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(300)
$timer.Add_Tick({
    $p = $script:proc
    if (-not $p) { return }
    $text = Get-Content -LiteralPath $live -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if ($text -and $text.Length -gt $script:lastLen) {
        $part = $text.Substring($script:lastLen)
        $script:lastLen = $text.Length
        foreach ($line in ($part -split "`r?`n")) {
            if (-not $line) { continue }
            Append-Log $line
            if ($line -match '\[UPDATE:(\d+)\]\s*(.*)') {
                $bar.Value = [int]$Matches[1]
                $statusText.Text = $Matches[2]
            }
        }
    }
    if (-not $p.HasExited) { return }
    $timer.Stop()
    $final = Get-Content -LiteralPath $live -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    $updated = $false
    if ($final -and $final -match 'установлено') { $updated = $true }
    if ($final -and $final -match 'установлено|актуальная|не настроено|Ошибка|Не удалось') {
        $bar.Value = 100
        $statusText.Text = 'Завершено'
    }

    if ($updated) {
        # restart the main panel automatically after a successful update
        $statusText.Text = 'Перезапуск панели...'
        Append-Log 'Обновление установлено. Перезапуск панели...'
        $me = $PID
        $old = @(Get-CimInstance Win32_Process -Filter "name='powershell.exe'" | Where-Object {
            $_.ProcessId -ne $me -and $_.CommandLine -like '*BackuperGUI.ps1*'
        })
        foreach ($op in $old) { Stop-Process -Id $op.ProcessId -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Milliseconds 700
        $startScript = Join-Path $InstallDir 'BackuperStart.ps1'
        if (-not (Test-Path -LiteralPath $startScript)) { $startScript = Join-Path $InstallDir 'BackuperGUI.ps1' }
        if (Test-Path -LiteralPath $startScript) {
            Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
                '-File', $startScript
            )
            Append-Log 'Панель перезапущена.'
        }
        Start-Sleep -Milliseconds 500
    }

    $btnDone.IsEnabled = $true
    $script:proc = $null
    if ($AutoClose) { $window.Close() }
})
$timer.Start()
$window.ShowDialog() | Out-Null
