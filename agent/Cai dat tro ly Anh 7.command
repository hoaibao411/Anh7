#!/bin/bash
# =========================================================
# Cài trợ lý Anh 7 vào máy ảo (bấm đúp file này BÊN TRONG máy ảo)
# Trợ lý tự chạy mỗi khi đăng nhập máy ảo.
# =========================================================
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/Library/Application Support/Anh7Agent"
PLIST="$HOME/Library/LaunchAgents/vn.anh7.agent.plist"

mkdir -p "$DEST" "$HOME/Library/LaunchAgents"
cp "$SRC/anh7-agent.js" "$DEST/anh7-agent.js"

cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>vn.anh7.agent</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/osascript</string>
        <string>-l</string>
        <string>JavaScript</string>
        <string>$DEST/anh7-agent.js</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardErrorPath</key><string>$DEST/agent.log</string>
</dict>
</plist>
EOF

# Khởi động lại trợ lý (nếu đã cài trước đó)
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo ""
echo "Đã cài trợ lý Anh 7. Nếu macOS hỏi quyền truy cập ổ đĩa/thư mục chia sẻ, bấm Cho phép."
echo "Quay lại Win12 > Ứng dụng > tab Máy ảo để xem danh sách app."
echo ""
read -n 1 -s -r -p "Bấm phím bất kỳ để đóng..."
