# =====================================================================
#  ANH 7 START — menu Start kiểu Win12 (một phần của Anh 7 cho Windows)
#  Được Anh 7 Dock nạp (dot-source). Dùng chung Files-Thumb của files.ps1.
#
#  - Đã ghim: lưu trong dock.json -> startPinned (mã AppID của Windows)
#  - Tất cả ứng dụng: lấy từ Windows (Get-StartApps), gồm cả app Microsoft Store
#  - Nút nguồn: Khóa, Ngủ, Đăng xuất, Khởi động lại, Tắt máy
# =====================================================================

$StartHere = $PSScriptRoot
$script:StartWin = $null
$script:StartApps = @()
$script:StartLoaded = [datetime]::MinValue
$script:StartIconQueue = New-Object System.Collections.Queue
$script:StartAllMode = $false

# Tên app mặc định được ghim lần đầu (tên tiếng Anh và tiếng Việt)
$StartDefaultNames = @('Microsoft Edge', 'Google Chrome', 'Settings', 'Cài đặt', 'Microsoft Store', 'Notepad', 'Calculator',
                       'Máy tính', 'Paint', 'Photos', 'Ảnh', 'Clock', 'Đồng hồ', 'Snipping Tool', 'Terminal', 'Outlook')

function Start-NewItem([string]$name, [string]$id) {
    $it = New-Object Anh7Dock.FileItem
    $it.Name = $name; $it.Path = $id; $it.Icon = $script:FilesAppIcon
    return $it
}

function Start-IconFor([string]$id) {
    if ($id -eq 'anh7:files') { return $script:FilesFolderIcon }
    $p = if ($id -match '^[a-zA-Z]:\\' -and (Test-Path -LiteralPath $id)) { $id } else { 'shell:AppsFolder\' + $id }
    $img = Files-Thumb $p 64 4
    if ($img) { return $img }
    return $script:FilesAppIcon
}

# Danh sách app của Windows (làm mới tối đa 2 phút/lần)
function Start-LoadApps([bool]$force) {
    if (-not $force -and $script:StartApps.Count -gt 0 -and ((Get-Date) - $script:StartLoaded).TotalSeconds -lt 120) { return }
    $old = @{}
    foreach ($a in $script:StartApps) { $old[$a.Path] = $a }
    $list = New-Object System.Collections.Generic.List[Anh7Dock.FileItem]
    $list.Add((Start-NewItem 'Tệp Anh 7' 'anh7:files'))
    $seen = @{}
    try {
        foreach ($a in (Get-StartApps | Sort-Object Name)) {
            if (-not $a.Name -or -not $a.AppID -or $seen.ContainsKey($a.AppID)) { continue }
            $seen[$a.AppID] = $true
            if ($old.ContainsKey($a.AppID)) { $list.Add($old[$a.AppID]); continue }   # giữ icon đã nạp
            $it = Start-NewItem $a.Name $a.AppID
            $list.Add($it)
            $script:StartIconQueue.Enqueue($it)
        }
    } catch { }
    $list[0].Icon = $script:FilesFolderIcon
    $script:StartApps = @($list)
    $script:StartLoaded = Get-Date
}

function Start-FindApp([string]$id) { return $script:StartApps | Where-Object { $_.Path -eq $id } | Select-Object -First 1 }

function Start-PinnedIds {
    $ids = @($script:conf.startPinned)
    if ($ids.Count -eq 0 -or -not $ids[0]) {
        $ids = @('anh7:files')
        foreach ($n in $StartDefaultNames) {
            $a = $script:StartApps | Where-Object { $_.Name -eq $n } | Select-Object -First 1
            if ($a -and $ids -notcontains $a.Path) { $ids += $a.Path }
        }
        $script:conf | Add-Member -NotePropertyName startPinned -NotePropertyValue $ids -Force
        Save-Conf $script:conf
    }
    return $ids
}

function Start-Launch($it) {
    if (-not $it) { return }
    Start-Hide
    $id = [string]$it.Path
    try {
        if ($id -eq 'anh7:files') { Open-FilesWindow }
        elseif ($id -match '^[a-zA-Z]:\\' -and (Test-Path -LiteralPath $id)) { Start-Process -FilePath $id }
        else { Start-Process explorer.exe ('shell:AppsFolder\' + $id) }
    } catch {
        [System.Windows.MessageBox]::Show('Không mở được: ' + $it.Name) | Out-Null
    }
}

function Start-RenderPinned {
    $ui = $script:StartUi
    $items = New-Object System.Collections.ArrayList
    foreach ($id in (Start-PinnedIds)) {
        $a = Start-FindApp $id
        if ($a) { [void]$items.Add($a) }
    }
    $ui.PinList.ItemsSource = $items
}

# Đổi giữa: Đã ghim (lưới) | Tất cả ứng dụng (danh sách) | Kết quả tìm
function Start-Refresh {
    $ui = $script:StartUi
    $q = $ui.TxtQ.Text.Trim()
    $ui.QHint.Visibility = $(if ($ui.TxtQ.Text) { 'Collapsed' } else { 'Visible' })
    $ui.TxtNone.Visibility = 'Collapsed'
    if ($q) {
        $res = @($script:StartApps | Where-Object { $_.Name.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
        $ui.TxtSection.Text = 'Kết quả cho "' + $q + '"'
        $ui.PinList.Visibility = 'Collapsed'; $ui.AllList.Visibility = 'Visible'
        $ui.AllList.ItemsSource = $res
        if ($res.Count -gt 0) { $ui.AllList.SelectedIndex = 0 } else { $ui.TxtNone.Visibility = 'Visible' }
        $ui.BtnAll.Visibility = 'Collapsed'
        return
    }
    $ui.BtnAll.Visibility = 'Visible'
    if ($script:StartAllMode) {
        $ui.TxtSection.Text = 'Tất cả ứng dụng'; $ui.TxtAllBtn.Text = '‹  Đã ghim'
        $ui.PinList.Visibility = 'Collapsed'; $ui.AllList.Visibility = 'Visible'
        $ui.AllList.ItemsSource = $script:StartApps
    } else {
        $ui.TxtSection.Text = 'Đã ghim'; $ui.TxtAllBtn.Text = 'Tất cả ứng dụng  ›'
        $ui.AllList.Visibility = 'Collapsed'; $ui.PinList.Visibility = 'Visible'
        Start-RenderPinned
    }
}

function Start-PinToggle($it, [bool]$pin) {
    $ids = @(Start-PinnedIds)
    if ($pin) { if ($ids -notcontains $it.Path) { $ids += $it.Path } }
    else { $ids = @($ids | Where-Object { $_ -ne $it.Path }) }
    $script:conf | Add-Member -NotePropertyName startPinned -NotePropertyValue $ids -Force
    Save-Conf $script:conf
    Start-Refresh
}

function Start-PinToDock($it) {
    $id = [string]$it.Path
    if ($id -eq 'anh7:files') { return }
    $path = if ($id -match '^[a-zA-Z]:\\') { $id } else { 'shell:AppsFolder\' + $id }
    if (@($script:conf.pinned | Where-Object { $_.path -eq $path }).Count -gt 0) { return }
    $script:conf.pinned = @($script:conf.pinned) + [pscustomobject]@{ name = $it.Name; path = $path }
    Save-Conf $script:conf
    Build-Apps $true
}

function Start-Menu([string[]]$labels, [scriptblock[]]$actions) {
    $m = New-Object Windows.Controls.ContextMenu
    for ($i = 0; $i -lt $labels.Count; $i++) {
        $mi = New-Object Windows.Controls.MenuItem
        $mi.Header = $labels[$i]
        $mi.Add_Click($actions[$i])
        [void]$m.Items.Add($mi)
    }
    return $m
}

function Start-Build {
    $w = [Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $StartHere 'start.xaml'), [Text.Encoding]::UTF8))
    $ui = @{}
    foreach ($n in @('TxtQ', 'QHint', 'BtnAll', 'TxtAllBtn', 'TxtSection', 'PinList', 'AllList', 'TxtNone', 'BtnPower', 'BtnSettings',
                     'BtnFiles', 'TxtInitial', 'TxtUser')) { $ui[$n] = $w.FindName($n) }
    $script:StartUi = $ui
    $script:StartWin = $w

    # Người dùng
    $name = $env:USERNAME
    try { $full = ([System.DirectoryServices.AccountManagement.UserPrincipal]::Current).DisplayName; if ($full) { $name = $full } } catch { }
    $ui.TxtUser.Text = $name
    $ui.TxtInitial.Text = $name.Substring(0, 1).ToUpperInvariant()

    $ui.TxtQ.Add_TextChanged({ Start-Refresh })
    $ui.TxtQ.Add_PreviewKeyDown({ param($s, $e)
        $l = $script:StartUi.AllList
        if ($e.Key -eq 'Return') {
            $it = if ($l.Visibility -eq 'Visible') { $l.SelectedItem } else { $null }
            if ($it) { Start-Launch $it }
            $e.Handled = $true
        } elseif ($e.Key -eq 'Down' -and $l.Visibility -eq 'Visible' -and $l.Items.Count -gt 0) {
            $l.SelectedIndex = [math]::Min($l.SelectedIndex + 1, $l.Items.Count - 1); $l.ScrollIntoView($l.SelectedItem); $e.Handled = $true
        } elseif ($e.Key -eq 'Up' -and $l.Visibility -eq 'Visible' -and $l.SelectedIndex -gt 0) {
            $l.SelectedIndex = $l.SelectedIndex - 1; $l.ScrollIntoView($l.SelectedItem); $e.Handled = $true
        }
    })
    $w.Add_PreviewKeyDown({ param($s, $e) if ($e.Key -eq 'Escape') { Start-Hide; $e.Handled = $true } })
    $w.Add_Deactivated({ Start-Hide })

    $ui.BtnAll.Add_Click({ $script:StartAllMode = -not $script:StartAllMode; Start-Refresh })
    foreach ($l in @($ui.PinList, $ui.AllList)) {
        $l.Add_MouseLeftButtonUp({ param($s, $e)
            if ($e.OriginalSource -is [Windows.FrameworkElement] -and $e.OriginalSource.DataContext -is [Anh7Dock.FileItem]) {
                Start-Launch $e.OriginalSource.DataContext
            }
        })
    }
    $ui.PinList.ContextMenu = Start-Menu @('Bỏ ghim khỏi Start', 'Ghim vào Dock') @(
        { $it = $script:StartUi.PinList.SelectedItem; if ($it) { Start-PinToggle $it $false } },
        { $it = $script:StartUi.PinList.SelectedItem; if ($it) { Start-PinToDock $it } })
    $ui.AllList.ContextMenu = Start-Menu @('Ghim vào Start', 'Ghim vào Dock') @(
        { $it = $script:StartUi.AllList.SelectedItem; if ($it) { Start-PinToggle $it $true } },
        { $it = $script:StartUi.AllList.SelectedItem; if ($it) { Start-PinToDock $it } })

    $ui.BtnFiles.Add_Click({ Start-Hide; Open-FilesWindow })
    $ui.BtnSettings.Add_Click({ Start-Hide; Start-Process 'ms-settings:' })

    $confirm = { param([string]$what) return [System.Windows.MessageBox]::Show($what + '?', 'Anh 7', 'YesNo', 'Question') -eq 'Yes' }
    $ui.BtnPower.ContextMenu = Start-Menu @('Khóa máy', 'Ngủ', 'Đăng xuất', 'Khởi động lại', 'Tắt máy') @(
        { Start-Hide; Start-Process rundll32.exe 'user32.dll,LockWorkStation' },
        { Start-Hide; Start-Process rundll32.exe 'powrprof.dll,SetSuspendState 0,1,0' },
        { Start-Hide; if ([System.Windows.MessageBox]::Show('Đăng xuất?', 'Anh 7', 'YesNo', 'Question') -eq 'Yes') { Start-Process shutdown.exe '/l' } },
        { Start-Hide; if ([System.Windows.MessageBox]::Show('Khởi động lại máy?', 'Anh 7', 'YesNo', 'Question') -eq 'Yes') { Start-Process shutdown.exe '/r /t 0' } },
        { Start-Hide; if ([System.Windows.MessageBox]::Show('Tắt máy?', 'Anh 7', 'YesNo', 'Question') -eq 'Yes') { Start-Process shutdown.exe '/s /t 0' } })
    $ui.BtnPower.Add_Click({ $m = $script:StartUi.BtnPower.ContextMenu; $m.PlacementTarget = $script:StartUi.BtnPower; $m.Placement = 'Top'; $m.IsOpen = $true })

    # Nạp icon app dần dần
    $t = New-Object Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromMilliseconds(30)
    $t.Add_Tick({
        for ($i = 0; $i -lt 6 -and $script:StartIconQueue.Count -gt 0; $i++) {
            $it = $script:StartIconQueue.Dequeue()
            $it.Icon = Start-IconFor $it.Path
        }
    })
    $t.Start()
}

function Start-Hide {
    if ($script:StartWin -and $script:StartWin.IsVisible) { $script:StartWin.Hide() }
}

function Toggle-Start {
    try {
        if (-not $script:StartWin) { Start-Build }
        $w = $script:StartWin
        if ($w.IsVisible) { Start-Hide; return }
        Start-LoadApps $false
        $script:StartAllMode = $false
        $script:StartUi.TxtQ.Text = ''
        Start-Refresh
        # Đặt ngay trên Dock, giữa màn hình
        $wa = [Windows.SystemParameters]::WorkArea
        $w.Left = $wa.Left + ($wa.Width - $w.Width) / 2
        $w.Top = $wa.Bottom - $w.Height + 6
        $w.Show()
        $w.Activate() | Out-Null
        [Anh7Dock.Native]::BringToFront((New-Object System.Windows.Interop.WindowInteropHelper($w)).Handle)
        $script:StartUi.TxtQ.Focus() | Out-Null
    } catch {
        $_ | Out-String | Set-Content -LiteralPath (Join-Path $env:TEMP 'anh7-start-loi.txt') -Encoding UTF8
        [Anh7Dock.Native]::Keys([byte[]]@(0x5B))   # lỗi -> mở Start của Windows để không bị kẹt
    }
}
