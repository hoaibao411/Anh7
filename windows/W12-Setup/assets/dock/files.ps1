# =====================================================================
#  TỆP ANH 7 — trình quản lý file kiểu Finder (một phần của Anh 7 cho Windows)
#
#  Chạy riêng:  powershell -STA -WindowStyle Hidden -File files.ps1 [-Path "C:\..."]
#  Anh 7 Dock nạp file này (-Library) để mở cửa sổ ngay trong tiến trình Dock (mở tức thì).
#
#  Không sửa gì của Windows. Xóa = đưa vào Thùng rác (khôi phục được).
# =====================================================================
param([string]$Path, [switch]$Library)

$FilesHere = $PSScriptRoot
$FilesLog  = Join-Path $env:TEMP 'anh7-tep-loi.txt'

if (-not $Library) {
    $ErrorActionPreference = 'Stop'
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Drawing
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $FilesHere 'Native.cs')))
}
Add-Type -AssemblyName Microsoft.VisualBasic

# ---------- Ảnh dùng chung ----------
function Files-LoadPng([string]$p) {
    $bi = New-Object Windows.Media.Imaging.BitmapImage
    $bi.BeginInit(); $bi.UriSource = New-Object Uri($p); $bi.CacheOption = 'OnLoad'; $bi.EndInit(); $bi.Freeze()
    return $bi
}
$script:FilesFolderIcon = Files-LoadPng (Join-Path $FilesHere 'ic-folder.png')
$script:FilesAppIcon = Files-LoadPng (Join-Path $FilesHere 'ic-app.png')
$script:FilesExtIcons = @{}
$script:FilesWins = New-Object System.Collections.ArrayList

# Ảnh thu nhỏ của Windows (ảnh, video, PDF...) hoặc icon của file
function Files-Thumb([string]$p, [int]$size, [int]$flags) {
    $w = 0; $h = 0
    $px = [Anh7Dock.Thumbs]::Get($p, $size, $flags, [ref]$w, [ref]$h)
    if (-not $px) { return $null }
    $bs = [Windows.Media.Imaging.BitmapSource]::Create($w, $h, 96, 96, [Windows.Media.PixelFormats]::Pbgra32, $null, $px, $w * 4)
    $bs.Freeze()
    return $bs
}

# Icon tạm (nhanh) theo đuôi file, trước khi có ảnh thu nhỏ thật
function Files-QuickIcon($item) {
    if ($item.IsDir) { return $script:FilesFolderIcon }
    $ext = [IO.Path]::GetExtension($item.Path).ToLowerInvariant()
    if ($ext -eq '.exe' -or $ext -eq '.lnk') { return $script:FilesAppIcon }
    if ($script:FilesExtIcons.ContainsKey($ext)) { return $script:FilesExtIcons[$ext] }
    $img = Files-Thumb $item.Path 48 4
    if (-not $img) { $img = $script:FilesAppIcon }
    $script:FilesExtIcons[$ext] = $img
    return $img
}

function Files-SizeText([long]$n) {
    if ($n -lt 1024) { return "$n B" }
    if ($n -lt 1MB) { return ('{0:N0} KB' -f ($n / 1KB)).Replace(',', '.') }
    if ($n -lt 1GB) { return ('{0:N1} MB' -f ($n / 1MB)).Replace('.', ',') }
    return ('{0:N2} GB' -f ($n / 1GB)).Replace('.', ',')
}

$script:FilesKinds = @{
    '.jpg' = 'Ảnh JPEG'; '.jpeg' = 'Ảnh JPEG'; '.png' = 'Ảnh PNG'; '.gif' = 'Ảnh GIF'; '.webp' = 'Ảnh WebP'; '.heic' = 'Ảnh HEIC'
    '.mp4' = 'Video MP4'; '.mov' = 'Video MOV'; '.mkv' = 'Video MKV'; '.mp3' = 'Âm thanh MP3'; '.wav' = 'Âm thanh WAV'
    '.pdf' = 'Tài liệu PDF'; '.docx' = 'Tài liệu Word'; '.doc' = 'Tài liệu Word'; '.xlsx' = 'Bảng tính Excel'; '.xls' = 'Bảng tính Excel'
    '.pptx' = 'Bản trình chiếu'; '.txt' = 'Văn bản'; '.md' = 'Markdown'; '.zip' = 'Tệp nén ZIP'; '.rar' = 'Tệp nén RAR'; '.7z' = 'Tệp nén 7z'
    '.exe' = 'Ứng dụng'; '.lnk' = 'Lối tắt'; '.ps1' = 'Script PowerShell'; '.cmd' = 'Script lệnh'; '.html' = 'Trang web'
}

# ---------- Vị trí trên thanh bên ----------
function Files-KnownFolder([string]$guid, [string]$fallback) {
    try {
        $v = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction Stop).$guid
        if ($v) { return [Environment]::ExpandEnvironmentVariables($v) }
    } catch { }
    return $fallback
}
function Files-Places {
    $list = @(
        @{ Name = 'Thư mục nhà'; Path = $env:USERPROFILE; Glyph = 0xE80F }
        @{ Name = 'Màn hình nền'; Path = [Environment]::GetFolderPath('Desktop'); Glyph = 0xE7F4 }
        @{ Name = 'Tải về'; Path = (Files-KnownFolder '{374DE290-123F-4565-9164-39C4925E467B}' (Join-Path $env:USERPROFILE 'Downloads')); Glyph = 0xE896 }
        @{ Name = 'Tài liệu'; Path = [Environment]::GetFolderPath('MyDocuments'); Glyph = 0xE8A5 }
        @{ Name = 'Ảnh'; Path = [Environment]::GetFolderPath('MyPictures'); Glyph = 0xEB9F }
        @{ Name = 'Nhạc'; Path = [Environment]::GetFolderPath('MyMusic'); Glyph = 0xEC4F }
        @{ Name = 'Video'; Path = [Environment]::GetFolderPath('MyVideos'); Glyph = 0xE714 }
    )
    return @($list | Where-Object { $_.Path -and (Test-Path -LiteralPath $_.Path) })
}

function Files-SideButton($st, [string]$text, [int]$glyph, $target) {
    $b = New-Object Windows.Controls.Button
    $b.Style = $st.Win.Resources['Flat']
    $b.HorizontalContentAlignment = 'Left'
    $b.Padding = New-Object Windows.Thickness(10, 5, 8, 5)
    $sp = New-Object Windows.Controls.StackPanel
    $sp.Orientation = 'Horizontal'
    $g = New-Object Windows.Controls.TextBlock
    $g.Text = [string][char]$glyph
    $g.FontFamily = New-Object Windows.Media.FontFamily('Segoe Fluent Icons, Segoe MDL2 Assets')
    $g.FontSize = 15; $g.Width = 24; $g.VerticalAlignment = 'Center'
    $g.Foreground = (New-Object Windows.Media.BrushConverter).ConvertFromString('#3B6FF0')
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $text; $t.VerticalAlignment = 'Center'; $t.TextTrimming = 'CharacterEllipsis'
    [void]$sp.Children.Add($g); [void]$sp.Children.Add($t)
    $b.Content = $sp
    $b.Tag = @{ St = $st; Target = $target }
    $b.Add_Click({ param($s, $e)
        $tg = $s.Tag
        if ($tg.Target -is [scriptblock]) { & $tg.Target } else { Files-Go $tg.St ([string]$tg.Target) $true }
    })
    return $b
}

# ---------- Mở cửa sổ mới ----------
function Files-Open([string]$start) {
    $w = [Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $FilesHere 'files.xaml'), [Text.Encoding]::UTF8))
    $st = @{ Win = $w; Hist = New-Object System.Collections.ArrayList; Idx = -1; Path = ''; All = @(); Mode = 'grid'
             Queue = New-Object System.Collections.Queue; Zoomed = $false; Normal = $null; Ui = @{} }
    $w.Tag = $st
    foreach ($n in @('Shell', 'Side', 'Lights', 'BtnClose', 'BtnMin', 'BtnZoom', 'SideFav', 'SideLoc', 'Toolbar', 'BtnBack', 'BtnFwd',
                     'TxtSearch', 'SearchHint', 'BtnNewFolder', 'BtnGrid', 'BtnList', 'TxtTitle', 'ListHeader', 'FileList', 'TxtEmpty',
                     'TxtCount', 'PathBar')) {
        $st.Ui[$n] = $w.FindName($n)
        if ($st.Ui[$n] -is [Windows.FrameworkElement]) { $st.Ui[$n].Tag = $(if ($st.Ui[$n].Tag) { $st.Ui[$n].Tag } else { $st }) }
    }
    $ui = $st.Ui
    foreach ($n in @('BtnClose', 'BtnMin', 'BtnZoom', 'BtnBack', 'BtnFwd', 'TxtSearch', 'BtnNewFolder', 'BtnGrid', 'BtnList', 'FileList', 'Toolbar', 'Lights')) {
        $ui[$n].Tag = $st
    }
    try { $w.Icon = Files-LoadPng (Join-Path $FilesHere 'ic-folder.png') } catch { }

    # Thanh bên
    foreach ($p in (Files-Places)) { [void]$ui.SideFav.Children.Add((Files-SideButton $st $p.Name $p.Glyph $p.Path)) }
    foreach ($d in [IO.DriveInfo]::GetDrives()) {
        if (-not $d.IsReady) { continue }
        $label = if ($d.VolumeLabel) { $d.VolumeLabel + ' (' + $d.Name.TrimEnd('\') + ')' } else { 'Ổ ' + $d.Name.TrimEnd('\') }
        [void]$ui.SideLoc.Children.Add((Files-SideButton $st $label 0xEDA2 $d.RootDirectory.FullName))
    }
    [void]$ui.SideLoc.Children.Add((Files-SideButton $st 'Thùng rác' 0xE74D { Start-Process explorer.exe 'shell:RecycleBinFolder' }))

    # Nút tròn
    $ui.BtnClose.Add_Click({ param($s, $e) $s.Tag.Win.Close() })
    $ui.BtnMin.Add_Click({ param($s, $e) $s.Tag.Win.WindowState = 'Minimized' })
    $ui.BtnZoom.Add_Click({ param($s, $e) Files-Zoom $s.Tag })

    # Kéo cửa sổ bằng thanh công cụ / vùng nút tròn; bấm đúp thanh công cụ = phóng to
    $drag = {
        param($s, $e)
        if ($e.OriginalSource -is [Windows.Controls.TextBox]) { return }
        if ($e.ClickCount -eq 2) { Files-Zoom $s.Tag; return }
        try { $s.Tag.Win.DragMove() } catch { }
    }
    $ui.Toolbar.Add_MouseLeftButtonDown($drag)
    $ui.Lights.Add_MouseLeftButtonDown($drag)

    # Điều hướng
    $ui.BtnBack.Add_Click({ param($s, $e) Files-History $s.Tag -1 })
    $ui.BtnFwd.Add_Click({ param($s, $e) Files-History $s.Tag 1 })
    $ui.BtnGrid.Add_Click({ param($s, $e) Files-SetMode $s.Tag 'grid' })
    $ui.BtnList.Add_Click({ param($s, $e) Files-SetMode $s.Tag 'list' })
    $ui.BtnNewFolder.Add_Click({ param($s, $e) Files-NewFolder $s.Tag })
    $ui.TxtSearch.Add_TextChanged({ param($s, $e)
        $s.Tag.Ui.SearchHint.Visibility = $(if ($s.Text) { 'Collapsed' } else { 'Visible' })
        Files-Render $s.Tag
    })
    $ui.FileList.Add_MouseDoubleClick({ param($s, $e)
        $it = $s.SelectedItem
        if ($it -and ($e.OriginalSource -is [Windows.FrameworkElement]) -and $e.OriginalSource.DataContext -eq $it) { Files-OpenItem $s.Tag $it }
    })

    # Menu chuột phải
    $m = New-Object Windows.Controls.ContextMenu
    foreach ($def in @(
        @('Mở', { param($s, $e) $st2 = $s.Tag; foreach ($it in @($st2.Ui.FileList.SelectedItems)) { Files-OpenItem $st2 $it } }),
        @('Hiện trong File Explorer', { param($s, $e) $it = $s.Tag.Ui.FileList.SelectedItem; if ($it) { Start-Process explorer.exe ('/select,"' + $it.Path + '"') } }),
        @('Đổi tên (F2)', { param($s, $e) Files-Rename $s.Tag }),
        @('Sao chép đường dẫn', { param($s, $e) $it = $s.Tag.Ui.FileList.SelectedItem; if ($it) { [Windows.Clipboard]::SetText($it.Path) } }),
        @('Đưa vào Thùng rác (Delete)', { param($s, $e) Files-Trash $s.Tag })
    )) {
        $mi = New-Object Windows.Controls.MenuItem
        $mi.Header = $def[0]; $mi.Tag = $st
        $mi.Add_Click($def[1])
        [void]$m.Items.Add($mi)
    }
    $ui.FileList.ContextMenu = $m

    # Phím tắt
    $w.Add_KeyDown({ param($s, $e)
        $st2 = $s.Tag
        $alt = ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Alt) -ne 0
        $ctrl = ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control) -ne 0
        $inSearch = $st2.Ui.TxtSearch.IsKeyboardFocusWithin
        $key = $e.Key
        if ($key -eq 'System') { $key = $e.SystemKey }
        if ($alt -and $key -eq 'Left') { Files-History $st2 -1; $e.Handled = $true; return }
        if ($alt -and $key -eq 'Right') { Files-History $st2 1; $e.Handled = $true; return }
        if ($ctrl -and $key -eq 'F') { $st2.Ui.TxtSearch.Focus() | Out-Null; $e.Handled = $true; return }
        if ($key -eq 'F5') { Files-Go $st2 $st2.Path $false; $e.Handled = $true; return }
        if ($inSearch) { if ($key -eq 'Escape') { $st2.Ui.TxtSearch.Text = '' }; return }
        switch ($key) {
            'Return' { foreach ($it in @($st2.Ui.FileList.SelectedItems)) { Files-OpenItem $st2 $it }; $e.Handled = $true }
            'Back'   { Files-Up $st2; $e.Handled = $true }
            'Delete' { Files-Trash $st2; $e.Handled = $true }
            'F2'     { Files-Rename $st2; $e.Handled = $true }
        }
    })

    # Nạp ảnh thu nhỏ dần dần để cửa sổ không bị đứng
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(25)
    $timer.Tag = $st
    $timer.Add_Tick({ param($s, $e)
        $st2 = $s.Tag
        $size = $(if ($st2.Mode -eq 'grid') { 96 } else { 32 })
        for ($i = 0; $i -lt 6 -and $st2.Queue.Count -gt 0; $i++) {
            $it = $st2.Queue.Dequeue()
            if ($it.IsDir) { continue }
            $img = Files-Thumb $it.Path $size 0
            if ($img) { $it.Icon = $img }
        }
    })
    $st.Timer = $timer
    $timer.Start()

    $w.Add_Closed({ param($s, $e)
        $s.Tag.Timer.Stop()
        [void]$script:FilesWins.Remove($s)
    })
    [void]$script:FilesWins.Add($w)

    if (-not $start -or -not (Test-Path -LiteralPath $start)) { $start = $env:USERPROFILE }
    Files-SetMode $st 'grid'
    Files-Go $st $start $true
    return $w
}

# ---------- Thao tác ----------
function Files-Zoom($st) {
    $w = $st.Win
    if ($st.Zoomed) {
        $n = $st.Normal
        $w.Left = $n.X; $w.Top = $n.Y; $w.Width = $n.Width; $w.Height = $n.Height
        $st.Ui.Shell.Margin = New-Object Windows.Thickness(14)
        $st.Zoomed = $false
    } else {
        $st.Normal = New-Object Windows.Rect($w.Left, $w.Top, $w.Width, $w.Height)
        $wa = [Windows.SystemParameters]::WorkArea   # vùng làm việc: chừa chỗ cho Anh 7 Dock
        $w.Left = $wa.Left; $w.Top = $wa.Top; $w.Width = $wa.Width; $w.Height = $wa.Height
        $st.Ui.Shell.Margin = New-Object Windows.Thickness(4)
        $st.Zoomed = $true
    }
}

function Files-Go($st, [string]$path, [bool]$addHist) {
    try {
        $dir = New-Object IO.DirectoryInfo($path)
        $entries = $dir.GetFileSystemInfos()
    } catch {
        [Windows.MessageBox]::Show($st.Win, 'Không mở được thư mục này: ' + $_.Exception.Message, 'Tệp Anh 7') | Out-Null
        return
    }
    $items = New-Object System.Collections.Generic.List[Anh7Dock.FileItem]
    foreach ($fi in $entries) {
        $attr = $fi.Attributes
        if (($attr -band [IO.FileAttributes]::Hidden) -or ($attr -band [IO.FileAttributes]::System)) { continue }
        $it = New-Object Anh7Dock.FileItem
        $it.Name = $fi.Name; $it.Path = $fi.FullName; $it.Modified = $fi.LastWriteTime
        $it.DateText = $fi.LastWriteTime.ToString('dd/MM/yyyy HH:mm')
        if ($fi -is [IO.DirectoryInfo]) {
            $it.IsDir = $true; $it.Kind = 'Thư mục'; $it.SizeText = '—'
        } else {
            $it.Size = $fi.Length; $it.SizeText = Files-SizeText $fi.Length
            $ext = $fi.Extension.ToLowerInvariant()
            $it.Kind = $(if ($script:FilesKinds.ContainsKey($ext)) { $script:FilesKinds[$ext] } elseif ($ext) { 'Tệp ' + $ext.TrimStart('.').ToUpperInvariant() } else { 'Tệp' })
        }
        $items.Add($it)
    }
    # Thư mục trước, rồi theo tên (kiểu tiếng Việt)
    $st.All = @($items | Sort-Object -Property @{ Expression = { -not $_.IsDir } }, @{ Expression = { $_.Name } })
    foreach ($it in $st.All) { $it.Icon = Files-QuickIcon $it }

    $st.Path = $dir.FullName
    if ($addHist) {
        while ($st.Hist.Count -gt $st.Idx + 1) { $st.Hist.RemoveAt($st.Hist.Count - 1) }
        [void]$st.Hist.Add($st.Path)
        $st.Idx = $st.Hist.Count - 1
    }
    $st.Ui.TxtSearch.Text = ''
    $title = if ($dir.Parent) { $dir.Name } else { $dir.FullName.TrimEnd('\') }
    $st.Ui.TxtTitle.Text = $title
    $st.Win.Title = $title + ' — Tệp Anh 7'
    $st.Ui.BtnBack.IsEnabled = $st.Idx -gt 0
    $st.Ui.BtnFwd.IsEnabled = $st.Idx -lt $st.Hist.Count - 1
    Files-PathBar $st
    Files-Render $st
}

function Files-Render($st) {
    $q = $st.Ui.TxtSearch.Text
    $shown = if ($q) { @($st.All | Where-Object { $_.Name.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0 }) } else { @($st.All) }
    $st.Ui.FileList.ItemsSource = $shown
    $st.Ui.TxtEmpty.Visibility = $(if ($shown.Count -eq 0) { 'Visible' } else { 'Collapsed' })
    $st.Ui.TxtEmpty.Text = $(if ($q) { 'Không có mục khớp "' + $q + '"' } else { 'Thư mục trống' })
    $dirs = @($shown | Where-Object { $_.IsDir }).Count
    $st.Ui.TxtCount.Text = ('{0} mục · {1} thư mục' -f $shown.Count, $dirs)
    $st.Queue.Clear()
    foreach ($it in $shown) { if (-not $it.IsDir) { $st.Queue.Enqueue($it) } }
}

function Files-PathBar($st) {
    $bar = $st.Ui.PathBar
    $bar.Children.Clear()
    $parts = New-Object System.Collections.ArrayList
    $d = New-Object IO.DirectoryInfo($st.Path)
    while ($d) { [void]$parts.Insert(0, $d); $d = $d.Parent }
    $i = 0
    foreach ($p in $parts) {
        if ($i -gt 0) {
            $sep = New-Object Windows.Controls.TextBlock
            $sep.Text = '›'; $sep.Foreground = (New-Object Windows.Media.BrushConverter).ConvertFromString('#A0A0A8')
            $sep.Margin = New-Object Windows.Thickness(2, 0, 2, 0); $sep.VerticalAlignment = 'Center'
            [void]$bar.Children.Add($sep)
        }
        $b = New-Object Windows.Controls.Button
        $b.Style = $st.Win.Resources['Flat']
        $b.Padding = New-Object Windows.Thickness(5, 1, 5, 1)
        $b.FontSize = 11.5
        $b.Content = $(if ($p.Parent) { $p.Name } else { $p.FullName.TrimEnd('\') })
        $b.Tag = @{ St = $st; Target = $p.FullName }
        $b.Add_Click({ param($s, $e) Files-Go $s.Tag.St ([string]$s.Tag.Target) $true })
        [void]$bar.Children.Add($b)
        $i++
    }
}

function Files-SetMode($st, [string]$mode) {
    $st.Mode = $mode
    $lst = $st.Ui.FileList
    $res = $st.Win.Resources
    if ($mode -eq 'grid') {
        $lst.ItemTemplate = $res['GridTpl']; $lst.ItemsPanel = $res['WrapTpl']; $st.Ui.ListHeader.Visibility = 'Collapsed'
    } else {
        $lst.ItemTemplate = $res['ListTpl']; $lst.ItemsPanel = $res['StackTpl']; $st.Ui.ListHeader.Visibility = 'Visible'
    }
    $on = (New-Object Windows.Media.BrushConverter).ConvertFromString('#FFFFFF')
    $st.Ui.BtnGrid.Background = $(if ($mode -eq 'grid') { $on } else { [Windows.Media.Brushes]::Transparent })
    $st.Ui.BtnList.Background = $(if ($mode -eq 'list') { $on } else { [Windows.Media.Brushes]::Transparent })
    if ($st.Path) { Files-Render $st }   # nạp lại ảnh đúng cỡ
}

function Files-History($st, [int]$step) {
    $n = $st.Idx + $step
    if ($n -lt 0 -or $n -ge $st.Hist.Count) { return }
    $st.Idx = $n
    Files-Go $st ([string]$st.Hist[$n]) $false
}

function Files-Up($st) {
    $d = New-Object IO.DirectoryInfo($st.Path)
    if ($d.Parent) { Files-Go $st $d.Parent.FullName $true }
}

function Files-OpenItem($st, $it) {
    if ($it.IsDir) { Files-Go $st $it.Path $true; return }
    try { Start-Process -FilePath $it.Path } catch {
        [Windows.MessageBox]::Show($st.Win, 'Không mở được: ' + $_.Exception.Message, 'Tệp Anh 7') | Out-Null
    }
}

function Files-NewFolder($st) {
    $base = Join-Path $st.Path 'Thư mục mới'
    $p = $base; $n = 2
    while (Test-Path -LiteralPath $p) { $p = $base + ' (' + $n + ')'; $n++ }
    try { New-Item -ItemType Directory -Path $p | Out-Null } catch {
        [Windows.MessageBox]::Show($st.Win, 'Không tạo được thư mục: ' + $_.Exception.Message, 'Tệp Anh 7') | Out-Null; return
    }
    Files-Go $st $st.Path $false
    $new = $st.All | Where-Object { $_.Path -eq $p } | Select-Object -First 1
    if ($new) { $st.Ui.FileList.SelectedItem = $new; $st.Ui.FileList.ScrollIntoView($new); Files-Rename $st }
}

function Files-Rename($st) {
    $it = $st.Ui.FileList.SelectedItem
    if (-not $it) { return }
    $name = [Microsoft.VisualBasic.Interaction]::InputBox('Tên mới:', 'Đổi tên', $it.Name)
    if (-not $name -or $name -eq $it.Name) { return }
    if ($name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
        [Windows.MessageBox]::Show($st.Win, 'Tên không được chứa các ký tự \ / : * ? " < > |', 'Tệp Anh 7') | Out-Null; return
    }
    try { Rename-Item -LiteralPath $it.Path -NewName $name } catch {
        [Windows.MessageBox]::Show($st.Win, 'Không đổi tên được: ' + $_.Exception.Message, 'Tệp Anh 7') | Out-Null; return
    }
    Files-Go $st $st.Path $false
}

function Files-Trash($st) {
    $sel = @($st.Ui.FileList.SelectedItems)
    if ($sel.Count -eq 0) { return }
    $msg = if ($sel.Count -eq 1) { 'Đưa "' + $sel[0].Name + '" vào Thùng rác?' } else { 'Đưa ' + $sel.Count + ' mục vào Thùng rác?' }
    if ([Windows.MessageBox]::Show($st.Win, $msg, 'Tệp Anh 7', 'YesNo', 'Question') -ne 'Yes') { return }
    foreach ($it in $sel) {
        try {
            if ($it.IsDir) {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($it.Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
            } else {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($it.Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
            }
        } catch { }
    }
    Files-Go $st $st.Path $false
}

# ---------- Chạy riêng ----------
if (-not $Library) {
    try {
        $w = Files-Open $Path
        [void]$w.ShowDialog()
    } catch {
        $_ | Out-String | Set-Content -LiteralPath $FilesLog -Encoding UTF8
        try { [Windows.MessageBox]::Show('Tệp Anh 7 gặp lỗi: ' + $_.Exception.Message + "`n`nChi tiết: " + $FilesLog) | Out-Null } catch { }
    }
}
