/* =========================================================
   APP ANH 7 — nền tảng app riêng chạy trong Win12, không cần máy chủ
   - "Ứng dụng Anh 7" (Ctrl+Shift+K): xem, mở, cài, gỡ app
   - Mỗi app chạy trong 1 cửa sổ Win12, bên trong khung cách ly (iframe sandbox)
     nên app KHÔNG đụng được vào Win12 hay file máy Mac.
   - App gọi chức năng qua Anh7 SDK (postMessage). Lớp này kiểm tra quyền rồi mới làm.

   Quyền (khai báo trong app.json -> "permissions"):
     (mặc định)  lưu dữ liệu riêng của app, đặt tiêu đề, đóng cửa sổ
     "notify"    hiện thông báo
     "system"    đọc thông tin máy (pin, RAM, CPU...) — hỏi người dùng lần đầu
     "files"     đọc/ghi file trong thư mục nhà — hỏi người dùng lần đầu
   ========================================================= */
(function () {
  'use strict';
  if (!window.anh7 || !window.anh7.makeWindow) return;

  var ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">' +
    '<rect x="3" y="3" width="7.5" height="7.5" rx="2"/><rect x="13.5" y="3" width="7.5" height="7.5" rx="3.75"/>' +
    '<rect x="3" y="13.5" width="7.5" height="7.5" rx="3.75"/><rect x="13.5" y="13.5" width="7.5" height="7.5" rx="2"/></svg>';

  var PERM_NAMES = { notify: 'hiện thông báo', system: 'đọc thông tin máy Mac (pin, RAM, CPU, Wi‑Fi)', files: 'đọc và sửa file trong thư mục nhà của bạn' };
  var ASK_PERMS = { system: true, files: true };   // quyền phải hỏi người dùng

  var apps = [];          // danh sách app (từ Swift)
  var running = {};       // id -> { win, frame, app }

  // ---------- Giao diện ----------
  var css = `
  #anh7store .as-tb { display: flex; gap: 8px; align-items: center; padding: 6px 14px 10px; }
  #anh7store .as-tb .sp { flex: 1; }
  #anh7store .as-tb input { border: 0; border-radius: 6px; padding: 6px 10px; width: 200px; font: inherit; font-size: 12.5px;
    background: var(--hover, #8882); color: inherit; outline: none; }
  #anh7store .as-grid { flex: 1; overflow: auto; padding: 4px 14px 14px; display: grid;
    grid-template-columns: repeat(auto-fill, minmax(116px, 1fr)); gap: 8px; align-content: start; }
  #anh7store .as-app { display: flex; flex-direction: column; align-items: center; gap: 8px; padding: 14px 6px 10px;
    border-radius: 10px; cursor: pointer; text-align: center; position: relative; }
  #anh7store .as-app:hover { background: var(--hover, #8882); }
  #anh7store .as-app.sel { background: var(--hover-b, #8883); }
  #anh7store .as-ic { width: 56px; height: 56px; border-radius: 14px; display: grid; place-items: center; overflow: hidden;
    font-size: 26px; font-weight: 600; color: #fff; box-shadow: 0 2px 8px #0002; }
  #anh7store .as-ic img { width: 100%; height: 100%; object-fit: cover; }
  #anh7store .as-nm { font-size: 12.5px; line-height: 1.3; }
  #anh7store .as-tag { font-size: 10.5px; opacity: .55; }
  #anh7store .as-info { border-top: 1px solid #8883; padding: 10px 14px; display: flex; gap: 10px; align-items: center;
    font-size: 12.5px; min-height: 52px; }
  #anh7store .as-info .tx { flex: 1; min-width: 0; }
  #anh7store .as-info .tx b { display: block; }
  #anh7store .as-info .tx span { opacity: .7; }
  #anh7store .as-empty { grid-column: 1 / -1; text-align: center; opacity: .6; padding: 40px 0; font-size: 13px; }
  #anh7store .as-help { display: none; flex: 1; overflow: auto; padding: 4px 20px 20px; font-size: 13px; line-height: 1.6; }
  #anh7store.help .as-help { display: block; }
  #anh7store.help .as-grid, #anh7store.help .as-info { display: none; }
  #anh7store .as-help pre { background: #8881; border-radius: 8px; padding: 10px 12px; font-size: 12px; overflow: auto; }
  .anh7-win.a7app .aw-body iframe { flex: 1; width: 100%; border: 0; background: transparent; }
  .anh7-win.a7app { min-width: 260px; min-height: 200px; }
  body.a7-drag .anh7-win iframe { pointer-events: none; }
  #a7-toasts { position: fixed; right: 16px; bottom: 76px; z-index: 100000; display: flex; flex-direction: column; gap: 8px; }
  #a7-toasts .t { width: 300px; padding: 12px 14px; border-radius: 10px; font-size: 12.5px; color: var(--text, #222);
    background: var(--bg70, rgba(245,245,252,.92)); backdrop-filter: blur(30px); -webkit-backdrop-filter: blur(30px);
    box-shadow: 0 8px 28px #0004; animation: a7in .25s ease; }
  #a7-toasts .t b { display: block; margin-bottom: 2px; font-size: 13px; }
  #a7-toasts .t small { opacity: .6; }
  @keyframes a7in { from { transform: translateX(30px); opacity: 0; } }
  `;
  var st = document.createElement('style');
  st.textContent = css;
  document.head.appendChild(st);

  // Khi kéo/đổi kích thước cửa sổ, tạm "tắt chuột" cho iframe để chuột không bị app nuốt
  document.addEventListener('mousedown', function (e) {
    if (e.target.closest && e.target.closest('.anh7-win .aw-t, .anh7-win .aw-rz')) document.body.classList.add('a7-drag');
  }, true);
  document.addEventListener('mouseup', function () { document.body.classList.remove('a7-drag'); }, true);

  function esc(s) { var d = document.createElement('div'); d.textContent = s == null ? '' : String(s); return d.innerHTML; }
  function isDark() {
    return document.documentElement.classList.contains('dark') || document.body.classList.contains('dark');
  }
  function iconHTML(app) {
    if (app.icon) return '<img src="anh7app://' + app.id + '/' + encodeURI(app.icon) + '" alt="">';
    var colors = ['#2b7de9', '#16a085', '#8e44ad', '#e67e22', '#c0392b', '#2c3e50'];
    var c = app.color || colors[app.id.length % colors.length];
    return '<span style="background:' + esc(c) + ';width:100%;height:100%;display:grid;place-items:center">' +
      esc((app.name || '?').trim().charAt(0).toUpperCase()) + '</span>';
  }

  // ---------- Thông báo ----------
  function toast(title, text, from) {
    var box = document.getElementById('a7-toasts');
    if (!box) { box = document.createElement('div'); box.id = 'a7-toasts'; document.body.appendChild(box); }
    var t = document.createElement('div');
    t.className = 't';
    t.innerHTML = '<b>' + esc(title) + '</b>' + esc(text) + (from ? '<br><small>' + esc(from) + '</small>' : '');
    box.appendChild(t);
    setTimeout(function () { t.remove(); }, 5000);
  }
  window.anh7.toast = toast;

  // ---------- Cửa sổ "Ứng dụng Anh 7" ----------
  var w = anh7.makeWindow({ id: 'anh7store', title: 'Ứng dụng Anh 7', icon: ICON, width: 680, height: 500, left: 220, top: 80,
    onShow: function () { refresh(); } });
  w.body.innerHTML =
    '<div class="as-tb">' +
      '<input type="search" class="q" placeholder="Tìm app">' +
      '<span class="sp"></span>' +
      '<button type="button" class="anh7-btn pri b-install">Cài app…</button>' +
      '<button type="button" class="anh7-btn b-folder">Thư mục app</button>' +
      '<button type="button" class="anh7-btn b-help">Tự làm app</button>' +
    '</div>' +
    '<div class="as-grid"></div>' +
    '<div class="as-info"><div class="tx"><span>Chọn một app để xem thông tin. Bấm đúp để mở.</span></div></div>' +
    '<div class="as-help"></div>';
  document.body.appendChild(w.el);
  var $ = function (s) { return w.el.querySelector(s); };
  var selected = null;

  $('.as-help').innerHTML =
    '<p><b>App Anh 7</b> là một thư mục gồm <code>app.json</code> và <code>index.html</code> (HTML/CSS/JS thuần). ' +
    'App chạy ngay trong Win12, không cần máy chủ, không cần Internet.</p>' +
    '<pre>{\n  "id": "vn.tencuaban.vidu",\n  "name": "Ví dụ",\n  "version": "1.0.0",\n  "entry": "index.html",\n  "icon": "icon.svg",\n  "width": 520,\n  "height": 400,\n  "permissions": ["notify"]\n}</pre>' +
    '<p>Trong <code>index.html</code>, nạp thư viện Anh 7:</p>' +
    '<pre>&lt;link rel="stylesheet" href="anh7app://_sdk/anh7-ui.css"&gt;\n&lt;script src="anh7app://_sdk/anh7-sdk.js"&gt;&lt;/script&gt;\n&lt;script&gt;\n  Anh7.storage.get().then(function (data) { /* dữ liệu đã lưu */ });\n  Anh7.storage.set({ diem: 10 });\n  Anh7.notify("Xong", "Đã lưu");\n&lt;/script&gt;</pre>' +
    '<p>Quyền có thể xin: <code>notify</code> (thông báo), <code>system</code> (thông tin máy), <code>files</code> (file trong thư mục nhà). ' +
    'Hai quyền sau sẽ hỏi người dùng trước.</p>' +
    '<p>Cài: nén thư mục thành <code>.zip</code> (hoặc đổi đuôi thành <code>.anh7app</code>) rồi bấm <b>Cài app…</b>; hoặc chọn thẳng thư mục.</p>' +
    '<p><button type="button" class="anh7-btn b-back">← Quay lại danh sách</button></p>';

  function render() {
    var q = $('.q').value.trim().toLowerCase();
    var list = apps.filter(function (a) { return !q || (a.name + ' ' + a.description).toLowerCase().indexOf(q) >= 0; });
    var grid = $('.as-grid');
    if (!list.length) {
      grid.innerHTML = '<div class="as-empty">' + (apps.length ? 'Không có app khớp.' : 'Chưa có app. Bấm "Cài app…" để thêm.') + '</div>';
      return;
    }
    grid.innerHTML = list.map(function (a) {
      return '<div class="as-app' + (selected === a.id ? ' sel' : '') + '" data-id="' + esc(a.id) + '" title="' + esc(a.description) + '">' +
        '<div class="as-ic">' + iconHTML(a) + '</div><div class="as-nm">' + esc(a.name) + '</div>' +
        '<div class="as-tag">' + (a.builtin ? 'Có sẵn' : 'Đã cài') + '</div></div>';
    }).join('');
  }

  function showInfo(app) {
    var box = $('.as-info');
    if (!app) { box.innerHTML = '<div class="tx"><span>Chọn một app để xem thông tin. Bấm đúp để mở.</span></div>'; return; }
    var perms = (app.permissions || []).map(function (p) { return PERM_NAMES[p] || p; });
    box.innerHTML = '<div class="tx"><b>' + esc(app.name) + (app.version ? ' · ' + esc(app.version) : '') + '</b>' +
      '<span>' + esc(app.description || 'Không có mô tả') + (app.author ? ' — ' + esc(app.author) : '') +
      (perms.length ? '<br>Quyền: ' + esc(perms.join(', ')) : '') + '</span></div>' +
      '<button type="button" class="anh7-btn pri i-open">Mở</button>' +
      (app.builtin ? '' : '<button type="button" class="anh7-btn dan i-remove">Gỡ</button>');
    box.querySelector('.i-open').addEventListener('click', function () { openApp(app.id); });
    var rm = box.querySelector('.i-remove');
    if (rm) rm.addEventListener('click', function () { removeApp(app); });
  }

  function refresh() {
    return anh7.call('apps.list').then(function (list) {
      apps = list || [];
      render();
      showInfo(apps.filter(function (a) { return a.id === selected; })[0]);
    }).catch(function (e) { $('.as-grid').innerHTML = '<div class="as-empty">' + esc(e.message) + '</div>'; });
  }

  $('.as-grid').addEventListener('click', function (e) {
    var el = e.target.closest('.as-app');
    if (!el) return;
    selected = el.dataset.id;
    // Chỉ đổi lớp "sel", không vẽ lại lưới (vẽ lại sẽ làm mất thao tác bấm đúp)
    $('.as-grid').querySelectorAll('.as-app').forEach(function (x) { x.classList.toggle('sel', x === el); });
    showInfo(apps.filter(function (a) { return a.id === selected; })[0]);
  });
  $('.as-grid').addEventListener('dblclick', function (e) {
    var el = e.target.closest('.as-app');
    if (el) openApp(el.dataset.id);
  });
  $('.q').addEventListener('input', render);
  $('.b-help').addEventListener('click', function () { w.el.classList.add('help'); });
  w.el.querySelector('.as-help').addEventListener('click', function (e) {
    if (e.target.closest('.b-back')) w.el.classList.remove('help');
  });
  $('.b-folder').addEventListener('click', function () { anh7.call('apps.openFolder').catch(function (e) { alert(e.message); }); });
  $('.b-install').addEventListener('click', function () {
    anh7.call('apps.install').then(function (r) {
      if (!r) return;   // người dùng bấm Hủy
      if (running[r.id]) closeApp(r.id);
      selected = r.id;
      refresh();
      toast(r.replaced ? 'Đã cập nhật app' : 'Đã cài app', r.name);
    }).catch(function (e) { alert('Không cài được app: ' + e.message); });
  });

  function removeApp(app) {
    if (!confirm('Gỡ app "' + app.name + '"? App và dữ liệu của nó sẽ vào Thùng rác.')) return;
    closeApp(app.id);
    anh7.call('apps.remove', { id: app.id }).then(function () {
      try { Object.keys(localStorage).forEach(function (k) { if (k.indexOf('anh7.perm.' + app.id + '.') === 0) localStorage.removeItem(k); }); } catch (e) {}
      selected = null;
      refresh();
    }).catch(function (e) { alert(e.message); });
  }

  // ---------- Chạy app ----------
  var seq = 0;
  function openApp(id) {
    if (running[id]) { running[id].win.show(); return; }
    var app = apps.filter(function (a) { return a.id === id; })[0];
    if (!app) {   // chưa nạp danh sách -> nạp rồi mở
      return refresh().then(function () { if (apps.some(function (a) { return a.id === id; })) openApp(id); });
    }
    var n = ++seq;
    var win = anh7.makeWindow({
      id: 'a7app-' + n, title: app.name, icon: '<span class="as-mini" style="width:16px;height:16px;border-radius:4px;overflow:hidden;display:inline-block">' + iconHTML(app) + '</span>',
      width: Math.max(260, Math.min(app.width || 720, innerWidth - 80)),
      height: Math.max(200, Math.min((app.height || 480) + 38, innerHeight - 120)),
      left: 120 + (n % 6) * 36, top: 50 + (n % 6) * 30, minWidth: 260, minHeight: 200
    });
    win.el.classList.add('a7app');
    document.body.appendChild(win.el);
    var frame = document.createElement('iframe');
    // Cách ly: không cùng nguồn với Win12, không điều hướng được trang Win12
    frame.setAttribute('sandbox', 'allow-scripts allow-forms allow-modals allow-popups allow-downloads');
    frame.setAttribute('allow', 'clipboard-write');
    frame.src = 'anh7app://' + id + '/' + encodeURI(app.entry || 'index.html');
    frame.addEventListener('load', function () { send(frame, { event: 'theme', dark: isDark() }); });
    win.body.appendChild(frame);
    win.el.querySelector('.aw-x').addEventListener('click', function () { closeApp(id); });
    running[id] = { win: win, frame: frame, app: app };
    win.show();
  }

  function closeApp(id) {
    var r = running[id];
    if (!r) return;
    delete running[id];
    r.win.hide();
    r.win.el.remove();   // xóa hẳn iframe -> app dừng chạy, giải phóng bộ nhớ
  }

  window.anh7.openApp = openApp;
  window.anh7.refreshApps = refresh;

  // ---------- API cho app (postMessage) ----------
  function send(frame, msg) {
    msg.anh7 = 1;
    try { frame.contentWindow.postMessage(msg, '*'); } catch (e) {}
  }

  function findBySource(src) {
    for (var id in running) if (running[id].frame.contentWindow === src) return running[id];
    return null;
  }

  // Kiểm tra quyền: phải khai báo trong app.json; quyền nhạy cảm hỏi người dùng 1 lần
  function needPerm(r, perm) {
    if ((r.app.permissions || []).indexOf(perm) < 0) {
      throw new Error('App chưa khai báo quyền "' + perm + '" trong app.json.');
    }
    if (!ASK_PERMS[perm]) return;
    var key = 'anh7.perm.' + r.app.id + '.' + perm;
    var v = null;
    try { v = localStorage.getItem(key); } catch (e) {}
    if (v === '1') return;
    if (v === '0') throw new Error('Người dùng đã từ chối quyền "' + perm + '".');
    var ok = confirm('App "' + r.app.name + '" muốn ' + PERM_NAMES[perm] + '.\n\nCho phép?');
    try { localStorage.setItem(key, ok ? '1' : '0'); } catch (e) {}
    if (!ok) throw new Error('Người dùng đã từ chối quyền "' + perm + '".');
  }

  var FILE_OPS = { 'files.places': 1, 'files.list': 1, 'files.readText': 1, 'files.writeText': 1, 'files.mkdir': 1, 'files.newText': 1 };

  function handleOp(r, op, args) {
    var id = r.app.id;
    switch (op) {
      case 'app.info':
        return { id: id, name: r.app.name, version: r.app.version, dark: isDark(), permissions: r.app.permissions || [] };
      case 'storage.get':
        return anh7.call('apps.dataGet', { id: id }).then(function (t) { try { return JSON.parse(t || '{}'); } catch (e) { return {}; } });
      case 'storage.set':
        return anh7.call('apps.dataSet', { id: id, json: JSON.stringify(args.data == null ? {} : args.data) });
      case 'ui.setTitle':
        r.win.setTitle(String(args.title || r.app.name).slice(0, 80));
        return true;
      case 'ui.close':
        setTimeout(function () { closeApp(id); }, 0);
        return true;
      case 'ui.notify':
        needPerm(r, 'notify');
        toast(String(args.title || r.app.name).slice(0, 80), String(args.text || '').slice(0, 300), r.app.name);
        return true;
      case 'sys.info':
        needPerm(r, 'system');
        return anh7.call('sys.info').then(function (i) {
          return { battery: i.battery, memory: i.memory, cpu: i.cpu, disk: i.disk, wifi: i.wifi, dark: i.dark, host: i.host };
        });
      default:
        if (FILE_OPS[op]) { needPerm(r, 'files'); return anh7.call(op, args); }
        throw new Error('Lệnh không hỗ trợ: ' + op);
    }
  }

  window.addEventListener('message', function (e) {
    var d = e.data;
    if (!d || d.anh7 !== 1 || typeof d.op !== 'string') return;
    var r = findBySource(e.source);
    if (!r) return;   // không phải app Anh 7 đang chạy -> bỏ qua
    var frame = r.frame;
    Promise.resolve().then(function () { return handleOp(r, d.op, d.args || {}); })
      .then(function (result) { send(frame, { id: d.id, result: result === undefined ? null : result }); })
      .catch(function (err) { send(frame, { id: d.id, error: (err && err.message) || String(err) }); });
  });

  // Báo app khi Win12 đổi sáng/tối
  new MutationObserver(function () {
    var dark = isDark();
    for (var id in running) send(running[id].frame, { event: 'theme', dark: dark });
  }).observe(document.documentElement, { attributes: true, attributeFilter: ['class'] });

  // ---------- Nút thanh tác vụ + phím tắt ----------
  var btn = document.createElement('button');
  btn.type = 'button'; btn.className = 'dock-btn'; btn.id = 'anh7store-btn';
  btn.setAttribute('aria-label', 'Ứng dụng Anh 7');
  btn.setAttribute('win12_title', 'Ứng dụng Anh 7 (Ctrl+Shift+K)');
  btn.innerHTML = ICON;
  btn.addEventListener('click', function (e) { e.stopPropagation(); w.toggle(); });
  anh7.addDockButton(btn, ['macfiles-btn', 'vmwin-btn', 'macapps-btn', 'search-btn']);

  document.addEventListener('keydown', function (e) {
    if (e.ctrlKey && e.shiftKey && (e.key === 'K' || e.key === 'k')) { e.preventDefault(); w.toggle(); }
  });
})();
