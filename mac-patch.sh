#!/bin/bash
# =====================================================
# Gắn "Ứng dụng Mac", "Máy ảo macOS", "Tệp Mac", "Cài đặt Máy Mac" vào Win12
# Chép mac-apps.js, mac-vm.js vào win12/scripts và nạp chúng cuối desktop.html.
# Chạy lại nhiều lần vẫn an toàn.
# =====================================================
set -e
REPO="$(cd "$(dirname "$0")" && pwd)"

WIN12="$HOME/win12"
cd "$WIN12"

for f in mac-apps.js mac-vm.js mac-bridge.js mac-files.js mac-settings.js mac-realdata.js mac-appkit.js; do
    cp "$REPO/$f" "scripts/$f"
    if ! grep -q "scripts/$f" desktop.html; then
        export F="$f"
        perl -0pi -e 's{</body>}{  <script src="scripts/$ENV{F}"></script>\n  </body>}i' desktop.html
    fi
    if grep -q "scripts/$f" desktop.html; then
        echo "Đã gắn $f"
    else
        echo "LỖI: không gắn được $f vào desktop.html"
        exit 1
    fi
done
