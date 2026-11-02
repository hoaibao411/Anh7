# NOTICE — Ghi công bên thứ ba

## Win12 Online

- Nguồn: https://github.com/win12-online/win12 (trước đây: https://github.com/tjy-gitnub/win12)
- Tác giả: tjy-gitnub (Tan Jingyuan), Starry Source và các cộng tác viên của dự án
- Giấy phép mã nguồn: Eclipse Public License 2.0 (EPL-2.0) — https://www.eclipse.org/legal/epl-2.0/
- Giấy phép hình ảnh/âm thanh: Creative Commons BY-SA (theo ghi chú trong repo gốc)

Anh 7 không chứa sẵn mã nguồn Win12 trong repo này. Khi build, mã nguồn Win12 được tải
từ repo gốc, sau đó các script `vi-patch.sh` và `mac-patch.sh` áp những thay đổi sau:

| Thay đổi | File |
|---|---|
| Thêm bản dịch tiếng Việt | `lang/lang/lang_vi.properties`, `scripts/vi-runtime.js` |
| Đăng ký ngôn ngữ `vi`, định dạng ngày | `data/languages.js`, `desktop.html`, `login.html` |
| Nạp các phần mở rộng Mac | `desktop.html` + `scripts/mac-*.js` |

Toàn bộ mã nguồn của các thay đổi trên nằm trong repo này, phát hành theo EPL-2.0.
Bản app phát hành (file .zip trong Releases) có kèm file LICENSE gốc của Win12.

## Font và logo

- Logo Anh 7 (W12) do dự án tự thiết kế, không dùng tài nguyên bên thứ ba.

## Thương hiệu

"Windows" và logo Windows là thương hiệu của Microsoft Corporation. Anh 7 và Win12 Online
là dự án độc lập, không liên kết và không được Microsoft bảo trợ.
