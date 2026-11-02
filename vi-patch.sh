#!/bin/bash
# =====================================================
# Gắn tiếng Việt vào Win12 Online
# - Tải bản dịch gốc (kho phụ win12-locales) nếu chưa có
# - Chép lang_vi.properties vào win12/lang/lang/
# - Đăng ký mã "vi" + thêm lựa chọn "Tiếng Việt" ở màn hình đăng nhập và Cài đặt
# - Định dạng ngày kiểu Việt Nam
# Chạy lại nhiều lần vẫn an toàn (đã sửa rồi thì bỏ qua).
# =====================================================
set -e
REPO="$(cd "$(dirname "$0")" && pwd)"

WIN12="$HOME/win12"
VI_FILE="$REPO/lang_vi.properties"

cd "$WIN12"

# 1. Tải bản dịch gốc (zh_CN, zh_TW, en) từ kho phụ
if [ ! -f lang/lang/lang_en.properties ]; then
    git submodule update --init --depth 1
fi
echo "Bản dịch gốc: $(ls lang/lang/*.properties | wc -l | tr -d ' ') file"

# 2. Chép bản dịch tiếng Việt
cp "$VI_FILE" lang/lang/lang_vi.properties
echo "Đã chép lang_vi.properties"

# 3. Đăng ký mã ngôn ngữ vi (máy để tiếng Việt thì "Tự động" cũng chọn vi)
if ! grep -q "'vi-VN'" data/languages.js; then
    perl -0pi -e "s/(\n\s*en: 'en',)/\n  vi: 'vi',\n  'vi-VN': 'vi',\n  'vi-vn': 'vi',\$1/" data/languages.js
fi

# 4. Thêm "Tiếng Việt" vào danh sách ngôn ngữ ở màn hình đăng nhập
if ! grep -q 'class="a vi"' desktop.html; then
    perl -0pi -e "s/(>English<\/a\s*\n\s*>)/\$1\n        <a\n          class=\"a vi\"\n          onclick=\"\n            localStorage.setItem('lang', 'vi');\n            window.location.href = '';\n          \"\n          >Tiếng Việt<\/a\n        >/" desktop.html
fi

# 5. Thêm "Tiếng Việt" vào ô chọn ngôn ngữ trong Cài đặt
if ! grep -q 'option value="vi"' data/window-templates.js; then
    perl -0pi -e 's/(<option value="en">English<\/option>)/$1\n\t\t\t\t\t\t\t\t\t<option value="vi">Tiếng Việt<\/option>/' data/window-templates.js
fi

# 6. Định dạng ngày tiếng Việt: "Thứ Hai, 01/11/2026"
if ! grep -q "  vi: \`" desktop.js; then
    perl -0pi -e 's/(\n\}\[langcode\];)/\n  vi: `\${["Chủ Nhật", "Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy"][da.getDay()]}, \${da.getDate().toString().padStart(2, "0")}\/\${(da.getMonth() + 1).toString().padStart(2, "0")}\/\${da.getFullYear()}`,$1/' desktop.js
fi

# 7. Lớp dịch tự động cho chữ tiếng Trung viết cứng trong mã
cp "$REPO/vi-runtime.js" scripts/vi-runtime.js
for page in desktop.html boot.html bluescreen.html shutdown.html reload.html 404.html \
            data/disconnected.html data/disconnected_dark.html games/minesweeper.html; do
    [ -f "$page" ] || continue
    grep -q "vi-runtime.js" "$page" && continue
    case "$page" in */*) src="../scripts/vi-runtime.js" ;; *) src="scripts/vi-runtime.js" ;; esac
    # Chèn ngay sau thẻ <head> để chạy sớm nhất
    export SRC="$src"; perl -0pi -e 's{(<head[^>]*>)}{$1\n    <script src="$ENV{SRC}"></script>}i' "$page"
done
echo "Đã gắn lớp dịch tự động"

# 8. Kiểm tra từng điểm sửa
ok=0
grep -q "'vi-VN'" data/languages.js            && ok=$((ok+1)) || echo "LỖI: languages.js"
grep -q 'class="a vi"' desktop.html            && ok=$((ok+1)) || echo "LỖI: desktop.html"
grep -q 'option value="vi"' data/window-templates.js && ok=$((ok+1)) || echo "LỖI: window-templates.js"
grep -q "  vi: \`" desktop.js                  && ok=$((ok+1)) || echo "LỖI: desktop.js"
[ -f lang/lang/lang_vi.properties ]            && ok=$((ok+1)) || echo "LỖI: lang_vi.properties"
grep -q "vi-runtime.js" desktop.html           && ok=$((ok+1)) || echo "LỖI: lớp dịch tự động"
echo "Đã gắn tiếng Việt: $ok/6 điểm"
