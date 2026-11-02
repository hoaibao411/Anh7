/* =========================================================
   "Ứng dụng Mac" cho Win12 trong app Anh 7
   - Thêm nút trên thanh tác vụ Win12
   - Bảng kiểu Launchpad: tên + icon thật của app trên máy Mac, có tìm kiếm
   - Bấm vào app -> Swift mở app Mac thật (cửa sổ macOS bình thường)
   Phím tắt: Ctrl + Shift + A để mở/đóng bảng
   ========================================================= */
(function () {
  'use strict';

  var bridge =
    window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.store;

  var apps = [];
  var loaded = false;

  // ---------- Giao diện ----------
  var css = `
  #macapps-btn { display:flex; align-items:center; justify-content:center; }
  #macapps-btn svg { width:22px; height:22px; }
  #macapps {
    position: fixed; left: 50%; bottom: 62px; transform: translate(-50%, 16px);
    width: min(860px, calc(100vw - 32px)); height: min(560px, calc(100vh - 110px));
    background: var(--contextmeu, rgba(240,240,250,.8));
    backdrop-filter: blur(30px) saturate(1.8); -webkit-backdrop-filter: blur(30px) saturate(1.8);
    border-radius: var(--radius-2xl, 14px);
    box-shadow: 0 1px 2px #44444460, 0 12px 40px #0004;
    z-index: 95; display: flex; flex-direction: column; padding: 18px 20px 12px;
    opacity: 0; pointer-events: none; transition: opacity .2s, transform .25s cubic-bezier(.2,.8,.2,1);
    color: var(--text, #222); font-family: inherit;
  }
  #macapps.show { opacity: 1; pointer-events: auto; transform: translate(-50%, 0); }
  #macapps .mh { display:flex; align-items:center; gap:12px; margin-bottom:14px; }
  #macapps .mh h3 { margin:0; font-size:18px; font-weight:600; flex:1; }
  #macapps .tabs { display:inline-flex; background: var(--hover, #8882); border-radius:9px; padding:3px; }
  #macapps .tabs button { border:0; background:transparent; color:inherit; font:inherit; font-size:13px;
    padding:5px 14px; border-radius:7px; cursor:pointer; }
  #macapps .tabs button.on { background: var(--bg, #fff); box-shadow: 0 1px 3px #0002; font-weight:600; }
  #macapps .ma-msg button { display:block; margin:14px auto 0; border:0; border-radius:8px; padding:7px 16px; cursor:pointer;
    background: var(--theme-1, #2983cc); color:#fff; font:inherit; font-size:13px; }
  #macapps .ma-msg code { background:#8882; padding:1px 6px; border-radius:4px; }
  #macapps .mh button {
    border:0; background: var(--hover, #8882); color:inherit; border-radius:8px;
    padding:6px 12px; cursor:pointer; font:inherit; font-size:13px;
  }
  #macapps .mh button:hover { filter: brightness(1.1); background: var(--hover-b, #8884); }
  #macapps input {
    width:100%; box-sizing:border-box; padding:9px 14px; border-radius:20px; margin-bottom:12px;
    border:1px solid #8884; background: var(--bg, #fff8); color:inherit; font:inherit; outline:none;
  }
  #macapps input:focus { border-color: var(--theme-1, #2983cc); }
  #macapps .grid {
    flex:1; overflow-y:auto; display:grid; gap:6px;
    grid-template-columns: repeat(auto-fill, minmax(104px, 1fr)); align-content:start;
  }
  #macapps .app {
    display:flex; flex-direction:column; align-items:center; gap:6px; padding:12px 6px;
    border-radius:10px; cursor:pointer; text-align:center; border:0; background:transparent; color:inherit; font:inherit;
  }
  #macapps .app:hover, #macapps .app:focus-visible { background: var(--hover, #8882); outline:none; }
  #macapps .app img { width:56px; height:56px; }
  #macapps .app span {
    font-size:12px; line-height:1.3; max-width:100%; overflow:hidden; text-overflow:ellipsis;
    display:-webkit-box; -webkit-line-clamp:2; -webkit-box-orient:vertical; word-break:break-word;
  }
  #macapps .app.opening img { animation: macapps-bounce .5s ease 2; }
  @keyframes macapps-bounce { 50% { transform: translateY(-10px); } }
  #macapps .ma-msg { grid-column:1/-1; text-align:center; opacity:.7; padding:40px 0; }
  #macapps .foot { font-size:11px; opacity:.6; padding-top:8px; text-align:center; }
  `;

  function el(tag, attrs, html) {
    var e = document.createElement(tag);
    for (var k in attrs || {}) e.setAttribute(k, attrs[k]);
    if (html != null) e.innerHTML = html;
    return e;
  }

  var style = el('style', {}, css);
  var panel = el('div', { id: 'macapps', role: 'dialog', 'aria-label': 'Ứng dụng Mac' },
    '<div class="mh"><h3>Ứng dụng</h3>' +
    '<div class="tabs"><button type="button" class="on" data-src="host">Máy Mac</button>' +
    '<button type="button" data-src="vm">Máy ảo</button></div>' +
    '<button type="button" class="reload" title="Quét lại thư mục Ứng dụng">Làm mới</button>' +
    '<button type="button" class="close" title="Đóng (Esc)">Đóng</button></div>' +
    '<input type="text" placeholder="Tìm ứng dụng..." aria-label="Tìm ứng dụng">' +
    '<div class="grid"></div>' +
    '<div class="foot"></div>');
  var grid = panel.querySelector('.grid');
  var search = panel.querySelector('input');
  var foot = panel.querySelector('.foot');

  // Nguồn đang xem: "host" = app máy Mac thật, "vm" = app trong máy ảo
  var source = 'host';
  var vmApps = [];
  var vmLoaded = false;
  var vmInfo = { running: false, agent: false };
  var FOOT = {
    host: 'App mở bằng macOS thật, cửa sổ hiện ngoài Win12 · Ctrl + Shift + A',
    vm: 'App mở bên trong máy ảo, hiện trong cửa sổ Máy ảo macOS của Win12 · Ctrl + Shift + A'
  };

  // Icon nút: lưới 4 ô bo góc (biểu tượng riêng, không dùng logo Apple)
  var btn = el('button', {
    type: 'button', class: 'dock-btn', id: 'macapps-btn',
    'aria-label': 'Ứng dụng Mac', win12_title: 'Ứng dụng Mac (Ctrl+Shift+A)'
  }, '<svg viewBox="0 0 24 24" aria-hidden="true">' +
     '<defs><linearGradient id="macapps-g" x1="0" y1="0" x2="1" y2="1">' +
     '<stop offset="0" stop-color="#5ac8fa"/><stop offset="1" stop-color="#7d5cf0"/></linearGradient></defs>' +
     '<rect x="2" y="2" width="9" height="9" rx="2.5" fill="url(#macapps-g)"/>' +
     '<rect x="13" y="2" width="9" height="9" rx="2.5" fill="url(#macapps-g)" opacity=".85"/>' +
     '<rect x="2" y="13" width="9" height="9" rx="2.5" fill="url(#macapps-g)" opacity=".85"/>' +
     '<rect x="13" y="13" width="9" height="9" rx="2.5" fill="url(#macapps-g)" opacity=".7"/></svg>');

  // ---------- Hiển thị danh sách ----------
  function message(text) {
    grid.innerHTML = '';
    grid.appendChild(el('div', { class: 'ma-msg' })).textContent = text;
  }

  function render() {
    foot.textContent = FOOT[source];
    if (source === 'vm' && !renderVmState()) return;
    if (source === 'host' && !loaded) { message(bridge ? 'Đang tải danh sách ứng dụng...' : 'Chỉ dùng được khi chạy trong app Anh 7 (không chạy trên trình duyệt).'); return; }
    var q = search.value.trim().toLowerCase();
    var list = (source === 'vm' ? vmApps : apps).filter(function (a) { return !q || a.name.toLowerCase().indexOf(q) !== -1; });
    grid.innerHTML = '';
    if (!list.length) { message(q ? 'Không tìm thấy ứng dụng.' : 'Không có ứng dụng nào.'); return; }
    list.forEach(function (a) {
      var b = el('button', { type: 'button', class: 'app', title: a.path });
      var img = el('img', { alt: '' });
      img.src = a.icon ? 'data:image/png;base64,' + a.icon : '';
      var name = el('span');
      name.textContent = a.name;
      b.appendChild(img); b.appendChild(name);
      b.addEventListener('click', function () { launch(a, b); });
      grid.appendChild(b);
    });
  }

  // Máy ảo chưa sẵn sàng -> hiện hướng dẫn thay cho danh sách; trả về true nếu hiện danh sách được
  function renderVmState() {
    if (!bridge) { message('Chỉ dùng được khi chạy trong app Anh 7 (không chạy trên trình duyệt).'); return false; }
    if (!vmLoaded) { message('Đang hỏi máy ảo...'); return false; }
    if (!vmInfo.running) {
      message('Máy ảo đang tắt. Bật máy ảo để xem và mở app bên trong.');
      var b = grid.querySelector('.ma-msg').appendChild(el('button', { type: 'button' }, 'Mở cửa sổ máy ảo'));
      b.addEventListener('click', function () { close(); if (window.__vmWinOpen) window.__vmWinOpen(); });
      return false;
    }
    if (!vmInfo.agent && !vmApps.length) {
      grid.innerHTML = '';
      var m = grid.appendChild(el('div', { class: 'ma-msg' }));
      m.innerHTML = 'Chưa cài <b>trợ lý Anh 7</b> trong máy ảo (cài 1 lần):<br><br>' +
        '1. Trong máy ảo mở Finder > <code>Cmd + Shift + G</code> > gõ <code>/Volumes/My Shared Files</code><br>' +
        '2. Mở thư mục <b>Tro ly Anh 7</b> > bấm đúp <b>Cai dat tro ly Anh 7.command</b><br>' +
        '3. macOS hỏi quyền thì bấm <b>Cho phép</b>, rồi bấm <b>Làm mới</b> ở đây';
      var b2 = m.appendChild(el('button', { type: 'button' }, 'Mở cửa sổ máy ảo'));
      b2.addEventListener('click', function () { close(); if (window.__vmWinOpen) window.__vmWinOpen(); });
      return false;
    }
    return true;
  }

  function load(refresh) {
    if (source === 'vm') { loadVm(); return; }
    if (!bridge) { message('Chỉ dùng được khi chạy trong app Anh 7 (không chạy trên trình duyệt).'); return; }
    message('Đang tải danh sách ứng dụng...');
    bridge.postMessage({ action: 'listApps', refresh: !!refresh });
  }

  // Swift gọi hàm này khi quét xong
  window.__macAppsReceive = function (list) {
    apps = Array.isArray(list) ? list : [];
    loaded = true;
    render();
  };

  function loadVm() {
    if (!bridge) { render(); return; }
    if (!vmLoaded) message('Đang hỏi máy ảo...');
    bridge.postMessage({ action: 'vmApps' });
  }

  // Swift gọi hàm này: { running, agent, apps }
  window.__vmAppsReceive = function (info) {
    info = info || {};
    vmInfo = { running: !!info.running, agent: !!info.agent };
    vmApps = Array.isArray(info.apps) ? info.apps : [];
    vmLoaded = true;
    if (source === 'vm') render();
  };

  // Tab Máy ảo đang mở: hỏi lại mỗi 3 giây (máy ảo vừa bật, trợ lý vừa cài, app mới cài...)
  setInterval(function () {
    if (source === 'vm' && panel.classList.contains('show') && !search.value) loadVm();
  }, 3000);

  // Đổi tab Máy Mac / Máy ảo
  panel.querySelectorAll('.tabs button').forEach(function (t) {
    t.addEventListener('click', function () {
      source = t.getAttribute('data-src');
      panel.querySelectorAll('.tabs button').forEach(function (x) { x.classList.toggle('on', x === t); });
      if (source === 'vm') loadVm(); else if (!loaded) load(false); else render();
      search.focus();
    });
  });

  window.__macAppsError = function (msg) {
    alert('Không mở được ứng dụng:\n' + msg);
  };

  function launch(a, b) {
    if (!bridge) return;
    b.classList.add('opening');
    setTimeout(function () { b.classList.remove('opening'); }, 1000);
    if (source === 'vm') {
      // Mở app trong máy ảo rồi hiện cửa sổ máy ảo để thấy app
      bridge.postMessage({ action: 'vmLaunch', path: a.path });
      setTimeout(function () { close(); if (window.__vmWinOpen) window.__vmWinOpen(); }, 400);
      return;
    }
    bridge.postMessage({ action: 'launchApp', path: a.path });
  }

  // ---------- Mở / đóng ----------
  function open() {
    panel.classList.add('show');
    btn.classList.add('show');
    if (source === 'vm') loadVm(); else if (!loaded) load(false);
    render();
    setTimeout(function () { search.focus(); search.select(); }, 50);
  }
  function close() {
    panel.classList.remove('show');
    btn.classList.remove('show');
  }
  function toggle() { panel.classList.contains('show') ? close() : open(); }

  btn.addEventListener('click', function (e) { e.stopPropagation(); toggle(); });
  panel.querySelector('.close').addEventListener('click', close);
  panel.querySelector('.reload').addEventListener('click', function () { load(true); });
  search.addEventListener('input', render);
  search.addEventListener('keydown', function (e) {
    if (e.key === 'Enter') {
      var first = grid.querySelector('.app');
      if (first) first.click();
    }
  });
  panel.addEventListener('mousedown', function (e) { e.stopPropagation(); });
  document.addEventListener('mousedown', function (e) {
    if (panel.classList.contains('show') && !panel.contains(e.target) && e.target !== btn && !btn.contains(e.target)) close();
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && panel.classList.contains('show')) close();
    if (e.ctrlKey && e.shiftKey && (e.key === 'A' || e.key === 'a')) { e.preventDefault(); toggle(); }
  });

  // ---------- Gắn vào Win12 ----------
  function mount() {
    document.head.appendChild(style);
    document.body.appendChild(panel);
    // Đặt nút ngay sau nút Tìm kiếm trên thanh tác vụ; không có thì gắn vào dock đầu tiên
    var anchor = document.getElementById('search-btn');
    if (anchor && anchor.parentNode) anchor.parentNode.insertBefore(btn, anchor.nextSibling);
    else {
      var dock = document.querySelector('#dock-box .dock');
      if (dock) dock.appendChild(btn);
    }
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mount);
  else mount();
})();
