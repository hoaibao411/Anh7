/* =========================================================
   Trang "Máy Mac" trong Cài đặt Win12
   - Âm thanh & hiển thị: âm lượng, tắt tiếng, chế độ tối của macOS
   - Thông tin máy: pin, CPU, RAM, ổ đĩa, Wi-Fi (tự cập nhật 3 giây/lần)
   - Máy ảo: RAM, số nhân CPU, độ phân giải (áp dụng lần bật máy ảo sau)
   - Khởi động & giao diện app Anh 7
   ========================================================= */
(function () {
  'use strict';
  if (!window.anh7) return;
  var anh7 = window.anh7;
  var PAGE = 'anh7mac';

  var css = `
  #win-setting .cnt.anh7mac { padding-bottom: 30px; }
  .am-sec { margin: 18px 25px 6px; font-size: 15px; font-weight: 600; }
  .am-card { margin: 6px 25px; padding: 12px 16px; border-radius: 8px; display: flex; align-items: center; gap: 14px;
    background: var(--card, rgba(255,255,255,.55)); box-shadow: 0 1px 2px #0001; }
  .am-card .tx { flex: 1; min-width: 0; }
  .am-card .tx p { margin: 0; }
  .am-card .tx p + p { font-size: 12px; opacity: .65; margin-top: 2px; }
  .am-card input[type=range] { width: 220px; accent-color: var(--theme-1, #2983cc); }
  .am-card select { font: inherit; font-size: 13px; padding: 4px 8px; border-radius: 6px; border: 1px solid #8885;
    background: var(--bg, #fff); color: inherit; min-width: 150px; }
  .am-card .anh7-btn + .anh7-btn { margin-left: 6px; }
  .am-val { min-width: 42px; text-align: right; font-variant-numeric: tabular-nums; font-size: 13px; }
  .am-grid { margin: 6px 25px; display: grid; grid-template-columns: repeat(auto-fill, minmax(190px, 1fr)); gap: 8px; }
  .am-stat { padding: 12px 14px; border-radius: 8px; background: var(--card, rgba(255,255,255,.55)); box-shadow: 0 1px 2px #0001; }
  .am-stat .k { font-size: 12px; opacity: .65; }
  .am-stat .v { font-size: 20px; font-weight: 600; margin: 4px 0; font-variant-numeric: tabular-nums; }
  .am-stat .s { font-size: 12px; opacity: .65; }
  .am-bar { height: 5px; border-radius: 3px; background: #8883; overflow: hidden; margin-top: 6px; }
  .am-bar i { display: block; height: 100%; background: var(--theme-1, #2983cc); width: 0; transition: width .4s; }
  .am-note { margin: 4px 25px; font-size: 12px; opacity: .65; }
  .am-err { margin: 6px 25px; font-size: 12px; color: #d13438; min-height: 14px; }
  `;

  var MENU_ICON = 'data:image/svg+xml;utf8,' + encodeURIComponent(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">' +
    '<stop offset="0" stop-color="#5ac8fa"/><stop offset="1" stop-color="#7d5cf0"/></linearGradient></defs>' +
    '<rect x="2" y="4" width="20" height="13" rx="2.5" fill="url(#g)"/><rect x="7" y="19" width="10" height="2" rx="1" fill="url(#g)"/></svg>');

  function sw(id) {
    return '<label class="anh7-switch"><input type="checkbox" id="' + id + '"><span></span></label>';
  }
  function card(title, desc, control) {
    return '<div class="am-card"><div class="tx"><p>' + title + '</p>' + (desc ? '<p>' + desc + '</p>' : '') + '</div>' + control + '</div>';
  }
  function stat(id, label) {
    return '<div class="am-stat" id="' + id + '"><div class="k">' + label + '</div><div class="v">–</div><div class="s"></div>' +
      '<div class="am-bar"><i></i></div></div>';
  }

  var HTML =
    '<p class="title">Máy Mac</p>' +
    '<div class="am-err" id="am-err"></div>' +

    '<div class="am-sec">Âm thanh & hiển thị</div>' +
    card('Âm lượng', 'Âm lượng loa của máy Mac', '<input type="range" id="am-vol" min="0" max="100" step="1"><span class="am-val" id="am-vol-v">–</span>') +
    card('Tắt tiếng', '', sw('am-mute')) +
    card('Chế độ tối của macOS', 'Lần đầu bật, macOS sẽ hỏi quyền cho Anh 7 điều khiển "System Events" — bấm OK', sw('am-dark')) +
    card('Độ sáng màn hình', 'Màn hình tích hợp của Mac', '<input type="range" id="am-bri" min="0" max="100" step="1"><span class="am-val" id="am-bri-v">–</span>') +

    '<div class="am-sec">Kết nối & nguồn</div>' +
    card('Wi-Fi', '<span id="am-wifi-d"></span>', sw('am-wifi-sw')) +
    card('Bluetooth', 'macOS có thể chặn đổi từ app — khi đó dùng Trung tâm điều khiển của Mac', sw('am-bt')) +
    card('Khóa máy Mac', 'Về màn hình khóa, cần mật khẩu để mở lại', '<button type="button" class="anh7-btn" id="am-lock">Khóa ngay</button>') +
    card('Cho máy Mac ngủ', 'Máy ảo đang chạy sẽ tạm dừng theo', '<button type="button" class="anh7-btn" id="am-sleep">Ngủ</button>') +

    '<div class="am-sec">Hình nền</div>' +
    card('Hình nền Win12', 'Chọn ảnh trên Mac làm hình nền desktop Win12',
      '<button type="button" class="anh7-btn" id="am-wp-win">Chọn ảnh...</button>' +
      '<button type="button" class="anh7-btn" id="am-wp-win-reset">Mặc định</button>') +
    card('Hình nền máy Mac', 'Đổi hình nền thật của macOS (mọi màn hình)',
      '<button type="button" class="anh7-btn" id="am-wp-mac">Chọn ảnh...</button>') +

    '<div class="am-sec">Người dùng Win12</div>' +
    card('Tên hiển thị', 'Hiện ở màn hình đăng nhập, menu Start, Cài đặt. Để trống = tên người dùng Mac',
      '<input type="text" id="am-name" style="font:inherit;font-size:13px;padding:5px 8px;border-radius:6px;border:1px solid #8885;background:var(--bg,#fff);color:inherit;width:200px">') +
    card('Ảnh đại diện', 'Chọn ảnh trên Mac',
      '<button type="button" class="anh7-btn" id="am-av">Chọn ảnh...</button>' +
      '<button type="button" class="anh7-btn" id="am-av-reset">Mặc định</button>') +

    '<div class="am-sec">Thông tin máy Mac</div>' +
    '<div class="am-grid">' + stat('am-bat', 'Pin') + stat('am-cpu', 'CPU') + stat('am-mem', 'Bộ nhớ (RAM)') +
      stat('am-disk', 'Ổ đĩa') + stat('am-wifi', 'Wi-Fi') + stat('am-host', 'Máy') + '</div>' +

    '<div class="am-sec">Máy ảo macOS</div>' +
    card('Bộ nhớ (RAM) cho máy ảo', 'Nhiều hơn = máy ảo mượt hơn nhưng máy thật chậm hơn', '<select id="am-vmmem"></select>') +
    card('Số nhân CPU cho máy ảo', '', '<select id="am-vmcpu"></select>') +
    card('Độ phân giải màn hình máy ảo', 'macOS 14 trở lên: tự khớp theo kích thước cửa sổ, đây là độ phân giải khởi đầu',
      '<select id="am-vmres">' +
        '<option value="">Mặc định (1920 × 1200)</option>' +
        '<option value="1280x800">1280 × 800 (nhẹ)</option>' +
        '<option value="1680x1050">1680 × 1050</option>' +
        '<option value="1920x1200">1920 × 1200</option>' +
        '<option value="2560x1600">2560 × 1600 (nét, nặng)</option>' +
      '</select>') +
    '<p class="am-note">Thay đổi máy ảo có hiệu lực từ lần bật máy ảo tiếp theo (tắt hẳn rồi bật lại).</p>' +

    '<div class="am-sec">Khởi động & giao diện app Anh 7</div>' +
    card('Tự vào toàn màn hình khi mở app', '', sw('am-full')) +
    card('Bỏ qua màn hình đăng nhập Win12', '', sw('am-skip')) +
    card('Tự bật máy ảo khi mở app', 'Chỉ khi máy ảo đã cài', sw('am-autovm')) +
    card('Dùng Tệp Mac thay Trình quản lý tệp Win12', 'Mở "PC này" / Trình quản lý tệp sẽ hiện file thật của máy Mac', sw('am-explorer')) +

    '<div class="am-sec">Dữ liệu</div>' +
    card('Nơi lưu dữ liệu Anh 7', '<span id="am-path"></span>',
      '<button type="button" class="anh7-btn" id="am-openpath">Mở</button>');

  var page = null, settings = {}, limits = {}, timer = null, volTimer = null, dataPath = '';

  function $(id) { return document.getElementById(id); }
  function showErr(e) { var el = $('am-err'); if (el) el.textContent = e ? (e.message || String(e)) : ''; }

  function gb(n) { return (n / 1073741824).toFixed(1).replace('.', ',') + ' GB'; }

  function setStat(id, value, sub, pct) {
    var el = $(id);
    if (!el) return;
    el.querySelector('.v').textContent = value;
    el.querySelector('.s').textContent = sub || '';
    var bar = el.querySelector('.am-bar');
    bar.style.display = pct == null ? 'none' : '';
    if (pct != null) bar.querySelector('i').style.width = Math.max(0, Math.min(100, pct)) + '%';
  }

  // ---------- Thông tin máy (cập nhật liên tục khi trang đang mở) ----------
  var userTouching = false;
  function refresh() {
    anh7.call('sys.info').then(function (i) {
      showErr(null);
      var b = i.battery || {};
      if (b.available) setStat('am-bat', b.percent + '%', b.charging ? 'Đang sạc' : (b.plugged ? 'Đã cắm sạc' : 'Dùng pin'), b.percent);
      else setStat('am-bat', 'Không có', 'Máy dùng điện trực tiếp', null);
      if (i.cpu != null) setStat('am-cpu', Math.round(i.cpu) + '%', 'Đang dùng', i.cpu);
      else setStat('am-cpu', '…', 'Đang đo', null);
      if (i.memory) setStat('am-mem', gb(i.memory.used), 'trên ' + gb(i.memory.total), i.memory.used / i.memory.total * 100);
      if (i.disk) setStat('am-disk', gb(i.disk.free), 'còn trống trên ' + gb(i.disk.total), (1 - i.disk.free / i.disk.total) * 100);
      var wf = i.wifi || {};
      setStat('am-wifi', !wf.on ? 'Tắt' : (wf.ssid || 'Đang bật'),
        wf.on && !wf.ssid ? 'macOS ẩn tên mạng nếu app chưa có quyền Vị trí' : '', null);
      if (i.host) setStat('am-host', i.host.computerName || 'Mac', (i.host.model || '') + ' · ' + (i.host.macOS || ''), null);
      $('am-wifi-d').textContent = wf.on ? (wf.ssid ? 'Đang kết nối: ' + wf.ssid : 'Đang bật') : 'Đang tắt';
      if (!userTouching) {
        $('am-wifi-sw').checked = !!wf.on;
        if (i.bluetooth != null) $('am-bt').checked = !!i.bluetooth; else $('am-bt').disabled = true;
        if (i.brightness != null) {
          $('am-bri').value = Math.round(i.brightness * 100);
          $('am-bri-v').textContent = Math.round(i.brightness * 100) + '%';
        } else { $('am-bri').disabled = true; $('am-bri-v').textContent = 'Không hỗ trợ'; }
        if (i.volume != null) { $('am-vol').value = i.volume; $('am-vol-v').textContent = i.volume + '%'; }
        if (i.muted != null) $('am-mute').checked = i.muted;
        if (i.dark != null) $('am-dark').checked = i.dark;
      }
    }).catch(showErr);
  }

  // ---------- Đọc / lưu cài đặt ----------
  function loadSettings() {
    return anh7.call('app.getSettings').then(function (r) {
      settings = r.settings || {}; limits = r.limits || {}; dataPath = r.dataPath || '';
      var mem = $('am-vmmem'), cpu = $('am-vmcpu');
      mem.innerHTML = '<option value="0">Tự động (khuyên dùng)</option>';
      for (var g = 3; g <= (limits.maxMemGB || 8); g++) mem.insertAdjacentHTML('beforeend', '<option value="' + g + '">' + g + ' GB</option>');
      cpu.innerHTML = '<option value="0">Tự động (khuyên dùng)</option>';
      for (var c = 2; c <= (limits.maxCPU || 4); c++) cpu.insertAdjacentHTML('beforeend', '<option value="' + c + '">' + c + ' nhân</option>');
      mem.value = String(settings.vmMemGB || 0);
      cpu.value = String(settings.vmCPU || 0);
      $('am-vmres').value = settings.vmWidth ? settings.vmWidth + 'x' + settings.vmHeight : '';
      $('am-full').checked = !!settings.startFullscreen;
      $('am-skip').checked = !!settings.skipLogin;
      $('am-autovm').checked = !!settings.autoStartVM;
      var rep = true;
      try { rep = localStorage.getItem('anh7.replaceExplorer') !== '0'; } catch (e) {}
      $('am-explorer').checked = rep;
      $('am-path').textContent = dataPath + (r.portable ? ' (bản di động)' : '');
    }).catch(showErr);
  }

  function save(obj) {
    anh7.call('app.setSettings', { settings: obj }).then(function () { showErr(null); }).catch(showErr);
  }

  // ---------- Gắn sự kiện ----------
  function bind() {
    var vol = $('am-vol');
    vol.addEventListener('input', function () {
      userTouching = true;
      $('am-vol-v').textContent = vol.value + '%';
      clearTimeout(volTimer);
      volTimer = setTimeout(function () {
        anh7.call('sys.setVolume', { level: Number(vol.value) }).catch(showErr).then(function () { userTouching = false; });
      }, 120);
    });
    $('am-mute').addEventListener('change', function () { anh7.call('sys.setMuted', { muted: this.checked }).catch(showErr); });
    $('am-dark').addEventListener('change', function () {
      var el = this;
      anh7.call('sys.setDark', { dark: el.checked }).catch(function (e) { el.checked = !el.checked; showErr(e); });
    });
    $('am-vmmem').addEventListener('change', function () { save({ vmMemGB: Number(this.value) }); });
    $('am-vmcpu').addEventListener('change', function () { save({ vmCPU: Number(this.value) }); });
    $('am-vmres').addEventListener('change', function () {
      var v = this.value.split('x');
      save(v.length === 2 ? { vmWidth: Number(v[0]), vmHeight: Number(v[1]) } : { vmWidth: 0, vmHeight: 0 });
    });
    $('am-full').addEventListener('change', function () { save({ startFullscreen: this.checked }); });
    $('am-skip').addEventListener('change', function () { save({ skipLogin: this.checked }); });
    $('am-autovm').addEventListener('change', function () { save({ autoStartVM: this.checked }); });
    $('am-explorer').addEventListener('change', function () {
      try { localStorage.setItem('anh7.replaceExplorer', this.checked ? '1' : '0'); } catch (e) {}
    });
    // Độ sáng
    var briTimer = null;
    $('am-bri').addEventListener('input', function () {
      userTouching = true;
      var el = this;
      $('am-bri-v').textContent = el.value + '%';
      clearTimeout(briTimer);
      briTimer = setTimeout(function () {
        anh7.call('sys.setBrightness', { level: Number(el.value) / 100 }).catch(showErr).then(function () { userTouching = false; });
      }, 80);
    });

    // Wi-Fi / Bluetooth: lỗi thì trả công tắc về vị trí cũ
    function toggle(id, op) {
      $(id).addEventListener('change', function () {
        var el = this;
        anh7.call(op, { on: el.checked }).then(function () { showErr(null); refresh(); })
          .catch(function (e) { el.checked = !el.checked; showErr(e); });
      });
    }
    toggle('am-wifi-sw', 'sys.setWifi');
    toggle('am-bt', 'sys.setBluetooth');

    $('am-lock').addEventListener('click', function () { anh7.call('sys.lock').catch(showErr); });
    $('am-sleep').addEventListener('click', function () {
      if (confirm('Cho máy Mac ngủ ngay?')) anh7.call('sys.sleep').catch(showErr);
    });

    // Hình nền & ảnh đại diện (ảnh được chép vào thư mục dữ liệu Anh 7)
    function pick(message) { return anh7.call('app.pickImage', { message: message }); }
    function store(key, val) { try { if (val) localStorage.setItem(key, val); else localStorage.removeItem(key); } catch (e) {} }
    function refreshLook() { if (window.anh7RealData) window.anh7RealData.refresh(); }

    $('am-wp-win').addEventListener('click', function () {
      pick('Chọn ảnh làm hình nền Win12').then(function (r) { if (r) { store('anh7.wallpaper', r.rel); refreshLook(); } }).catch(showErr);
    });
    $('am-wp-win-reset').addEventListener('click', function () { store('anh7.wallpaper', null); refreshLook(); });
    $('am-wp-mac').addEventListener('click', function () {
      pick('Chọn ảnh làm hình nền máy Mac').then(function (r) {
        if (r) return anh7.call('sys.setMacWallpaper', { path: r.path }).then(function () { showErr(null); });
      }).catch(showErr);
    });
    $('am-av').addEventListener('click', function () {
      pick('Chọn ảnh đại diện').then(function (r) { if (r) { store('anh7.avatar', r.rel); refreshLook(); } }).catch(showErr);
    });
    $('am-av-reset').addEventListener('click', function () { store('anh7.avatar', null); refreshLook(); });

    var nameEl = $('am-name');
    try { nameEl.value = localStorage.getItem('anh7.userName') || ''; } catch (e) {}
    nameEl.placeholder = (window.__anh7Host && window.__anh7Host.fullName) || 'Tên người dùng Mac';
    nameEl.addEventListener('change', function () { store('anh7.userName', nameEl.value.trim()); refreshLook(); });

    $('am-openpath').addEventListener('click', function () {
      if (window.anh7.openFiles && dataPath.indexOf('/Library/') === -1) window.anh7.openFiles(dataPath);
      else anh7.call('files.reveal', { path: dataPath }).catch(showErr);
    });
  }

  // ---------- Chèn vào Cài đặt Win12 ----------
  function mount() {
    var setting = document.getElementById('win-setting');
    if (!setting || document.querySelector('#win-setting .cnt.' + PAGE)) return !!setting;
    var list = setting.querySelector('.menu list');
    var pages = setting.querySelector('.page');
    if (!list || !pages) return false;

    var st = document.createElement('style');
    st.textContent = css;
    document.head.appendChild(st);

    var item = document.createElement('a');
    item.className = 'enable ' + PAGE;
    item.innerHTML = '<img alt=""><span>Máy Mac</span>';
    item.querySelector('img').src = MENU_ICON;
    item.addEventListener('click', function () { typeof apps !== 'undefined' && apps.setting && apps.setting.page(PAGE); });
    var focs = list.querySelector('.focs');
    list.insertBefore(item, focs || null);

    page = document.createElement('div');
    page.className = 'cnt ' + PAGE;
    page.innerHTML = HTML;
    pages.appendChild(page);

    if (!anh7.available) {
      $('am-err').textContent = 'Chỉ dùng được khi chạy trong app Anh 7.';
      return true;
    }
    bind();

    // Chỉ hỏi thông tin máy khi trang Máy Mac đang hiện
    new MutationObserver(function () {
      var shown = page.classList.contains('show');
      if (shown && !timer) { loadSettings(); refresh(); timer = setInterval(refresh, 3000); }
      if (!shown && timer) { clearInterval(timer); timer = null; }
    }).observe(page, { attributes: true, attributeFilter: ['class'] });
    return true;
  }

  // Cửa sổ Cài đặt của Win12 được tạo sau khi trang nạp -> thử lại cho đến khi có
  var tries = 0;
  (function wait() {
    if (mount() || ++tries > 60) return;
    setTimeout(wait, 500);
  })();

  // Mở thẳng trang Máy Mac (dùng cho nút khác)
  window.anh7.openMacSettings = function () {
    if (typeof window.openapp === 'function') window.openapp('setting');
    setTimeout(function () { if (typeof apps !== 'undefined' && apps.setting) apps.setting.page(PAGE); }, 300);
  };
})();
