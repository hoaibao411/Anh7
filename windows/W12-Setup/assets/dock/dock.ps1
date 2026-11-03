# =====================================================================
#  ANH 7 DOCK — thanh tác vụ kiểu Win12 cho Windows (một phần của Anh 7 cho Windows)
#
#  Chạy:   powershell -STA -WindowStyle Hidden -File dock.ps1
#  Tắt:    powershell -File dock.ps1 -Stop      (thanh tác vụ Windows hiện lại)
#
#  Khi chạy, Dock ẩn thanh tác vụ Windows và tự chiếm dải dưới màn hình.
#  Khi thoát (hoặc -Stop), mọi thứ trả lại như cũ.
#  Cấu hình app ghim: %LOCALAPPDATA%\Anh7-W12\dock.json
# =====================================================================
param([switch]$Stop)
$ErrorActionPreference = 'Stop'

$Here      = $PSScriptRoot
$DataDir   = Join-Path $env:LOCALAPPDATA 'Anh7-W12'
$ConfFile  = Join-Path $DataDir 'dock.json'
$StateFile = Join-Path $DataDir 'dock-state.json'
$LogFile   = Join-Path $env:TEMP 'anh7-dock-loi.txt'
New-Item -ItemType Directory -Path $DataDir -Force | Out-Null

Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $Here 'Native.cs')))

# Trả thanh tác vụ Windows về như trước khi chạy Dock
function Restore-Taskbar {
    # Chỉ trả chế độ tự ẩn khi Dock đã từng đổi nó (có file trạng thái)
    if (Test-Path -LiteralPath $StateFile) {
        $wasAutoHide = $false
        try { $wasAutoHide = [bool](Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json).autoHide } catch { }
        [Anh7Dock.Native]::SetTaskbarAutoHide($wasAutoHide)
        Remove-Item -LiteralPath $StateFile -Force -ErrorAction SilentlyContinue
    }
    [Anh7Dock.Native]::ShowTaskbar()
}

# ---------- Chế độ tắt Dock ----------
if ($Stop) {
    $evt = $null
    if ([Threading.EventWaitHandle]::TryOpenExisting('Anh7Dock.Quit', [ref]$evt)) {
        [void]$evt.Set()
        Start-Sleep -Milliseconds 1500
    }
    Restore-Taskbar   # phòng khi Dock đã bị tắt đột ngột
    return
}

# ---------- Chỉ chạy 1 Dock ----------
$created = $false
$mutex = New-Object Threading.Mutex($true, 'Anh7Dock.Single', [ref]$created)
if (-not $created) { return }
$quitEvt = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::AutoReset, 'Anh7Dock.Quit')

try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Drawing, System.Windows.Forms

    # ---------- Cấu hình app ghim ----------
    function Default-Pinned {
        $list = @(
            [pscustomobject]@{ name = 'File Explorer'; path = (Join-Path $env:WINDIR 'explorer.exe'); icon = 'folder' }
        )
        $edge = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'
        if (-not (Test-Path $edge)) { $edge = Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe' }
        if (Test-Path $edge) { $list += [pscustomobject]@{ name = 'Microsoft Edge'; path = $edge } }
        foreach ($c in @((Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
                         (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
                         (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe'))) {
            if (Test-Path $c) { $list += [pscustomobject]@{ name = 'Google Chrome'; path = $c }; break }
        }
        $list += [pscustomobject]@{ name = 'Cài đặt'; path = 'ms-settings:'; icon = 'settings' }
        $list += [pscustomobject]@{ name = 'Microsoft Store'; path = 'ms-windows-store:'; icon = 'store' }
        return $list
    }
    function Load-Conf {
        if (Test-Path -LiteralPath $ConfFile) {
            try { return (Get-Content -LiteralPath $ConfFile -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { }
        }
        $c = [pscustomobject]@{ theme = 'light'; pinned = @(Default-Pinned) }
        Save-Conf $c
        return $c
    }
    function Save-Conf($c) { $c | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ConfFile -Encoding UTF8 }
    $script:conf = Load-Conf

    # ---------- Giao diện ----------
    $win = [Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $Here 'dock.xaml'), [Text.Encoding]::UTF8))
    $ui = @{}
    foreach ($n in @('AppsPanel', 'BtnOrb', 'ImgOrb', 'BtnStatus', 'IcBattery', 'IcNet', 'IcBt', 'IcVol', 'BtnClock', 'TxtTime', 'TxtDate')) {
        $ui[$n] = $win.FindName($n)
    }
    # Lưu ý: PowerShell không phân biệt hoa/thường, nên tên biến font phải khác hẳn tham số $glyph
    $IconFont = New-Object Windows.Media.FontFamily('Segoe Fluent Icons, Segoe MDL2 Assets')
    function G([string]$hex) { return [string][char][Convert]::ToInt32($hex, 16) }

    # Màu Dock: theme = 'light' (mặc định, giống Win12) | 'dark' | 'auto' (theo Windows)
    $brushConv = New-Object Windows.Media.BrushConverter
    function Brush([string]$c) {
        [Windows.Media.Brush]$b = $brushConv.ConvertFromString($c)
        $b.Freeze()
        return ,$b
    }
    $Themes = @{
        light = @{ PillBg = '#E6FFFFFF'; PillBorder = '#99FFFFFF'; Ink = '#1B1B2F'; Hover = '#1A2A1E5C'; Dot = '#6D6AF0' }
        dark  = @{ PillBg = '#D91C2033'; PillBorder = '#33FFFFFF'; Ink = '#F0F2FA'; Hover = '#26FFFFFF'; Dot = '#8FB4FF' }
    }
    function Apply-Theme {
        $t = [string]$script:conf.theme
        if (-not $t) { $t = 'light' }
        if ($t -eq 'auto') {
            $t = 'light'
            try {
                if (-not [bool](Get-ItemPropertyValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'SystemUsesLightTheme')) { $t = 'dark' }
            } catch { }
        }
        if (-not $Themes.ContainsKey($t)) { $t = 'light' }
        foreach ($k in $Themes[$t].Keys) {
            try { $win.Resources[$k] = (Brush $Themes[$t][$k]) } catch { }
        }
    }
    Apply-Theme

    function Load-Png([string]$path) {
        $bi = New-Object Windows.Media.Imaging.BitmapImage
        $bi.BeginInit(); $bi.UriSource = New-Object Uri($path); $bi.CacheOption = 'OnLoad'; $bi.EndInit()
        return $bi
    }
    $ui.ImgOrb.Source = Load-Png (Join-Path $Here 'orb.png')
    $startImg = Load-Png (Join-Path $Here 'start.png')
    $Icons = @{}
    foreach ($n in @('search', 'tasks', 'folder', 'settings', 'store', 'app')) {
        $f = Join-Path $Here ('ic-' + $n + '.png')
        if (Test-Path -LiteralPath $f) { $Icons[$n] = Load-Png $f }
    }
    # Cấu hình cũ dùng mã glyph -> đổi sang icon màu
    $GlyphToIcon = @{ 'E8B7' = 'folder'; 'E713' = 'settings'; 'E719' = 'store'; 'E71D' = 'app'; 'E721' = 'search'; 'E7C4' = 'tasks' }
    function Pin-Icon($p) {
        if ($p.icon -and $Icons.ContainsKey([string]$p.icon)) { return $Icons[[string]$p.icon] }
        if ($p.glyph -and $GlyphToIcon.ContainsKey(([string]$p.glyph).ToUpperInvariant())) { return $Icons[$GlyphToIcon[([string]$p.glyph).ToUpperInvariant()]] }
        $img = Exe-Icon ([string]$p.path)
        if ($img) { return $img }
        return $Icons['app']
    }

    # Icon của file .exe (lưu đệm theo đường dẫn)
    $iconCache = @{}
    function Exe-Icon([string]$path) {
        $k = $path.ToLowerInvariant()
        if ($iconCache.ContainsKey($k)) { return $iconCache[$k] }
        $src = $null
        try {
            $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($path)
            $src = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon($ico.Handle, [Windows.Int32Rect]::Empty,
                   [Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
            $src.Freeze()
            $ico.Dispose()
        } catch { }
        $iconCache[$k] = $src
        return $src
    }

    # Tạo 1 nút trên khối app: icon + chấm báo đang chạy bên dưới
    function New-DockButton([string]$tip, $image, [string]$glyph, [int]$running, [bool]$active) {
        $b = New-Object Windows.Controls.Button
        $b.Style = $win.Resources['DockBtn']
        $b.Width = 44; $b.Height = 44; $b.ToolTip = $tip
        $g = New-Object Windows.Controls.Grid
        if ($image) {
            $img = New-Object Windows.Controls.Image
            $img.Source = $image; $img.Width = 28; $img.Height = 28
            [Windows.Media.RenderOptions]::SetBitmapScalingMode($img, 'HighQuality')
            [void]$g.Children.Add($img)
        } else {
            $t = New-Object Windows.Controls.TextBlock
            $t.Text = G $glyph; $t.FontFamily = $IconFont; $t.FontSize = 20
            $t.HorizontalAlignment = 'Center'; $t.VerticalAlignment = 'Center'
            $t.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Ink')
            [void]$g.Children.Add($t)
        }
        if ($running -gt 0) {
            $dot = New-Object Windows.Shapes.Rectangle
            $dot.Height = 3; $dot.RadiusX = 1.5; $dot.RadiusY = 1.5
            $dot.Width = $(if ($active) { 16 } else { 6 })
            $dot.VerticalAlignment = 'Bottom'; $dot.HorizontalAlignment = 'Center'
            $dot.Margin = New-Object Windows.Thickness(0, 0, 0, -6)
            $dot.SetResourceReference([Windows.Shapes.Shape]::FillProperty, 'Dot')
            [void]$g.Children.Add($dot)
        }
        $b.Content = $g
        return $b
    }

    function Run-Target([string]$path) {
        try { Start-Process -FilePath $path } catch { [System.Windows.MessageBox]::Show('Không mở được: ' + $path) | Out-Null }
    }

    # ---------- Dựng khối app ----------
    $script:lastSig = ''
    function Build-Apps([bool]$force) {
        $wins = [Anh7Dock.Native]::AppWindows($PID)
        $fg = [Anh7Dock.Native]::GetForegroundWindow()
        $sig = ($wins | ForEach-Object { '{0}:{1}:{2}' -f $_.Handle, $_.Minimized, ($_.Handle -eq $fg) }) -join '|'
        if (-not $force -and $sig -eq $script:lastSig) { return }
        $script:lastSig = $sig

        $panel = $ui.AppsPanel
        $panel.Children.Clear()

        # Start, Tìm kiếm, Task view
        $b = New-DockButton 'Start' $startImg $null 0 $false
        $b.Add_Click({ [Anh7Dock.Native]::Keys([byte[]]@(0x5B)) }); [void]$panel.Children.Add($b)
        $b = New-DockButton 'Tìm kiếm (Win+S)' $Icons['search'] $null 0 $false
        $b.Add_Click({ [Anh7Dock.Native]::Keys([byte[]]@(0x5B, 0x53)) }); [void]$panel.Children.Add($b)
        $b = New-DockButton 'Các cửa sổ (Win+Tab)' $Icons['tasks'] $null 0 $false
        $b.Add_Click({ [Anh7Dock.Native]::Keys([byte[]]@(0x5B, 0x09)) }); [void]$panel.Children.Add($b)

        # Gom cửa sổ theo file chạy
        $groups = [ordered]@{}
        foreach ($w in $wins) {
            $k = if ($w.Path) { $w.Path.ToLowerInvariant() } else { 'pid:' + $w.Pid }
            if (-not $groups.Contains($k)) { $groups[$k] = New-Object System.Collections.ArrayList }
            [void]$groups[$k].Add($w)
        }

        # App ghim (kèm chấm nếu đang chạy)
        $used = @{}
        foreach ($p in @($script:conf.pinned)) {
            $k = ([string]$p.path).ToLowerInvariant()
            $ws = if ($groups.Contains($k)) { $groups[$k] } else { $null }
            if ($ws) { $used[$k] = $true }
            $isActive = $ws -and (@($ws | Where-Object { $_.Handle -eq $fg }).Count -gt 0)
            $img = Pin-Icon $p
            $btn = New-DockButton ([string]$p.name) $img $null $(if ($ws) { $ws.Count } else { 0 }) $isActive
            $btn.Tag = @{ Pin = $p; Wins = $ws }
            $btn.Add_Click({ param($s, $e)
                $t = $s.Tag
                if ($t.Wins -and $t.Wins.Count -gt 0) { [Anh7Dock.Native]::ToggleWindow($t.Wins[0].Handle) } else { Run-Target ([string]$t.Pin.path) }
            })
            Add-AppMenu $btn $p $ws
            [void]$panel.Children.Add($btn)
        }

        # App đang chạy nhưng chưa ghim
        foreach ($k in $groups.Keys) {
            if ($used.ContainsKey($k)) { continue }
            $ws = $groups[$k]
            $first = $ws[0]
            $isActive = @($ws | Where-Object { $_.Handle -eq $fg }).Count -gt 0
            $isFrameHost = $k.EndsWith('applicationframehost.exe')
            $img = if ($first.Path -and -not $isFrameHost) { Exe-Icon $first.Path } else { $null }
            if (-not $img) { $img = $Icons['app'] }
            $btn = New-DockButton $first.Title $img $null $ws.Count $isActive
            $btn.Tag = @{ Pin = $null; Wins = $ws }
            $btn.Add_Click({ param($s, $e) [Anh7Dock.Native]::ToggleWindow($s.Tag.Wins[0].Handle) })
            Add-AppMenu $btn $null $ws
            [void]$panel.Children.Add($btn)
        }
    }

    # Chuột phải trên app: ghim / bỏ ghim / đóng cửa sổ
    function Add-AppMenu($btn, $pin, $ws) {
        $m = New-Object Windows.Controls.ContextMenu
        if ($pin) {
            $i = New-Object Windows.Controls.MenuItem; $i.Header = 'Bỏ ghim khỏi Dock'; $i.Tag = $pin
            $i.Add_Click({ param($s, $e)
                $script:conf.pinned = @($script:conf.pinned | Where-Object { $_.path -ne $s.Tag.path })
                Save-Conf $script:conf; Build-Apps $true })
            [void]$m.Items.Add($i)
        } elseif ($ws -and $ws[0].Path -and -not $ws[0].Path.ToLowerInvariant().EndsWith('applicationframehost.exe')) {
            $i = New-Object Windows.Controls.MenuItem; $i.Header = 'Ghim vào Dock'
            $i.Tag = [pscustomobject]@{ name = [IO.Path]::GetFileNameWithoutExtension($ws[0].Path); path = $ws[0].Path }
            $i.Add_Click({ param($s, $e)
                $script:conf.pinned = @($script:conf.pinned) + $s.Tag
                Save-Conf $script:conf; Build-Apps $true })
            [void]$m.Items.Add($i)
        }
        if ($ws -and $ws.Count -gt 0) {
            $i = New-Object Windows.Controls.MenuItem
            $i.Header = $(if ($ws.Count -gt 1) { 'Đóng ' + $ws.Count + ' cửa sổ' } else { 'Đóng cửa sổ' })
            $i.Tag = $ws
            $i.Add_Click({ param($s, $e) foreach ($w in $s.Tag) { [Anh7Dock.Native]::CloseWindow($w.Handle) } })
            [void]$m.Items.Add($i)
        }
        if ($m.Items.Count -gt 0) { $btn.ContextMenu = $m }
    }

    # ---------- Khối trạng thái ----------
    function Update-Status {
        # Pin
        $ps = [System.Windows.Forms.SystemInformation]::PowerStatus
        $noBattery = ($ps.BatteryChargeStatus -band [System.Windows.Forms.BatteryChargeStatus]::NoSystemBattery) -ne 0
        if ($noBattery) {
            $ui.IcBattery.Visibility = 'Collapsed'
        } else {
            $pct = [int][math]::Round($ps.BatteryLifePercent * 100)
            $charging = $ps.PowerLineStatus -eq [System.Windows.Forms.PowerLineStatus]::Online
            $ui.IcBattery.Text = $(if ($charging) { G 'E83E' } elseif ($pct -ge 95) { G 'E83F' } else { G ('{0:X}' -f [int](0xE850 + [math]::Floor($pct / 10))) })
            $ui.IcBattery.ToolTip = 'Pin ' + $pct + '%' + $(if ($charging) { ' · đang sạc' } else { '' })
            $ui.IcBattery.Visibility = 'Visible'
        }
        # Mạng
        $nics = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
                Where-Object { $_.OperationalStatus -eq 'Up' -and $_.NetworkInterfaceType -ne 'Loopback' -and $_.NetworkInterfaceType -ne 'Tunnel' }
        $wifi = @($nics | Where-Object { $_.NetworkInterfaceType -eq 'Wireless80211' }).Count -gt 0
        $wired = @($nics | Where-Object { $_.NetworkInterfaceType -eq 'Ethernet' }).Count -gt 0
        if ($wifi) { $ui.IcNet.Text = G 'E701'; $ui.IcNet.Opacity = 1; $ui.IcNet.ToolTip = 'Wi‑Fi đã kết nối' }
        elseif ($wired) { $ui.IcNet.Text = G 'E839'; $ui.IcNet.Opacity = 1; $ui.IcNet.ToolTip = 'Mạng dây đã kết nối' }
        else { $ui.IcNet.Text = G 'E701'; $ui.IcNet.Opacity = 0.35; $ui.IcNet.ToolTip = 'Chưa kết nối mạng' }
        $ui.IcBt.Text = G 'E702'
        $ui.IcVol.Text = G 'E767'
    }
    foreach ($n in @('IcBattery', 'IcNet', 'IcBt', 'IcVol')) {
        $ui[$n].SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Ink')
    }

    function Update-Clock {
        $now = Get-Date
        $ui.TxtTime.Text = $now.ToString('HH:mm:ss')
        $ui.TxtDate.Text = $now.ToString('yyyy/MM/dd')
    }

    # ---------- Nút ----------
    $ui.BtnStatus.Add_Click({ [Anh7Dock.Native]::Keys([byte[]]@(0x5B, 0x41)) })   # Win+A
    $ui.BtnClock.Add_Click({ [Anh7Dock.Native]::Keys([byte[]]@(0x5B, 0x4E)) })    # Win+N

    $orbMenu = New-Object Windows.Controls.ContextMenu
    foreach ($item in @(
        @('Hiện desktop (Win+D)', { [Anh7Dock.Native]::Keys([byte[]]@(0x5B, 0x44)) }),
        @('Sửa danh sách app ghim', { Start-Process notepad.exe -ArgumentList ('"' + $ConfFile + '"') }),
        @('Đổi màu Dock (sáng / tối / theo Windows)', {
            $next = @{ light = 'dark'; dark = 'auto'; auto = 'light' }
            $cur = [string]$script:conf.theme; if (-not $cur) { $cur = 'light' }
            $script:conf | Add-Member -NotePropertyName theme -NotePropertyValue $next[$cur] -Force
            Save-Conf $script:conf; Apply-Theme; Build-Apps $true }),
        @('Tải lại Dock', { $script:conf = Load-Conf; Apply-Theme; Build-Apps $true }),
        @('Thoát Anh 7 Dock (hiện lại thanh tác vụ Windows)', { $win.Close() })
    )) {
        $mi = New-Object Windows.Controls.MenuItem
        $mi.Header = $item[0]
        $mi.Add_Click($item[1])
        [void]$orbMenu.Items.Add($mi)
    }
    $ui.BtnOrb.ContextMenu = $orbMenu
    $ui.BtnOrb.Add_Click({ $orbMenu.PlacementTarget = $ui.BtnOrb; $orbMenu.Placement = 'Top'; $orbMenu.IsOpen = $true })

    # ---------- Vị trí: dải dưới màn hình chính, giữ chỗ để cửa sổ phóng to không che Dock ----------
    $script:hwnd = [IntPtr]::Zero
    $win.Add_SourceInitialized({
        $script:hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($win)).Handle
        [Anh7Dock.Native]::MakeDockWindow($script:hwnd)

        # Lưu trạng thái thanh tác vụ gốc (1 lần) rồi ẩn nó
        if (-not (Test-Path -LiteralPath $StateFile)) {
            $st = [Anh7Dock.Native]::GetTaskbarState()
            @{ autoHide = [bool]($st -band 1) } | ConvertTo-Json | Set-Content -LiteralPath $StateFile -Encoding UTF8
        }
        [Anh7Dock.Native]::SetTaskbarAutoHide($true)
        [void][Anh7Dock.Native]::HideTaskbar()

        $scale = [System.Windows.PresentationSource]::FromVisual($win).CompositionTarget.TransformToDevice.M11
        $scr = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $hPx = [int][math]::Round(68 * $scale)
        [Anh7Dock.Native]::RegisterAppBar($script:hwnd, 0x0501)
        $rc = [Anh7Dock.Native]::PlaceAppBar($script:hwnd, $scr.Width, $scr.Height, $hPx)
        $win.Left = $rc.Left / $scale
        $win.Top = $rc.Top / $scale
        $win.Width = ($rc.Right - $rc.Left) / $scale
        $win.Height = ($rc.Bottom - $rc.Top) / $scale
    })

    $win.Add_Closing({
        try { if ($script:hwnd -ne [IntPtr]::Zero) { [Anh7Dock.Native]::RemoveAppBar($script:hwnd) } } catch { }
        Restore-Taskbar
    })

    # ---------- Đồng hồ hẹn giờ ----------
    $fast = New-Object Windows.Threading.DispatcherTimer
    $fast.Interval = [TimeSpan]::FromMilliseconds(500)
    $script:tick = 0
    $fast.Add_Tick({
        if ($quitEvt.WaitOne(0)) { $win.Close(); return }
        # Windows hay tự hiện lại thanh tác vụ -> ẩn lại (trừ lúc đang mở Start/Tìm kiếm)
        if (-not [Anh7Dock.Native]::ShellPopupOpen()) { [void][Anh7Dock.Native]::HideTaskbar() }
        Update-Clock
        try { Build-Apps $false } catch { }
        $script:tick++
        if ($script:tick % 20 -eq 0) { try { Update-Status } catch { } }
    })

    Update-Clock
    Update-Status
    Build-Apps $true
    $fast.Start()
    [void]$win.ShowDialog()
}
catch {
    $_ | Out-String | Set-Content -LiteralPath $LogFile -Encoding UTF8
    try { Restore-Taskbar } catch { }
}
finally {
    try { $mutex.ReleaseMutex() } catch { }
}
