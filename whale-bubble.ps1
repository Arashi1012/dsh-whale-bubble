param(
  [int]$Port = 43980
)

# dsh-whale-bubble desktop window.
# Plain Windows PowerShell 5.1 + WPF. Kept ASCII-only on purpose: Windows
# PowerShell reads BOM-less .ps1 files with the ANSI code page, so every
# localized string arrives from the Host plugin through /state instead.
$ErrorActionPreference = 'Stop'

$script:dataDir = Join-Path $env:LOCALAPPDATA 'dsh-whale-bubble'
New-Item -ItemType Directory -Force -Path $script:dataDir | Out-Null
$script:logFile = Join-Path $script:dataDir 'bubble.log'

function Write-Log([string]$message) {
  try {
    if ((Test-Path -LiteralPath $script:logFile) -and ((Get-Item -LiteralPath $script:logFile).Length -gt 262144)) {
      Move-Item -Force -LiteralPath $script:logFile -Destination ($script:logFile + '.old')
    }
    $line = '[{0}] {1}' -f (Get-Date).ToString('HH:mm:ss.fff'), $message
    Add-Content -LiteralPath $script:logFile -Value $line -Encoding UTF8
  } catch { }
}

# --- single instance -------------------------------------------------------
$script:mutexCreated = $false
$script:mutex = New-Object System.Threading.Mutex($true, 'Local\DshWhaleBubbleWindow', [ref]$script:mutexCreated)
if (-not $script:mutexCreated) {
  Write-Log 'another bubble instance owns the single-instance mutex; exiting'
  exit 0
}

# --- win32 helpers ---------------------------------------------------------
Add-Type -Namespace DshWin -Name Native -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
[StructLayout(LayoutKind.Sequential)]
public struct POINT { public int X; public int Y; }
[DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT pt);
[DllImport("user32.dll")] public static extern bool PtInRect(ref RECT rect, POINT pt);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
[DllImport("user32.dll", EntryPoint = "GetWindowLongW")] public static extern int GetWindowLong(IntPtr hWnd, int index);
[DllImport("user32.dll", EntryPoint = "SetWindowLongW")] public static extern int SetWindowLong(IntPtr hWnd, int index, int value);
[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
'@
[DshWin.Native]::SetProcessDPIAware() | Out-Null

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- application and window ------------------------------------------------
$script:app = New-Object System.Windows.Application
$script:app.ShutdownMode = [System.Windows.ShutdownMode]::OnMainWindowClose

[xml]$script:xamlDoc = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DSH Whale Bubble"
        Width="62" SizeToContent="Height"
        WindowStartupLocation="Manual"
        WindowStyle="None" AllowsTransparency="True"
        Background="{x:Null}"
        Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize"
        ShowActivated="False" UseLayoutRounding="True"
        TextOptions.TextFormattingMode="Ideal"
        TextOptions.TextRenderingMode="ClearType"
        FontFamily="Microsoft YaHei UI, Segoe UI">
    <Grid x:Name="Root" Width="62" Background="{x:Null}">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <Border x:Name="Card" Grid.Row="0" Width="244" Margin="0,0,0,6"
              CornerRadius="14" Background="#FFFFFF" BorderBrush="#E7ECF9" BorderThickness="1"
              Padding="12,10,12,9" Visibility="Collapsed">
        <Border.Effect>
          <DropShadowEffect BlurRadius="18" ShadowDepth="3" Opacity="0.16" Color="#1B2550"/>
        </Border.Effect>
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <Border x:Name="Accent" Grid.Row="0" Width="3" Height="13" CornerRadius="1.5"
                  Background="#4D6BFE" HorizontalAlignment="Left" VerticalAlignment="Center"/>
          <TextBlock x:Name="TxtTitle" Grid.Row="0" Margin="11,0,64,0" Text=""
                     FontSize="12.5" FontWeight="SemiBold" Foreground="#232A3B"
                     TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
          <TextBlock x:Name="TxtMeta" Grid.Row="0" HorizontalAlignment="Right" VerticalAlignment="Center"
                     Text="" FontSize="10.5" Foreground="#8B95A9"
                     Typography.NumeralAlignment="Tabular"/>
          <TextBlock x:Name="TxtDetail" Grid.Row="1" Margin="11,4,0,0" Text=""
                     FontSize="11" Foreground="#6D7891" TextTrimming="CharacterEllipsis"
                     Visibility="Collapsed"/>
          <Border x:Name="BarTrack" Grid.Row="2" Height="2.5" CornerRadius="1.25"
                  Background="#EEF2FC" Margin="11,8,0,0" Visibility="Collapsed">
            <Border x:Name="Bar" Width="46" Height="2.5" CornerRadius="1.25"
                    Background="#4D6BFE" HorizontalAlignment="Left"/>
          </Border>
        </Grid>
      </Border>

      <Canvas x:Name="Stage" Grid.Row="1" Height="52" VerticalAlignment="Bottom" Background="{x:Null}">
      <Border x:Name="DragArea" Canvas.Left="0" Canvas.Top="0" Width="220" Height="52"
              Background="Transparent"/>

      <Viewbox x:Name="MascotBox" Width="52" Height="52" Canvas.Left="84" Canvas.Top="0"
               Stretch="Uniform">
        <Canvas x:Name="Whale" Width="104" Height="104">
          <Canvas.RenderTransform>
            <TranslateTransform x:Name="Bob" Y="0"/>
          </Canvas.RenderTransform>
          <Border Width="104" Height="104">
            <Path x:Name="WhalePath" Data="M 0,0 L 1,1" Fill="#4D6BFE" Stretch="None">
              <Path.Effect>
                <DropShadowEffect BlurRadius="10" ShadowDepth="1" Opacity="0.3" Color="#16204A"/>
              </Path.Effect>
            </Path>
          </Border>
        </Canvas>
      </Viewbox>

      <Border x:Name="DoneDot" Width="7.7" Height="7.7" CornerRadius="3.85" Background="#22C55E"
              Canvas.Left="86" Canvas.Top="15" Visibility="Collapsed"/>
    </Canvas>
    </Grid>
</Window>
'@

$script:reader = New-Object System.Xml.XmlNodeReader($script:xamlDoc)
$script:window = [System.Windows.Markup.XamlReader]::Load($script:reader)

function Get-Part([string]$name) {
  $part = $script:window.FindName($name)
  if ($null -eq $part) { throw "xaml part missing: $name" }
  return $part
}

$script:Root = Get-Part 'Root'
$script:Stage = Get-Part 'Stage'
$script:DragArea = Get-Part 'DragArea'
$script:MascotBox = Get-Part 'MascotBox'
$script:Card = Get-Part 'Card'
$script:Accent = Get-Part 'Accent'
$script:TxtTitle = Get-Part 'TxtTitle'
$script:TxtMeta = Get-Part 'TxtMeta'
$script:TxtDetail = Get-Part 'TxtDetail'
$script:BarTrack = Get-Part 'BarTrack'
$script:Bar = Get-Part 'Bar'
$script:Whale = Get-Part 'Whale'
$script:WhalePath = Get-Part 'WhalePath'
$script:DoneDot = Get-Part 'DoneDot'
$script:Bob = $script:window.FindName('Bob')
if ($null -eq $script:Bob) { $script:Bob = $script:Whale.RenderTransform }

$script:brushCache = @{}
function Get-Brush([string]$hex) {
  if (-not $script:brushCache.ContainsKey($hex)) {
    $script:brushCache[$hex] = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($hex)
  }
  return $script:brushCache[$hex]
}

$script:tones = @{
  blue   = @{ accent = '#4D6BFE'; border = '#CBD8FF'; bg = '#FBFBFF'; text = '#2B3A67'; sub = '#6B7899' }
  green  = @{ accent = '#22C55E'; border = '#B9EBC8'; bg = '#F7FFFA'; text = '#14532D'; sub = '#4B7A5E' }
  orange = @{ accent = '#F59E0B'; border = '#FFD9B8'; bg = '#FFFBF5'; text = '#7C4A03'; sub = '#8A6A3C' }
  gray   = @{ accent = '#94A3B8'; border = '#DDE1EC'; bg = '#FAFBFC'; text = '#404A5C'; sub = '#6B7280' }
}

# The whale mark is official DeepSeek artwork: the web frontend favicon path,
# loaded at runtime so the asset stays a plain SVG file next to this script.
function New-WhaleGeometry([double]$flapDeg) {
  $flap = $flapDeg * [Math]::PI / 180
  $geo = New-Object System.Windows.Media.StreamGeometry
  $ctx = $geo.Open()
  $ctx.BeginFigure($script:whaleBody[0], $true, $true)
  for ($k = 1; $k -lt $script:whaleBody.Count; $k++) { $ctx.LineTo($script:whaleBody[$k], $true, $false) }
  for ($k = 1; $k -lt $script:whaleTail.Count - 1; $k++) {
    $t = $script:whaleT[$k]
    $angle = $flap * ($t + 0.35 * $t * $t)
    $pr = $script:whaleProj[$k]
    $p = $script:whaleTail[$k]
    $cos = [Math]::Cos($angle); $sin = [Math]::Sin($angle)
    $dx = $p.X - $pr[0]; $dy = $p.Y - $pr[1]
    $ctx.LineTo([System.Windows.Point]::new(($pr[0] + $dx * $cos - $dy * $sin), ($pr[1] + $dx * $sin + $dy * $cos)), $true, $false)
  }
  $ctx.Close()
  $group = New-Object System.Windows.Media.GeometryGroup
  $group.FillRule = [System.Windows.Media.FillRule]::Nonzero
  $group.Children.Add($geo)
  foreach ($hole in $script:whaleHoles) {
    $hg = New-Object System.Windows.Media.StreamGeometry
    $hc = $hg.Open()
    $hc.BeginFigure($hole[0], $true, $true)
    for ($k = 1; $k -lt $hole.Count; $k++) { $hc.LineTo($hole[$k], $true, $false) }
    $hc.Close()
    $group.Children.Add($hg)
  }
  return $group
}

function Initialize-Whale {
  try {
    $svgFile = Join-Path $PSScriptRoot 'whale.svg'
    if (-not (Test-Path -LiteralPath $svgFile)) {
      Write-Log 'whale.svg missing; the bubble stays empty'
      return
    }
    $text = [System.IO.File]::ReadAllText($svgFile, [System.Text.Encoding]::UTF8)
    $found = [regex]::Match($text, 'd="([^"]+)"')
    if (-not $found.Success) {
      Write-Log 'whale.svg has no path data'
      return
    }
    $full = [System.Windows.Media.Geometry]::Parse($found.Groups[1].Value)
    $flat = $full.GetFlattenedPathGeometry(0.03, [System.Windows.Media.ToleranceType]::Absolute)

    $figures = @()
    foreach ($figure in $flat.Figures) {
      $list = New-Object System.Collections.Generic.List[object]
      $list.Add($figure.StartPoint)
      foreach ($seg in $figure.Segments) {
        $segType = $seg.GetType().Name
        if ($seg.PSObject.Properties.Name -contains 'Points') {
          foreach ($p in $seg.Points) { $list.Add($p) }
        } elseif ($segType -eq 'BezierSegment') {
          $list.Add($seg.Point3)
        } elseif ($segType -eq 'LineSegment') {
          $list.Add($seg.Point)
        }
      }
      $figures += ,$list
    }
    $outer = $figures[0]
    $count = $outer.Count
    $ia = 0; $ib = 0; $bestA = [double]::MaxValue; $bestB = [double]::MaxValue
    for ($i = 0; $i -lt $count; $i++) {
      $distA = [Math]::Pow($outer[$i].X - 33.0, 2) + [Math]::Pow($outer[$i].Y - 19.0, 2)
      if ($distA -lt $bestA) { $bestA = $distA; $ia = $i }
      $distB = [Math]::Pow($outer[$i].X - 44.0, 2) + [Math]::Pow($outer[$i].Y - 20.5, 2)
      if ($distB -lt $bestB) { $bestB = $distB; $ib = $i }
    }
    $body = @(); $i = $ia
    while ($true) { $body += $outer[$i]; if ($i -eq $ib) { break }; $i = ($i + 1) % $count }
    $tail = @(); $i = $ib
    while ($true) { $tail += $outer[$i]; if ($i -eq $ia) { break }; $i = ($i + 1) % $count }

    $ax = $body[0].X; $ay = $body[0].Y
    $bx = $body[$body.Count - 1].X; $by = $body[$body.Count - 1].Y
    $cx = $bx - $ax; $cy = $by - $ay
    $cl2 = $cx * $cx + $cy * $cy
    $proj = @(); $maxD = 0.0001
    for ($k = 0; $k -lt $tail.Count; $k++) {
      $p = $tail[$k]
      $s = (($p.X - $ax) * $cx + ($p.Y - $ay) * $cy) / $cl2
      if ($s -lt 0) { $s = 0 } elseif ($s -gt 1) { $s = 1 }
      $px = $ax + $cx * $s; $py = $ay + $cy * $s
      $dd = [Math]::Sqrt([Math]::Pow($p.X - $px, 2) + [Math]::Pow($p.Y - $py, 2))
      if ($dd -gt $maxD) { $maxD = $dd }
      $proj += ,@($px, $py)
    }
    $tvals = @()
    for ($k = 0; $k -lt $tail.Count; $k++) {
      $p = $tail[$k]; $pr = $proj[$k]
      $tvals += ([Math]::Sqrt([Math]::Pow($p.X - $pr[0], 2) + [Math]::Pow($p.Y - $pr[1], 2)) / $maxD)
    }
    $holes = @()
    for ($f = 1; $f -lt $figures.Count; $f++) { $holes += ,$figures[$f] }

    $script:whaleBody = $body
    $script:whaleTail = $tail
    $script:whaleProj = $proj
    $script:whaleT = $tvals
    $script:whaleHoles = $holes

    $script:restGeometry = New-WhaleGeometry 0
    $bounds = $script:restGeometry.Bounds
    $scale = [Math]::Min((104 - 24) / $bounds.Width, (104 - 26) / $bounds.Height)
    $offsetX = 12 + ((104 - 24) - $bounds.Width * $scale) / 2 - $bounds.X * $scale
    $offsetY = 14 + ((104 - 26) - $bounds.Height * $scale) / 2 - $bounds.Y * $scale
    $script:WhalePath.Stretch = [System.Windows.Media.Stretch]::None
    $script:WhalePath.RenderTransform = New-Object System.Windows.Media.MatrixTransform($scale, 0, 0, $scale, $offsetX, $offsetY)
    $script:WhalePath.Data = $script:restGeometry

    $boxLeft = ($script:designWidth - 104 * $script:uiScale) / 2
    $dotX = $boxLeft + ($offsetX + 5.0 * $scale) * $script:uiScale
    $dotY = ($offsetY + 6.5 * $scale) * $script:uiScale
    [System.Windows.Controls.Canvas]::SetLeft($script:DoneDot, [Math]::Round($dotX - 3.85, 1))
    [System.Windows.Controls.Canvas]::SetTop($script:DoneDot, [Math]::Round($dotY - 3.85, 1))
    Write-Log ('whale mark ready: body=' + $body.Count + ' tail=' + $tail.Count + ' ia=' + $ia + ' ib=' + $ib + ' count=' + $count)
  } catch {
    Write-Log ('whale mark failed: ' + $_.Exception.Message)
  }
}

# --- window plumbing -------------------------------------------------------
function Get-Hwnd {
  return (New-Object System.Windows.Interop.WindowInteropHelper($script:window)).Handle
}

function Get-WindowRectPx {
  $rect = New-Object DshWin.Native+RECT
  [DshWin.Native]::GetWindowRect((Get-Hwnd), [ref]$rect) | Out-Null
  return $rect
}

function Get-DpiScale {
  try {
    $source = [System.Windows.PresentationSource]::FromVisual($script:window)
    if ($null -ne $source -and $null -ne $source.CompositionTarget) {
      return [double]$source.CompositionTarget.TransformToDevice.M11
    }
  } catch { }
  return 1.0
}

function Set-WindowPosition([double]$x, [double]$y) {
  $script:window.Left = $x
  $script:window.Top = $y
}

function Get-WorkArea {
  return [System.Windows.SystemParameters]::WorkArea
}

function Save-Position {
  try {
    $offset = 0.0
    if ($script:cardShown -and $script:whaleSize -gt 0) { $offset = ($script:cardWidth - $script:whaleSize) / 2 }
    $whaleLeft = $script:window.Left + $offset
    $bottom = $script:window.Top + $script:window.ActualHeight
    $whaleTop = $bottom - $script:whaleSize
    $payload = '{"x":' + [Math]::Round($whaleLeft, 1) + ',"y":' + [Math]::Round($whaleTop, 1) + '}'
    Set-Content -LiteralPath (Join-Path $script:dataDir 'position.json') -Value $payload -Encoding UTF8
  } catch { }
}

function Restore-Position {
  try {
    $area = Get-WorkArea
    $height = $script:window.ActualHeight
    if ($height -le 0) { $height = $script:whaleSize }
    $x = $area.Right - $script:window.Width - 12
    $y = $area.Bottom - $height - 8
    $posFile = Join-Path $script:dataDir 'position.json'
    if (Test-Path -LiteralPath $posFile) {
      $saved = (Get-Content -Raw -LiteralPath $posFile) | ConvertFrom-Json
      $sx = [double]$saved.x
      $sy = [double]$saved.y
      if ($sx -ge 0 -and $sy -ge 0 -and $sx -lt ($area.Right - 60) -and $sy -lt ($area.Bottom - 60)) {
        $x = $sx
        $y = $sy
      }
    }
    if ($x -lt 0) { $x = 0 }
    if ($y -lt 0) { $y = 0 }
    Set-WindowPosition $x $y
  } catch {
    Write-Log ('restore position failed: ' + $_.Exception.Message)
  }
}

function Reset-Position {
  $area = Get-WorkArea
  $height = $script:window.ActualHeight
  if ($height -le 0) { $height = $script:whaleSize }
  Set-WindowPosition ($area.Right - $script:window.Width - 12) ($area.Bottom - $height - 8)
  Save-Position
}

function Toggle-Harness {
  try {
    $handle = [IntPtr]::Zero
    for ($attempt = 0; $attempt -lt 3 -and $handle -eq [IntPtr]::Zero; $attempt++) {
      $target = Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
      if ($null -ne $target) {
        $handle = $target.MainWindowHandle
      } else {
        Start-Sleep -Milliseconds 150
      }
    }
    if ($handle -ne [IntPtr]::Zero) {
      $iconic = [DshWin.Native]::IsIconic($handle)
      $foreground = [DshWin.Native]::GetForegroundWindow()
      if ((-not $iconic) -and $foreground -eq $handle) {
        [DshWin.Native]::ShowWindow($handle, 6) | Out-Null
        Write-Log 'toggle: harness minimized'
        return
      }
      if ($iconic) {
        [DshWin.Native]::ShowWindow($handle, 9) | Out-Null
      } else {
        [DshWin.Native]::ShowWindow($handle, 5) | Out-Null
      }
      [DshWin.Native]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
      [DshWin.Native]::SetForegroundWindow($handle) | Out-Null
      [DshWin.Native]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
      [DshWin.Native]::BringWindowToTop($handle) | Out-Null
      Write-Log ('toggle: harness shown iconic=' + [DshWin.Native]::IsIconic($handle))
      return
    }
    # Fallback: let the shell activate the app by process id.
    $fallback = Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $fallback) {
      $shell = New-Object -ComObject WScript.Shell
      $shell.AppActivate($fallback.Id) | Out-Null
      Write-Log ('toggle: AppActivate pid=' + $fallback.Id)
      return
    }
    Write-Log 'toggle: harness window not found'
  } catch {
    Write-Log ('toggle failed: ' + $_.Exception.Message)
  }
}

# --- ui state --------------------------------------------------------------
$script:viewKind = 'idle'
$script:cardVisible = $false
$script:barVisible = $false
$script:phase = 0.0
$script:jumpUntil = [DateTime]::MinValue
$script:sound = $true
$script:lastCompletionAt = 0.0
$script:lastCaptureSeq = 0
$script:helloSent = $false
$script:pollFails = 0
$script:demoView = $null
$script:swimPhase = 0.0
$script:cardShown = $false
$script:viewHasProgress = $false
$script:whaleSize = 0.0
$script:cardWidth = 244.0
$script:barVisible = $false
$script:hoverTimer = $null
$script:hoverMisses = 0
$script:restGeometry = $null
$script:whaleBody = @()
$script:whaleTail = @()
$script:whaleProj = @()
$script:whaleT = @()
$script:whaleHoles = @()
# The window hugs the mascot: no text card, only the whale and the completion dot.
$script:uiScale = 0.6
$script:designWidth = [Math]::Round(104 * $script:uiScale, 1)

function Apply-View($view) {
  if ($null -eq $view) { return }
  $kind = [string]$view.kind
  $toneName = [string]$view.tone
  if (-not $script:tones.ContainsKey($toneName)) { $toneName = 'blue' }
  $tone = $script:tones[$toneName]
  $script:viewKind = $kind

  if ($null -ne $script:DoneDot) {
    if ($kind -eq 'done') { $script:DoneDot.Visibility = 'Visible' } else { $script:DoneDot.Visibility = 'Collapsed' }
  }
  if ($kind -ne 'working' -and $null -ne $script:restGeometry) {
    $script:WhalePath.Data = $script:restGeometry
  }

  $hasProgress = ($kind -eq 'working' -or $kind -eq 'done' -or $kind -eq 'error')
  $script:viewHasProgress = $hasProgress
  if ($hasProgress -and $script:window.IsMouseOver) { Show-ProgressCard }
  if (-not $hasProgress) {
    $script:barVisible = $false
    if ($script:cardShown) { Hide-ProgressCard }
    return
  }

  $script:TxtTitle.Text = [string]$view.title
  $script:TxtMeta.Text = [string]$view.meta
  $detail = [string]$view.detail
  $script:TxtDetail.Text = $detail
  if ([string]::IsNullOrWhiteSpace($detail)) {
    $script:TxtDetail.Visibility = 'Collapsed'
  } else {
    $script:TxtDetail.Visibility = 'Visible'
  }
  $script:Accent.Background = Get-Brush $tone.accent
  $script:Bar.Background = Get-Brush $tone.accent
  $showBar = [bool]$view.bar
  $script:barVisible = $showBar
  if ($showBar) { $script:BarTrack.Visibility = 'Visible' } else { $script:BarTrack.Visibility = 'Collapsed' }
}

function Show-ProgressCard {
  try {
    if ($script:cardShown -or -not $script:viewHasProgress) { return }
    $script:cardShown = $true
    $delta = ($script:cardWidth - $script:whaleSize) / 2
    $script:Card.Visibility = 'Visible'
    $script:Root.Background = [System.Windows.Media.Brushes]::Transparent
    $script:Root.Width = $script:cardWidth
    $script:Stage.Width = $script:cardWidth
    [System.Windows.Controls.Canvas]::SetLeft($script:MascotBox, $delta)
    $script:DragArea.Width = $script:cardWidth
    $script:window.Width = $script:cardWidth
    $script:window.Left = $script:window.Left - $delta
    Write-Log 'hover: card shown'
  } catch {
    Write-Log ('show card failed: ' + $_.Exception.Message)
  }
}

function Hide-ProgressCard {
  try {
    if (-not $script:cardShown) { return }
    $script:cardShown = $false
    $delta = ($script:cardWidth - $script:whaleSize) / 2
    $script:Card.Visibility = 'Collapsed'
    $script:Root.Background = $null
    $script:Root.Width = $script:whaleSize
    $script:Stage.Width = $script:whaleSize
    [System.Windows.Controls.Canvas]::SetLeft($script:MascotBox, 0)
    $script:DragArea.Width = $script:whaleSize
    $script:window.Width = $script:whaleSize
    $script:window.Left = $script:window.Left + $delta
    Write-Log 'hover: card hidden'
  } catch {
    Write-Log ('hide card failed: ' + $_.Exception.Message)
  }
}

function Update-Menu($menu) {
  if ($null -ne $menu.reset) { $script:menuReset.Header = [string]$menu.reset }
  if ($null -ne $menu.test) { $script:menuTest.Header = [string]$menu.test }
  if ($null -ne $menu.exit) { $script:menuExit.Header = [string]$menu.exit }
}

# --- animation -------------------------------------------------------------
function Step-Animation {
  try {
    $script:phase += 0.12
    $now = [DateTime]::UtcNow
    if ($now -lt $script:jumpUntil) {
      $remaining = ($script:jumpUntil - $now).TotalMilliseconds / 1300.0
      $script:Bob.Y = -1.0 * [Math]::Abs([Math]::Sin($script:phase * 2.6)) * 18.0 * $remaining
    } elseif ($script:viewKind -eq 'working') {
      $script:Bob.Y = [Math]::Sin($script:phase * 1.6) * 2.6 - 1.0
    } else {
      $script:Bob.Y = [Math]::Sin($script:phase * 0.55) * 1.8
    }

    if ($script:viewKind -eq 'working' -and $null -ne $script:restGeometry) {
      $script:swimPhase += 0.17
      if ($script:swimPhase -gt 6.283185307179586) { $script:swimPhase -= 6.283185307179586 }
      $script:WhalePath.Data = New-WhaleGeometry (14.0 * [Math]::Sin($script:swimPhase))
      $script:Bob.Y = [Math]::Sin($script:swimPhase + 1.0) * 1.5
    }

    if ($script:cardShown -and $script:barVisible) {
      $script:Bar.Width = 46.0 + 150.0 * (0.5 + 0.5 * [Math]::Sin($script:phase * 1.9))
    }
  } catch { }
}

# --- http ------------------------------------------------------------------
function Post-Json([string]$path, [string]$json) {
  try {
    Invoke-RestMethod -Uri ('http://127.0.0.1:' + $Port + $path) -Method Post `
      -ContentType 'application/json' -Body $json -TimeoutSec 2 | Out-Null
    return $true
  } catch {
    Write-Log ('post ' + $path + ' failed: ' + $_.Exception.Message)
    return $false
  }
}

function Send-Hello {
  try {
    $handle = Get-Hwnd
    $rect = Get-WindowRectPx
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    $payload = '{"pid":' + $PID + ',"hwnd":"' + $handle.ToString() + '","width":' + $width + ',"height":' + $height + '}'
    return (Post-Json '/hello' $payload)
  } catch {
    Write-Log ('hello build failed: ' + $_.Exception.Message)
    return $false
  }
}

function Save-Preview([int]$seq) {
  try {
    $root = $script:window.Content
    $width = [int][Math]::Ceiling($root.ActualWidth)
    $height = [int][Math]::Ceiling($root.ActualHeight)
    if ($width -le 0 -or $height -le 0) { return }
    $bitmap = New-Object System.Windows.Media.Imaging.RenderTargetBitmap(
      $width, $height, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($root)
    $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $path = Join-Path $script:dataDir 'preview.png'
    $stream = [System.IO.File]::Create($path)
    $encoder.Save($stream)
    $stream.Close()
    Write-Log ('preview saved ' + $width + 'x' + $height)
    Post-Json '/capture-done' ('{"seq":' + $seq + '}')
  } catch {
    Write-Log ('preview failed: ' + $_.Exception.Message)
  }
}

function Update-FromState($state) {
  if ($null -eq $state) { return }
  if ($state.shutdown -eq $true) {
    Write-Log 'plugin asked the bubble to shut down'
    $script:window.Close()
    return
  }
  if (-not $script:helloSent) {
    if (Send-Hello) { $script:helloSent = $true }
  }
  $script:sound = ($state.sound -ne $false)
  if ($null -ne $state.menu) { Update-Menu $state.menu }
  if ($null -ne $state.demo) { $script:demoView = $state.demo }

  $captureSeq = [int]$state.captureSeq
  if ($captureSeq -gt $script:lastCaptureSeq) {
    $script:lastCaptureSeq = $captureSeq
    Save-Preview $captureSeq
  }

  $completionAt = 0.0
  if ($null -ne $state.completion) { $completionAt = [double]$state.completion.at }
  if ($completionAt -gt $script:lastCompletionAt) {
    $script:lastCompletionAt = $completionAt
    $script:jumpUntil = [DateTime]::UtcNow.AddMilliseconds(1300)
    if ($script:sound) {
      try { [System.Media.SystemSounds]::Asterisk.Play() } catch { }
    }
  }

  Apply-View $state.view
}

function Poll-State {
  try {
    $req = [System.Net.WebRequest]::Create(('http://127.0.0.1:{0}/state' -f $Port))
    $req.Proxy = $null
    $req.Timeout = 4000
    $resp = $req.GetResponse()
    $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
    $body = $reader.ReadToEnd()
    $reader.Close()
    $resp.Close()
    if ($script:pollFails -gt 0) { $script:helloSent = $false }
    $script:pollFails = 0
    $state = $body | ConvertFrom-Json
    Update-FromState $state
  } catch {
    $script:pollFails = $script:pollFails + 1
    if ($script:pollFails -eq 1) {
      Write-Log ('state poll failed: ' + $_.Exception.Message)
    }
    if ($script:pollFails -ge 40) {
      Write-Log 'state endpoint stayed unreachable; exiting'
      $script:window.Close()
    }
  }
}

# --- menus -----------------------------------------------------------------
$script:menuReset = New-Object System.Windows.Controls.MenuItem
$script:menuReset.Header = 'Reset position'
$script:menuReset.Add_Click({ Reset-Position })

$script:menuTest = New-Object System.Windows.Controls.MenuItem
$script:menuTest.Header = 'Preview completion'
$script:menuTest.Add_Click({
  $script:jumpUntil = [DateTime]::UtcNow.AddMilliseconds(1300)
  if ($script:sound) { try { [System.Media.SystemSounds]::Asterisk.Play() } catch { } }
  if ($null -ne $script:demoView) { Apply-View $script:demoView }
})

$script:menuExit = New-Object System.Windows.Controls.MenuItem
$script:menuExit.Header = 'Quit bubble'
$script:menuExit.Add_Click({
  Save-Position
  Post-Json '/quit' '{}' | Out-Null
  $script:window.Close()
})

$script:contextMenu = New-Object System.Windows.Controls.ContextMenu
$script:contextMenu.Items.Add($script:menuReset) | Out-Null
$script:contextMenu.Items.Add($script:menuTest) | Out-Null
$script:contextMenu.Items.Add($script:menuExit) | Out-Null
$script:window.ContextMenu = $script:contextMenu

# --- drag and click --------------------------------------------------------
$script:drag = $null
$script:dragged = $false

$script:window.Add_MouseLeftButtonDown({
  param($sender, $e)
  try {
    if ($script:cardShown) {
      $stageTop = $script:window.ActualHeight - $script:whaleSize
      if ($e.GetPosition($script:window).Y -lt $stageTop) {
        $script:drag = $null
        return
      }
    }
    $p = [System.Windows.Forms.Cursor]::Position
    $script:drag = @{ X = $p.X; Y = $p.Y; Left = $script:window.Left; Top = $script:window.Top }
    $script:dragged = $false
    $script:skipMove = $true
    $script:window.CaptureMouse() | Out-Null
  } catch { }
})

$script:window.Add_MouseMove({
  if ($null -eq $script:drag) { return }
  try {
    $p = [System.Windows.Forms.Cursor]::Position
    if ($script:skipMove) {
      # the first move after mousedown can carry a stale cursor position;
      # rebase the drag origin on it instead of treating it as movement
      $script:skipMove = $false
      $script:drag.X = $p.X
      $script:drag.Y = $p.Y
      return
    }
    $scale = Get-DpiScale
    $dx = ($p.X - $script:drag.X) / $scale
    $dy = ($p.Y - $script:drag.Y) / $scale
    if (-not $script:dragged -and ([Math]::Abs($dx) -gt 5 -or [Math]::Abs($dy) -gt 5)) {
      $script:dragged = $true
    }
    if ($script:dragged) {
      Set-WindowPosition ($script:drag.Left + $dx) ($script:drag.Top + $dy)
    }
  } catch { }
})

$script:window.Add_MouseLeftButtonUp({
  if ($null -eq $script:drag) { return }
  try {
    $moved = $script:dragged
    $startLeft = $script:drag.Left
    $startTop = $script:drag.Top
    $script:window.ReleaseMouseCapture()
    $script:drag = $null
    $script:dragged = $false
    if ($moved) {
      Save-Position
      Write-Log 'drag: position saved'
    } else {
      Set-WindowPosition $startLeft $startTop
      Toggle-Harness
    }
  } catch { }
})

$script:window.Add_MouseEnter({
  try {
    $script:hoverMisses = 0
    Show-ProgressCard
  } catch { }
})

# A window that grows under the cursor can report a spurious MouseLeave, so the
# card is kept open by watching the real cursor position instead.
$script:hoverWatch = New-Object System.Windows.Threading.DispatcherTimer
$script:hoverWatch.Interval = [TimeSpan]::FromMilliseconds(220)
$script:hoverWatch.Add_Tick({
  try {
    if (-not $script:cardShown) { return }
    $rect = Get-WindowRectPx
    $rect.Left -= 6; $rect.Top -= 6; $rect.Right += 6; $rect.Bottom += 6
    $pt = New-Object DshWin.Native+POINT
    [DshWin.Native]::GetCursorPos([ref]$pt) | Out-Null
    if ([DshWin.Native]::PtInRect([ref]$rect, $pt)) {
      $script:hoverMisses = 0
    } else {
      $script:hoverMisses += 1
      if ($script:hoverMisses -eq 1) {
        Write-Log ('hover miss: window=' + $rect.Left + ',' + $rect.Top + '..' + $rect.Right + ',' + $rect.Bottom + ' cursor=' + $pt.X + ',' + $pt.Y)
      }
      if ($script:hoverMisses -ge 2) { Hide-ProgressCard }
    }
  } catch { }
})
$script:hoverWatch.Start()

Initialize-Whale

function Initialize-Mascot {
  try {
    $size = [Math]::Round(104 * $script:uiScale, 1)
    $script:whaleSize = $size
    $script:designWidth = $size
    $script:Root.Width = $size
    $script:window.Width = $size
    $script:MascotBox.Width = $size
    $script:MascotBox.Height = $size
    [System.Windows.Controls.Canvas]::SetLeft($script:MascotBox, 0)
    [System.Windows.Controls.Canvas]::SetTop($script:MascotBox, 0)
    $script:Stage.Width = $size
    $script:Stage.Height = $size
    $script:DragArea.Width = $size
    $script:DragArea.Height = $size
    Write-Log ('mascot size=' + $size + ' scale=' + $script:uiScale)
  } catch {
    Write-Log ('mascot layout failed: ' + $_.Exception.Message)
  }
}

Initialize-Mascot

# --- show windows ----------------------------------------------------------
$script:window.Add_SourceInitialized({
  try {
    $handle = Get-Hwnd
    $exStyle = [DshWin.Native]::GetWindowLong($handle, -20)
    $newStyle = ($exStyle -bor 0x08000000 -bor 0x00000080)
    [DshWin.Native]::SetWindowLong($handle, -20, $newStyle) | Out-Null
  } catch {
    Write-Log ('ex style failed: ' + $_.Exception.Message)
  }
})

$script:animTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:animTimer.Interval = [TimeSpan]::FromMilliseconds(33)
$script:animTimer.Add_Tick({ Step-Animation })

$script:pollTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:pollTimer.Interval = [TimeSpan]::FromMilliseconds(400)
$script:pollTimer.Add_Tick({ Poll-State })

$script:lastHeight = 0.0

$script:window.Add_SizeChanged({
  param($sender, $e)
  try {
    $newHeight = $e.NewSize.Height
    if ($script:lastHeight -gt 0 -and [Math]::Abs($newHeight - $script:lastHeight) -gt 0.1) {
      $script:window.Top = $script:window.Top + ($script:lastHeight - $newHeight)
    }
    $script:lastHeight = $newHeight
  } catch { }
})

$script:window.Add_Loaded({
  try {
    $script:window.Width = $script:designWidth
    $script:window.UpdateLayout()
    $script:lastHeight = $script:window.ActualHeight
    Restore-Position
    $script:pollTimer.Start()
    $script:animTimer.Start()
    Write-Log ('bubble window shown on port ' + $Port)
  } catch {
    Write-Log ('loaded failed: ' + $_.Exception.Message)
  }
})

$script:window.Add_Closed({
  try {
    $script:animTimer.Stop()
    $script:pollTimer.Stop()
    Save-Position
  } catch { }
  Write-Log 'bubble window closed'
})

try {
  $script:app.Run($script:window) | Out-Null
} catch {
  Write-Log ('application run failed: ' + $_.Exception.Message)
}
Write-Log 'bubble process exiting'
