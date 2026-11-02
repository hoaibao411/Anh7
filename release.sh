#!/bin/bash
# =====================================================
# Đóng gói "Anh 7.app" thành file .zip để đưa lên GitHub Releases
# Cách dùng:  ./release.sh 1.0.0
# Kết quả:    dist/Anh7-1.0.0-macOS-AppleSilicon.zip
# =====================================================
set -e
cd "$(dirname "$0")"

APP="/Applications/Anh 7.app"
VER="${1:-1.0.0}"

if [ ! -d "$APP" ]; then
    echo "Chưa có $APP — chạy ./build.sh trước"
    exit 1
fi

# Không đóng gói khi app đang chạy (tránh lẫn trạng thái tạm)
if pgrep -x MyApp > /dev/null; then
    echo "Anh 7 đang chạy. Tắt app (và máy ảo) rồi chạy lại."
    exit 1
fi

# Ghi số phiên bản vào app
plutil -replace CFBundleShortVersionString -string "$VER" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VER" "$APP/Contents/Info.plist"

# Kèm file ghi công vào app
cp NOTICE.md "$APP/Contents/Resources/NOTICE-Anh7.md"
[ -f LICENSE ] && cp LICENSE "$APP/Contents/Resources/LICENSE-Anh7"

# Info.plist đã đổi -> phải ký lại (kèm quyền ảo hoá), nếu không app báo hỏng
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
codesign --verify --deep "$APP" && echo "Chữ ký hợp lệ"

# Kiểm tra kiến trúc (chỉ chạy trên chip Apple)
echo "Kiến trúc: $(lipo -archs "$APP/Contents/MacOS/MyApp")"

# Nén (ditto giữ đúng cấu trúc .app, quyền và chữ ký)
mkdir -p dist
ZIP="dist/Anh7-$VER-macOS-AppleSilicon.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo ""
echo "Xong: $ZIP ($(du -h "$ZIP" | cut -f1))"
echo "SHA-256: $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
echo "Tiếp theo: GitHub > repo Anh7 > Releases > Draft a new release > kéo file zip vào."
