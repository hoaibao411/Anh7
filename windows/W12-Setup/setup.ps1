# =====================================================================
#  ANH 7 CHO WINDOWS — Giao diện W12 (phiên bản Windows của Anh 7)
#  Anh 7 bản gốc chạy trên macOS · Mã nguồn mở (EPL-2.0)
#
#  Trình cài này CHỈ đổi cài đặt giao diện của tài khoản đang dùng (HKCU):
#    hình nền, chế độ tối, màu nhấn, hiệu ứng trong suốt, căn giữa thanh tác vụ.
#  - Không cần quyền quản trị, không sửa file hệ thống, không dùng Internet.
#  - Trước khi đổi, lưu lại cài đặt cũ vào %LOCALAPPDATA%\Anh7-W12\backup.json
#    để khôi phục bất cứ lúc nào.
# =====================================================================
$ErrorActionPreference = 'Stop'

# ---------- Thông tin dự án (sửa ở đây nếu cần) ----------
$App = @{
    Name    = 'Anh 7 cho Windows'
    Version = '1.4.0'
    Author  = 'hoaibao411'
    Project = 'Anh 7'
    Repo    = 'https://github.com/hoaibao411/Anh7'
    License = 'Mã nguồn mở EPL-2.0'
}
$AccentHex = '#1F5FD1'     # màu nhấn (màu logo W12)

$Root       = $PSScriptRoot
$Assets     = Join-Path $Root 'assets'
$DataDir    = Join-Path $env:LOCALAPPDATA 'Anh7-W12'
$WpDir      = Join-Path $DataDir 'HinhNen'
$BackupFile = Join-Path $DataDir 'backup.json'
$LogFile    = Join-Path $env:TEMP 'anh7-w12-loi.txt'
$Wallpapers = @('W12-bongbong.jpg', 'W12-dem.jpg', 'W12-kinh.jpg', 'W12-binhminh.jpg', 'W12-toigian.jpg')
$IsWin11    = [Environment]::OSVersion.Version.Build -ge 22000
$DockDir      = Join-Path $DataDir 'Dock'
$StartMenuDir = Join-Path ([Environment]::GetFolderPath('Programs')) 'Anh 7'
$StartupLnk   = Join-Path ([Environment]::GetFolderPath('Startup')) 'Anh 7 Dock.lnk'
$PsExe        = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'

# ---------- Các cài đặt sẽ đụng tới (để sao lưu / khôi phục) ----------
$P_Personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$P_Dwm         = 'HKCU:\Software\Microsoft\Windows\DWM'
$P_Accent      = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
$P_Advanced    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$P_Desktop     = 'HKCU:\Control Panel\Desktop'
$Tracked = @(
    @{ Path = $P_Personalize; Names = @('AppsUseLightTheme', 'SystemUsesLightTheme', 'EnableTransparency', 'ColorPrevalence') },
    @{ Path = $P_Dwm;         Names = @('AccentColor', 'ColorizationColor', 'ColorizationAfterglow', 'ColorPrevalence') },
    @{ Path = $P_Accent;      Names = @('AccentColorMenu', 'StartColorMenu', 'AccentPalette') },
    @{ Path = $P_Advanced;    Names = @('TaskbarAl') },
    @{ Path = $P_Desktop;     Names = @('Wallpaper', 'WallpaperStyle', 'TileWallpaper') }
)

try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

    # Gọi Windows để đổi hình nền và báo các cửa sổ cập nhật giao diện
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class W12Native {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
                                                   uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
    public static void SetWallpaper(string path) {
        // SPI_SETDESKWALLPAPER = 20; SPIF_UPDATEINIFILE | SPIF_SENDCHANGE = 3
        SystemParametersInfo(20, 0, path, 3);
    }
    public static void Broadcast(string area) {
        UIntPtr r;
        // HWND_BROADCAST = 0xFFFF; WM_SETTINGCHANGE = 0x1A; SMTO_ABORTIFHUNG = 2
        SendMessageTimeout((IntPtr)0xFFFF, 0x1A, UIntPtr.Zero, area, 2, 3000, out r);
    }
}
'@

    # =================================================================
    # CÔNG CỤ
    # =================================================================
    function Ensure-Key([string]$path) {
        if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
    }
    function Set-Dword([string]$path, [string]$name, [int]$value) {
        Ensure-Key $path
        New-ItemProperty -LiteralPath $path -Name $name -Value $value -PropertyType DWord -Force | Out-Null
    }
    function Set-Str([string]$path, [string]$name, [string]$value) {
        Ensure-Key $path
        New-ItemProperty -LiteralPath $path -Name $name -Value $value -PropertyType String -Force | Out-Null
    }
    # 4 byte (thứ tự little-endian) -> số DWORD có dấu để ghi vào Registry
    function Dword-FromBytes([byte[]]$b) { return [BitConverter]::ToInt32($b, 0) }
    function Hex-ToRgb([string]$hex) {
        $h = $hex.TrimStart('#')
        return @([Convert]::ToByte($h.Substring(0, 2), 16), [Convert]::ToByte($h.Substring(2, 2), 16), [Convert]::ToByte($h.Substring(4, 2), 16))
    }
    # Pha màu: t > 0 pha trắng, t < 0 pha đen
    function Mix-Rgb($rgb, [double]$t) {
        $target = if ($t -ge 0) { 255 } else { 0 }
        $k = [math]::Abs($t)
        return @($rgb | ForEach-Object { [byte][math]::Round($_ + ($target - $_) * $k) })
    }

    # ---------- Sao lưu ----------
    function Read-Value([string]$path, [string]$name) {
        if (-not (Test-Path -LiteralPath $path)) { return $null }
        $key = Get-Item -LiteralPath $path
        $v = $key.GetValue($name, $null, 'DoNotExpandEnvironmentNames')
        if ($null -eq $v) { return $null }
        $kind = $key.GetValueKind($name).ToString()
        if ($kind -eq 'Binary') { $v = [Convert]::ToBase64String([byte[]]$v) }
        return @{ Value = $v; Kind = $kind }
    }
    function Save-Backup {
        if (Test-Path -LiteralPath $BackupFile) { return }   # đã có bản gốc -> giữ nguyên, không ghi đè
        New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
        $items = @()
        foreach ($t in $Tracked) {
            foreach ($n in $t.Names) {
                $r = Read-Value $t.Path $n
                $items += [pscustomobject]@{
                    Path = $t.Path; Name = $n; Exists = ($null -ne $r)
                    Value = $(if ($r) { $r.Value } else { $null }); Kind = $(if ($r) { $r.Kind } else { $null })
                }
            }
        }
        $obj = [pscustomobject]@{ Created = (Get-Date).ToString('s'); Version = $App.Version; Items = $items }
        $obj | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $BackupFile -Encoding UTF8
    }

    function Restore-Backup {
        $b = Get-Content -LiteralPath $BackupFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($e in $b.Items) {
            if ($e.Exists) {
                Ensure-Key $e.Path
                switch ($e.Kind) {
                    'DWord'        { New-ItemProperty -LiteralPath $e.Path -Name $e.Name -Value ([int]$e.Value) -PropertyType DWord -Force | Out-Null }
                    'QWord'        { New-ItemProperty -LiteralPath $e.Path -Name $e.Name -Value ([long]$e.Value) -PropertyType QWord -Force | Out-Null }
                    'Binary'       { New-ItemProperty -LiteralPath $e.Path -Name $e.Name -Value ([Convert]::FromBase64String($e.Value)) -PropertyType Binary -Force | Out-Null }
                    'ExpandString' { New-ItemProperty -LiteralPath $e.Path -Name $e.Name -Value ([string]$e.Value) -PropertyType ExpandString -Force | Out-Null }
                    default        { New-ItemProperty -LiteralPath $e.Path -Name $e.Name -Value ([string]$e.Value) -PropertyType String -Force | Out-Null }
                }
            } else {
                if (Test-Path -LiteralPath $e.Path) {
                    Remove-ItemProperty -LiteralPath $e.Path -Name $e.Name -ErrorAction SilentlyContinue
                }
            }
        }
        $wp = ($b.Items | Where-Object { $_.Name -eq 'Wallpaper' -and $_.Path -eq $P_Desktop } | Select-Object -First 1)
        $wpPath = if ($wp -and $wp.Exists) { [Environment]::ExpandEnvironmentVariables([string]$wp.Value) } else { '' }
        [W12Native]::SetWallpaper($wpPath)
        Refresh-Shell
        Remove-Item -LiteralPath $BackupFile -Force
    }

    function Refresh-Shell {
        foreach ($area in @('ImmersiveColorSet', 'WindowsThemeElement', 'TraySettings', 'Policy')) { [W12Native]::Broadcast($area) }
    }

    # =================================================================
    # GIAO DIỆN
    # =================================================================
    $xaml = [IO.File]::ReadAllText((Join-Path $Assets 'ui.xaml'), [Text.Encoding]::UTF8)
    $win = [Windows.Markup.XamlReader]::Parse($xaml)
    $ui = @{}
    foreach ($n in @('Logo', 'TxtVersion', 'TxtSideAuthor', 'S1', 'S2', 'S3', 'S4', 'S5', 'TopBar', 'BtnClose',
                     'Page1', 'Page2', 'Page3', 'Page4', 'Page5', 'TxtAuthor', 'TxtProject', 'TxtVer2', 'TxtRepo', 'TxtLicense',
                     'RestoreCard', 'BtnRestore', 'TxtDisclaimer', 'ChkAgree', 'R1', 'R2', 'R3', 'R4', 'R5', 'Img1', 'Img2', 'Img3', 'Img4', 'Img5',
                     'TgDark', 'TgAccent', 'TgTrans', 'TgCenter', 'TgTaskbar', 'TgDock', 'TgDockStartup', 'TxtWorking', 'ProgFill', 'TxtLog', 'TxtDoneTitle', 'TxtDoneBody',
                     'BtnOpenWp', 'BtnGithub', 'NavBar', 'BtnNext', 'BtnBack', 'TxtNavHint')) {
        $ui[$n] = $win.FindName($n)
    }

    function Load-Image([string]$path, [int]$decodeWidth = 0) {
        $bi = New-Object System.Windows.Media.Imaging.BitmapImage
        $bi.BeginInit()
        $bi.UriSource = New-Object System.Uri($path)
        $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        if ($decodeWidth -gt 0) { $bi.DecodePixelWidth = $decodeWidth }
        $bi.EndInit()
        return $bi
    }

    # Nội dung
    $ui.Logo.Source = Load-Image (Join-Path $Assets 'logo.png') 240
    $win.Icon = Load-Image (Join-Path $Assets 'icon.png') 64
    $ui.TxtVersion.Text = 'Phiên bản ' + $App.Version
    $ui.TxtSideAuthor.Text = 'Một phần của ' + $App.Project + ' · ' + $App.Author
    $ui.TxtAuthor.Text = $App.Author
    $ui.TxtProject.Text = 'Windows 10/11 (bản gốc ' + $App.Project + ' chạy trên macOS)'
    $ui.TxtVer2.Text = $App.Version
    $ui.TxtRepo.Text = $App.Repo.Replace('https://', '')
    $ui.TxtLicense.Text = $App.License
    $ui.TxtDisclaimer.Text = 'Đây là phiên bản Windows của ' + $App.Project + ', dự án cá nhân, độc lập của ' + $App.Author + ', phát hành miễn phí. ' +
        'Dự án không liên kết và không được Microsoft bảo trợ. "Windows" là thương hiệu của Microsoft Corporation. ' +
        'Bạn tự chịu trách nhiệm khi cài đặt; mọi thay đổi đều có thể khôi phục.'
    for ($i = 0; $i -lt $Wallpapers.Count; $i++) {
        $ui['Img' + ($i + 1)].Source = Load-Image (Join-Path $Assets ('thumbs\' + $Wallpapers[$i])) 360
    }
    if (-not $IsWin11) {
        $ui.TgCenter.IsChecked = $false
        $ui.TgCenter.IsEnabled = $false
        $ui.TgCenter.Content = 'Căn giữa thanh tác vụ (chỉ có trên Windows 11)'
    }
    if (Test-Path -LiteralPath $BackupFile) { $ui.RestoreCard.Visibility = 'Visible' }

    # ---------- Điều hướng ----------
    $script:page = 1
    $script:busy = $false
    function Show-Page([int]$n) {
        $script:page = $n
        for ($i = 1; $i -le 5; $i++) {
            $ui['Page' + $i].Visibility = $(if ($i -eq $n) { 'Visible' } else { 'Collapsed' })
            $ui['S' + $i].Opacity = $(if ($i -eq $n) { 1.0 } elseif ($i -lt $n) { 0.75 } else { 0.4 })
        }
        $ui.BtnBack.Visibility = $(if ($n -in 2, 3) { 'Visible' } else { 'Collapsed' })
        $ui.NavBar.Visibility = $(if ($n -eq 4) { 'Hidden' } else { 'Visible' })
        switch ($n) {
            1 { $ui.BtnNext.Content = 'Tiếp tục'; $ui.BtnNext.IsEnabled = $true; $ui.TxtNavHint.Text = 'Bước 1 / 3' }
            2 { $ui.BtnNext.Content = 'Tiếp tục'; $ui.BtnNext.IsEnabled = [bool]$ui.ChkAgree.IsChecked; $ui.TxtNavHint.Text = 'Bước 2 / 3' }
            3 { $ui.BtnNext.Content = 'Cài đặt';  $ui.BtnNext.IsEnabled = $true; $ui.TxtNavHint.Text = 'Bước 3 / 3' }
            5 { $ui.BtnNext.Content = 'Đóng';     $ui.BtnNext.IsEnabled = $true; $ui.TxtNavHint.Text = '' }
        }
    }

    # Cho giao diện kịp vẽ lại giữa các bước cài
    function Pump {
        $win.Dispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Background)
    }
    function Step([double]$pct, [string]$msg) {
        $ui.ProgFill.Width = [math]::Max(0, ($ui.ProgFill.Parent.ActualWidth) * $pct)
        $ui.TxtLog.Text += '✓  ' + $msg + "`n"
        Pump
        Start-Sleep -Milliseconds 220
        Pump
    }

    # ---------- Thanh tác vụ trong suốt: TranslucentTB (bên thứ ba, Microsoft Store) ----------
    # Chỉ chạy khi người dùng bật tùy chọn. Cài qua winget (nguồn msstore); không được thì mở trang Store.
    $StoreId = '9PF4KZ2VN4W9'
    function Install-TaskbarTool {
        $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
        if ($winget) {
            $ui.TxtLog.Text += '…  Đang tải TranslucentTB từ Microsoft Store (có thể mất 1–2 phút)' + "`n"
            Pump
            $p = Start-Process -FilePath $winget.Source -WindowStyle Hidden -PassThru -ArgumentList @(
                'install', '--id', $StoreId, '--source', 'msstore',
                '--accept-package-agreements', '--accept-source-agreements', '--silent')
            $null = $p.Handle   # giữ handle để đọc được mã kết thúc
            $sw = [Diagnostics.Stopwatch]::StartNew()
            while (-not $p.HasExited -and $sw.Elapsed.TotalMinutes -lt 5) { Pump; Start-Sleep -Milliseconds 200 }
            if ($p.HasExited -and $p.ExitCode -eq 0) { return $true }
        }
        # Không có winget / lỗi mạng / đã cài sẵn -> mở trang Store để người dùng tự bấm
        Start-Process ('ms-windows-store://pdp/?productid=' + $StoreId)
        return $false
    }

    # ---------- ANH 7 DOCK ----------
    function Stop-Dock {
        $dockPs = Join-Path $DockDir 'dock.ps1'
        if (-not (Test-Path -LiteralPath $dockPs)) { return }
        $p = Start-Process -FilePath $PsExe -WindowStyle Hidden -PassThru -ArgumentList (
            '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $dockPs + '" -Stop')
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while (-not $p.HasExited -and $sw.Elapsed.TotalSeconds -lt 15) { Pump; Start-Sleep -Milliseconds 150 }
    }
    # WScript.Shell không lưu được đường dẫn có dấu tiếng Việt -> lưu tên tạm không dấu rồi đổi tên
    function New-Shortcut([string]$lnk, [string]$arguments, [string]$desc) {
        $tmp = Join-Path ([IO.Path]::GetDirectoryName($lnk)) ('anh7-' + [Guid]::NewGuid().ToString('N') + '.lnk')
        $sh = New-Object -ComObject WScript.Shell
        $sc = $sh.CreateShortcut($tmp)
        $sc.TargetPath = $PsExe
        $sc.Arguments = $arguments
        $sc.WorkingDirectory = $DockDir
        $sc.WindowStyle = 7
        $sc.IconLocation = (Join-Path $DockDir 'anh7.ico') + ',0'
        $sc.Description = $desc
        $sc.Save()
        if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force }
        Move-Item -LiteralPath $tmp -Destination $lnk -Force
    }
    function Install-Dock([bool]$startup) {
        Stop-Dock
        New-Item -ItemType Directory -Path $DockDir -Force | Out-Null
        Copy-Item -Path (Join-Path $Assets 'dock\*') -Destination $DockDir -Recurse -Force
        $runArgs = '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "' + (Join-Path $DockDir 'dock.ps1') + '"'
        New-Item -ItemType Directory -Path $StartMenuDir -Force | Out-Null
        New-Shortcut (Join-Path $StartMenuDir 'Anh 7 Dock.lnk') $runArgs 'Bật thanh tác vụ kiểu Win12 của Anh 7'
        New-Shortcut (Join-Path $StartMenuDir 'Tắt Anh 7 Dock.lnk') ($runArgs + ' -Stop') 'Tắt Anh 7 Dock, hiện lại thanh tác vụ Windows'
        if ($startup) { New-Shortcut $StartupLnk $runArgs 'Anh 7 Dock' }
        elseif (Test-Path -LiteralPath $StartupLnk) { Remove-Item -LiteralPath $StartupLnk -Force }
        Start-Process -FilePath $PsExe -ArgumentList $runArgs -WindowStyle Hidden
    }
    function Remove-Dock {
        Stop-Dock
        foreach ($p in @($StartupLnk, $StartMenuDir, $DockDir)) {
            if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    # ---------- CÀI ĐẶT ----------
    function Install-Theme {
        $script:busy = $true
        Show-Page 4
        $ui.TxtWorking.Text = 'Đang áp dụng giao diện W12…'
        $ui.TxtLog.Text = ''
        Pump
        try {
            Save-Backup
            Step 0.15 'Đã lưu giao diện hiện tại để khôi phục khi cần'

            New-Item -ItemType Directory -Path $WpDir -Force | Out-Null
            foreach ($f in $Wallpapers) { Copy-Item -LiteralPath (Join-Path $Assets ('wallpapers\' + $f)) -Destination $WpDir -Force }
            $idx = 0
            foreach ($r in @('R1', 'R2', 'R3', 'R4', 'R5')) { if ($ui[$r].IsChecked) { break }; $idx++ }
            if ($idx -ge $Wallpapers.Count) { $idx = 0 }
            $wpPath = Join-Path $WpDir $Wallpapers[$idx]
            Set-Str $P_Desktop 'WallpaperStyle' '10'   # lấp đầy màn hình, giữ tỉ lệ
            Set-Str $P_Desktop 'TileWallpaper' '0'
            [W12Native]::SetWallpaper($wpPath)
            Step 0.35 'Đã đặt hình nền W12'

            if ($ui.TgDark.IsChecked) {
                Set-Dword $P_Personalize 'AppsUseLightTheme' 0
                Set-Dword $P_Personalize 'SystemUsesLightTheme' 0
                Step 0.5 'Đã bật chế độ tối'
            }

            if ($ui.TgAccent.IsChecked) {
                $rgb = Hex-ToRgb $AccentHex
                # AccentColorMenu / AccentColor dùng dạng ABGR; ColorizationColor dùng ARGB
                $abgr = Dword-FromBytes ([byte[]]@($rgb[0], $rgb[1], $rgb[2], 255))
                $argb = Dword-FromBytes ([byte[]]@($rgb[2], $rgb[1], $rgb[0], 0xC4))
                # Bảng 8 sắc độ (R,G,B,0) cho Start và thanh tác vụ
                $palette = New-Object System.Collections.Generic.List[byte]
                foreach ($t in @(0.6, 0.4, 0.2, 0.0, -0.25, -0.45, -0.65, -0.8)) {
                    $c = Mix-Rgb $rgb $t
                    $palette.AddRange([byte[]]@($c[0], $c[1], $c[2], 0))
                }
                Ensure-Key $P_Accent
                New-ItemProperty -LiteralPath $P_Accent -Name 'AccentPalette' -Value ($palette.ToArray()) -PropertyType Binary -Force | Out-Null
                Set-Dword $P_Accent 'AccentColorMenu' $abgr
                $start = Mix-Rgb $rgb -0.25
                Set-Dword $P_Accent 'StartColorMenu' (Dword-FromBytes ([byte[]]@($start[0], $start[1], $start[2], 255)))
                Set-Dword $P_Dwm 'AccentColor' $abgr
                Set-Dword $P_Dwm 'ColorizationColor' $argb
                Set-Dword $P_Dwm 'ColorizationAfterglow' $argb
                Set-Dword $P_Dwm 'ColorPrevalence' 1          # viền + thanh tiêu đề cửa sổ
                Set-Dword $P_Personalize 'ColorPrevalence' 1  # Start + thanh tác vụ
                Step 0.7 'Đã áp dụng màu nhấn xanh công nghệ'
            }

            Set-Dword $P_Personalize 'EnableTransparency' $(if ($ui.TgTrans.IsChecked) { 1 } else { 0 })
            Step 0.8 $(if ($ui.TgTrans.IsChecked) { 'Đã bật hiệu ứng trong suốt' } else { 'Đã tắt hiệu ứng trong suốt' })

            if ($IsWin11 -and $ui.TgCenter.IsChecked) {
                Set-Dword $P_Advanced 'TaskbarAl' 1
                Step 0.9 'Đã căn giữa thanh tác vụ'
            }

            $tbNote = ''
            if ($ui.TgTaskbar -and $ui.TgTaskbar.IsChecked) {
                if (Install-TaskbarTool) {
                    Step 0.95 'Đã cài TranslucentTB'
                    $tbNote = ' Mở TranslucentTB từ menu Start, rồi chuột phải biểu tượng của nó ở góc phải thanh tác vụ để chọn kiểu Acrylic (mờ kính) hoặc Clear (trong suốt).'
                } else {
                    Step 0.95 'Đã mở Microsoft Store: bấm Get / Install để cài TranslucentTB'
                    $tbNote = ' Trong Microsoft Store vừa mở, bấm Get để cài TranslucentTB, rồi mở nó từ menu Start.'
                }
            }

            Refresh-Shell
            Step 0.97 'Đã làm mới giao diện Windows'

            if ($ui.TgDock -and $ui.TgDock.IsChecked) {
                Install-Dock ([bool]$ui.TgDockStartup.IsChecked)
                Step 1.0 'Đã bật Anh 7 Dock (thanh tác vụ kiểu Win12)'
                $tbNote += ' Anh 7 Dock đang chạy ở đáy màn hình. Bấm nút tròn trên Dock để sửa app ghim hoặc thoát; muốn tắt hẳn: Start > Anh 7 > Tắt Anh 7 Dock.'
            } else {
                Remove-Dock
                Step 1.0 'Hoàn tất'
            }

            $ui.TxtDoneTitle.Text = 'Hoàn tất!'
            $ui.TxtDoneBody.Text = 'Giao diện W12 của ' + $App.Project + ' đã được áp dụng. Cảm ơn bạn đã dùng thử ' + $App.Project + ' cho Windows của ' + $App.Author + '.' + $tbNote
            $ui.RestoreCard.Visibility = 'Visible'
            Show-Page 5
        } catch {
            $_ | Out-String | Set-Content -LiteralPath $LogFile -Encoding UTF8
            [System.Windows.MessageBox]::Show($win, 'Có lỗi khi cài đặt: ' + $_.Exception.Message + "`n`nGiao diện cũ đã được lưu, bạn có thể bấm Khôi phục.",
                'Anh 7 cho Windows', 'OK', 'Error') | Out-Null
            Show-Page 1
            if (Test-Path -LiteralPath $BackupFile) { $ui.RestoreCard.Visibility = 'Visible' }
        } finally {
            $script:busy = $false
        }
    }

    function Run-Restore {
        $ok = [System.Windows.MessageBox]::Show($win, 'Khôi phục giao diện như trước khi cài W12?', 'Anh 7 cho Windows', 'YesNo', 'Question')
        if ($ok -ne 'Yes') { return }
        $script:busy = $true
        Show-Page 4
        $ui.TxtWorking.Text = 'Đang khôi phục giao diện cũ…'
        $ui.TxtLog.Text = ''
        Pump
        try {
            Step 0.3 'Đang tắt Anh 7 Dock và hiện lại thanh tác vụ Windows'
            Remove-Dock
            Step 0.6 'Đang đọc bản sao lưu'
            Restore-Backup
            Step 1.0 'Đã khôi phục hình nền, màu và chế độ sáng/tối'
            $ui.TxtDoneTitle.Text = 'Đã khôi phục'
            $ui.TxtDoneBody.Text = 'Giao diện đã trở về như trước khi cài W12. Hình nền W12 vẫn được giữ trong thư mục hình nền nếu bạn muốn dùng lại. ' +
                'Nếu đã cài TranslucentTB, gỡ trong Settings > Apps > Installed apps.'
            $ui.RestoreCard.Visibility = 'Collapsed'
            Show-Page 5
        } catch {
            $_ | Out-String | Set-Content -LiteralPath $LogFile -Encoding UTF8
            [System.Windows.MessageBox]::Show($win, 'Không khôi phục được: ' + $_.Exception.Message, 'Anh 7 cho Windows', 'OK', 'Error') | Out-Null
            Show-Page 1
        } finally {
            $script:busy = $false
        }
    }

    # ---------- Sự kiện ----------
    $ui.TopBar.Add_MouseLeftButtonDown({ $win.DragMove() })
    $ui.BtnClose.Add_Click({ if (-not $script:busy) { $win.Close() } })
    $ui.TxtRepo.Add_MouseLeftButtonUp({ Start-Process $App.Repo })
    $ui.BtnGithub.Add_Click({ Start-Process $App.Repo })
    $ui.BtnOpenWp.Add_Click({ if (Test-Path -LiteralPath $WpDir) { Start-Process explorer.exe -ArgumentList ('"' + $WpDir + '"') } })
    $ui.BtnRestore.Add_Click({ Run-Restore })
    $ui.ChkAgree.Add_Click({ if ($script:page -eq 2) { $ui.BtnNext.IsEnabled = [bool]$ui.ChkAgree.IsChecked } })
    $ui.BtnBack.Add_Click({ if ($script:page -gt 1) { Show-Page ($script:page - 1) } })
    $ui.BtnNext.Add_Click({
        switch ($script:page) {
            1 { Show-Page 2 }
            2 { if ($ui.ChkAgree.IsChecked) { Show-Page 3 } }
            3 { Install-Theme }
            5 { $win.Close() }
        }
    })
    $win.Add_Closing({ param($s, $e) if ($script:busy) { $e.Cancel = $true } })

    Show-Page 1
    [void]$win.ShowDialog()
}
catch {
    # Lỗi trước khi cửa sổ hiện ra (vd thiếu file) -> ghi log và báo
    $err = $_
    $err | Out-String | Set-Content -LiteralPath $LogFile -Encoding UTF8
    try {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show('Không mở được trình cài đặt: ' + $err.Exception.Message + "`n`nChi tiết: " + $LogFile,
            'Anh 7 cho Windows', 'OK', 'Error') | Out-Null
    } catch { }
}
