#!/bin/bash
# Dừng ngay nếu có lệnh lỗi
set -e
REPO="$(cd "$(dirname "$0")" && pwd)"

cd "$REPO"
APP="/Applications/Anh 7.app"

# =====================================================
# CHỌN NGUỒN GIAO DIỆN (bỏ dấu # ở đúng 1 dòng)
# =====================================================
WEB_DIR="$HOME/win12"          # Giao diện Win12 (mã nguồn tjy-gitnub)
# WEB_DIR="$REPO/web"    # Giao diện cũ: Tổng quan / Việc cần làm / Ghi chú

if [ ! -d "$WEB_DIR" ]; then
    echo "Không tìm thấy thư mục giao diện: $WEB_DIR"
    exit 1
fi

# Tắt app nếu đang chạy (tên tiến trình vẫn là MyApp)
pkill -x MyApp 2>/dev/null || true

# Biên dịch vỏ Swift
swiftc main.swift VMManager.swift HostBridge.swift -o "$APP/Contents/MacOS/MyApp" \
    -framework Cocoa -framework WebKit -framework Virtualization -framework IOKit -framework CoreWLAN

# Làm sạch Resources để không lẫn file của giao diện trước
RES="$APP/Contents/Resources"
rm -rf "$RES"
mkdir -p "$RES"

# Chép giao diện vào app, bỏ thư mục .git và file rác
rsync -a --exclude ".git" --exclude ".github" --exclude ".DS_Store" "$WEB_DIR/" "$RES/"
echo "Đã chép giao diện từ $WEB_DIR"

# Bộ cài trợ lý chạy trong máy ảo (app tự đặt vào thư mục chia sẻ khi mở)
if [ -d agent ]; then
    rsync -a --exclude ".DS_Store" agent/ "$RES/agent/"
fi

# App Anh 7 có sẵn (Ghi chú, Máy tính, Việc cần làm...) + thư viện _sdk
if [ -d anh7apps ]; then
    rsync -a --exclude ".DS_Store" anh7apps/ "$RES/anh7apps/"
    echo "Đã chép app Anh 7 có sẵn"
fi

# Icon kiểu cũ (dự phòng cho macOS đời trước)
if [ -f icon.png ]; then
    rm -rf AppIcon.iconset
    mkdir AppIcon.iconset

    sips -z 16 16     icon.png --out AppIcon.iconset/icon_16x16.png      > /dev/null
    sips -z 32 32     icon.png --out AppIcon.iconset/icon_16x16@2x.png   > /dev/null
    sips -z 32 32     icon.png --out AppIcon.iconset/icon_32x32.png      > /dev/null
    sips -z 64 64     icon.png --out AppIcon.iconset/icon_32x32@2x.png   > /dev/null
    sips -z 128 128   icon.png --out AppIcon.iconset/icon_128x128.png    > /dev/null
    sips -z 256 256   icon.png --out AppIcon.iconset/icon_128x128@2x.png > /dev/null
    sips -z 256 256   icon.png --out AppIcon.iconset/icon_256x256.png    > /dev/null
    sips -z 512 512   icon.png --out AppIcon.iconset/icon_256x256@2x.png > /dev/null
    sips -z 512 512   icon.png --out AppIcon.iconset/icon_512x512.png    > /dev/null
    sips -z 1024 1024 icon.png --out AppIcon.iconset/icon_512x512@2x.png > /dev/null

    iconutil -c icns AppIcon.iconset -o "$RES/AppIcon.icns"
    rm -rf AppIcon.iconset
    plutil -replace CFBundleIconFile -string AppIcon "$APP/Contents/Info.plist"
    echo "Đã cập nhật icon"
fi

# Icon chuẩn macOS mới (tràn khung)
if [ -d AppIcon.icon ]; then
    xcrun actool AppIcon.icon \
        --compile "$RES" \
        --app-icon AppIcon \
        --enable-on-demand-resources NO \
        --development-region en \
        --target-device mac \
        --platform macosx \
        --enable-icon-stack-fallback-generation=disabled \
        --include-all-app-icons \
        --minimum-deployment-target 11.0 \
        --output-partial-info-plist /dev/null > /dev/null

    plutil -replace CFBundleIconName -string AppIcon "$APP/Contents/Info.plist"
    echo "Đã cập nhật icon chuẩn mới"
fi

# Lý do xin quyền điều khiển System Events (bật/tắt chế độ tối từ Cài đặt Win12)
plutil -replace NSBluetoothAlwaysUsageDescription -string "Anh 7 cần quyền này để bật/tắt Bluetooth từ Cài đặt Win12." "$APP/Contents/Info.plist"
plutil -replace NSAppleEventsUsageDescription -string "Anh 7 cần quyền này để bật/tắt chế độ tối của máy Mac từ Cài đặt Win12." "$APP/Contents/Info.plist"

# Ký app kèm quyền ảo hóa (bắt buộc để chạy máy ảo).
# Ký "ad-hoc" (dấu -): chỉ dùng trên máy này, không cần tài khoản nhà phát triển.
# Phải ký SAU CÙNG vì mọi thay đổi trong app sau khi ký sẽ làm chữ ký mất hiệu lực.
cat > /tmp/anh7.entitlements << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.virtualization</key>
    <true/>
</dict>
</plist>
PLIST
codesign --force --sign - --entitlements /tmp/anh7.entitlements "$APP"
echo "Đã ký quyền ảo hóa"

touch "$APP"

# Mở lại app
open "$APP"
echo "Build xong"
