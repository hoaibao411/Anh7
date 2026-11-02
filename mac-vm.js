/* =========================================================
   Cửa sổ "Máy ảo macOS" trong Win12 (app Anh 7)
   - Cửa sổ kéo thả, đổi kích thước, phóng to, thu nhỏ kiểu Win12
   - Báo vị trí vùng màn hình cho Swift để đặt màn hình máy ảo đúng chỗ
   - Nút cài đặt / bật / tắt, hiện tiến độ tải và cài
   Phím tắt: Ctrl + Shift + M
   ========================================================= */
(function () {
  'use strict';

  var bridge =
    window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.store;
  function send(msg) { if (bridge) bridge.postMessage(msg); }

  var vmState = { state: bridge ? 'loading' : 'browser', progress: 0, message: '' };
  var visible = false;
  var maximized = false;
  var savedRect = null;

  // ---------- Giao diện ----------
  var css = `
  #vmwin-btn { display:flex; align-items:center; justify-content:center; }
  #vmwin-btn svg { width:22px; height:22px; }
  #vmwin {
    position: fixed; left: 120px; top: 60px; width: 960px; height: 640px;
    min-width: 520px; min-height: 360px;
    background: var(--bg70, rgba(245,245,252,.85));
    backdrop-filter: blur(40px) saturate(1.8); -webkit-backdrop-filter: blur(40px) saturate(1.8);
    border-radius: var(--radius-2xl, 12px); overflow: hidden;
    box-shadow: 0 1px 2px #44444460, 0 16px 48px #0005;
    z-index: 90; display: none; flex-direction: column; color: var(--text, #222);
  }
  #vmwin.show { display: flex; }
  #vmwin.max { left: 0 !important; top: 0 !important; width: 100vw !important;
    height: calc(100vh - 60px) !important; border-radius: 0; }
  #vmwin .vt { height: 38px; display:flex; align-items:center; padding-left:12px; gap:8px;
    cursor: default; user-select:none; flex-shrink:0; }
  #vmwin .vt .ti { flex:1; font-size:13px; }
  #vmwin .vt svg.ic { width:16px; height:16px; }
  #vmwin .vt button { width:46px; height:38px; border:0; background:transparent; color:inherit;
    font-size:15px; cursor:pointer; }
  #vmwin .vt button:hover { background: var(--hover, #8882); }
  #vmwin .vt button.x:hover { background:#e81123; color:#fff; }
  #vmwin .tb { display:flex; align-items:center; gap:8px; padding:6px 12px; flex-shrink:0;
    border-bottom: 1px solid #8883; font-size:13px; }
  #vmwin .tb .st { flex:1; opacity:.8; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  #vmwin .tb button { border:0; border-radius:6px; padding:5px 12px; cursor:pointer; font:inherit;
    font-size:12.5px; background: var(--hover, #8882); color:inherit; }
  #vmwin .tb button:hover { filter: brightness(1.1); }
  #vmwin .tb button.pri { background: var(--theme-1, #2983cc); color:#fff; }
  #vmwin .tb button.dan { color:#d13438; }
  #vmwin .tb button[hidden] { display:none; }
  #vmwin .scr { flex:1; position:relative; background:transparent; }
  #vmwin .scr.run { background:#000; }
  #vmwin .card { position:absolute; inset:0; display:flex; flex-direction:column; align-items:center;
    justify-content:center; gap:14px; padding:24px; text-align:center;
    background: transparent; color: var(--text, #222); }
  #vmwin .card[hidden] { display:none; }
  #vmwin .card h2 { margin:0; font-size:20px; font-weight:600; }
  #vmwin .card p { margin:0; max-width:520px; font-size:13px; line-height:1.6; opacity:.8; }
  #vmwin .bar { width:min(420px,80%); height:6px; border-radius:3px; background:#8883; overflow:hidden; }
  #vmwin .bar i { display:block; height:100%; width:0; background: var(--theme-1, #2983cc); transition: width .3s; }
  #vmwin .rz { position:absolute; right:0; bottom:0; width:16px; height:16px; cursor: nwse-resize; z-index:2; }
  `;

  function el(tag, attrs, html) {
    var e = document.createElement(tag);
    for (var k in attrs || {}) e.setAttribute(k, attrs[k]);
    if (html != null) e.innerHTML = html;
    return e;
  }

  var ICON = '<svg class="ic" viewBox="0 0 24 24" aria-hidden="true">' +
    '<defs><linearGradient id="vmwin-g" x1="0" y1="0" x2="1" y2="1">' +
    '<stop offset="0" stop-color="#5ac8fa"/><stop offset="1" stop-color="#7d5cf0"/></linearGradient></defs>' +
    '<rect x="2" y="3" width="20" height="14" rx="2.5" fill="url(#vmwin-g)"/>' +
    '<rect x="4.5" y="5.5" width="15" height="9" rx="1" fill="#fff" opacity=".85"/>' +
    '<rect x="8" y="19" width="8" height="2" rx="1" fill="url(#vmwin-g)"/></svg>';

  var style = el('style', {}, css);
  var win = el('div', { id: 'vmwin', role: 'dialog', 'aria-label': 'Máy ảo macOS' },
    '<div class="vt">' + ICON + '<span class="ti">Máy ảo macOS</span>' +
      '<button type="button" class="mn" title="Thu nhỏ">&#8211;</button>' +
      '<button type="button" class="mx" title="Phóng to">&#9744;</button>' +
      '<button type="button" class="x" title="Đóng cửa sổ (máy ảo vẫn chạy)">&#10005;</button></div>' +
    '<div class="tb"><span class="st"></span>' +
      '<button type="button" class="pri b-install">Cài đặt máy ảo</button>' +
      '<button type="button" class="pri b-start">Bật máy</button>' +
      '<button type="button" class="b-stop" title="Gửi lệnh tắt máy cho macOS bên trong">Tắt máy</button>' +
      '<button type="button" class="dan b-force" title="Tắt ngay như rút điện">Buộc tắt</button>' +
      '<button type="button" class="b-share" title="Mở thư mục chia sẻ với máy ảo">Thư mục chia sẻ</button>' +
      '<button type="button" class="dan b-delete" title="Xóa ổ cứng và cấu hình máy ảo">Xóa máy ảo</button></div>' +
    '<div class="scr"><div class="card"><h2></h2><p></p><div class="bar"><i></i></div></div></div>' +
    '<div class="rz" title="Kéo để đổi kích thước"></div>');

  var $ = function (s) { return win.querySelector(s); };
  var scr = $('.scr'), card = $('.card'), status = $('.st');

  var btn = el('button', {
    type: 'button', class: 'dock-btn', id: 'vmwin-btn',
    'aria-label': 'Máy ảo macOS', win12_title: 'Máy ảo macOS (Ctrl+Shift+M)'
  }, ICON.replace('class="ic"', '').replace('vmwin-g', 'vmwin-g2').replace(/url\(#vmwin-g\)/g, 'url(#vmwin-g2)'));

  // ---------- Nội dung theo trạng thái ----------
  var TEXT = {
    browser: ['Chỉ chạy trong app Anh 7', 'Máy ảo cần app Anh 7 trên máy Mac, không chạy được trên trình duyệt.'],
    loading: ['Đang kiểm tra...', ''],
    notSupported: ['Máy không hỗ trợ', ''],
    notInstalled: ['Chưa có máy ảo',
      'Anh 7 sẽ tải bản macOS mới nhất từ Apple (khoảng 15 GB) và cài vào một máy ảo riêng. ' +
      'Máy ảo dùng tối đa 64 GB ổ đĩa, một nửa RAM (tối đa 8 GB). Quá trình mất khoảng 30–60 phút tùy mạng.'],
    downloading: ['Đang tải bộ cài macOS', ''],
    installing: ['Đang cài macOS vào máy ảo', 'Đừng thoát app trong lúc cài.'],
    stopped: ['Máy ảo đang tắt',
      'Bấm "Bật máy" để khởi động. Chép file .app vào thư mục ~/MayAo-ChiaSe trên máy thật, ' +
      'trong máy ảo mở Finder > /Volumes/My Shared Files để lấy và chạy.'],
    starting: ['Đang bật máy ảo...', ''],
    stopping: ['Đang tắt máy ảo...', ''],
    saving: ['Đang lưu trạng thái...', ''],
    error: ['Có lỗi', '']
  };

  function show(cls, on) { var b = $(cls); if (on) b.removeAttribute('hidden'); else b.setAttribute('hidden', ''); }

  function render() {
    var s = vmState.state;
    var running = s === 'running';
    var t = TEXT[s] || [s, ''];

    card.hidden = running;
    scr.classList.toggle('run', running);
    $('.card h2').textContent = t[0];
    $('.card p').textContent = vmState.message && s !== 'stopped' && s !== 'notInstalled'
      ? vmState.message : (vmState.message && s === 'stopped' ? vmState.message + ' ' + t[1] : t[1]);
    var busy = s === 'downloading' || s === 'installing';
    $('.bar').style.display = busy ? '' : 'none';
    $('.bar i').style.width = Math.round((vmState.progress || 0) * 100) + '%';

    status.textContent = running ? 'Đang chạy · bấm vào màn hình máy ảo để điều khiển' : (t[0]);

    show('.b-install', s === 'notInstalled' || (s === 'error' && !vmState.installed));
    show('.b-start', s === 'stopped' || (s === 'error' && vmState.installed));
    show('.b-stop', running);
    show('.b-force', running || s === 'stopping' || s === 'starting');
    show('.b-share', !!bridge && s !== 'browser' && s !== 'notSupported');
    show('.b-delete', s === 'stopped' || s === 'error');
    btn.classList.toggle('show', visible);
    syncRect(true);
  }

  // Swift gọi hàm này mỗi khi trạng thái máy ảo đổi
  window.__vmState = function (st) {
    if (st.state === 'stopped' || st.state === 'running' || st.state === 'starting') vmState.installed = true;
    if (st.state === 'notInstalled') vmState.installed = false;
    vmState.state = st.state;
    vmState.progress = st.progress || 0;
    vmState.message = st.message || '';
    render();
  };

  // ---------- Đồng bộ vị trí màn hình máy ảo với Swift ----------
  var lastRect = '';
  function syncRect(force) {
    var r = scr.getBoundingClientRect();
    var on = visible && vmState.state === 'running' && r.width > 20 && r.height > 20;
    var payload = on
      ? { action: 'vmRect', visible: true, x: r.left, y: r.top, w: r.width, h: r.height }
      : { action: 'vmRect', visible: false };
    var key = JSON.stringify(payload);
    if (force || key !== lastRect) { lastRect = key; send(payload); }
  }
  // Kiểm tra định kỳ phòng trường hợp Win12 đổi bố cục (thanh tác vụ, toàn màn hình...)
  setInterval(function () { syncRect(false); }, 300);
  window.addEventListener('resize', function () { syncRect(false); });

  // ---------- Kéo thả & đổi kích thước ----------
  function drag(handle, onMove) {
    handle.addEventListener('mousedown', function (e) {
      if (e.button !== 0 || e.target.closest('button')) return;
      e.preventDefault();
      var sx = e.clientX, sy = e.clientY, r = win.getBoundingClientRect();
      function mv(ev) { onMove(ev.clientX - sx, ev.clientY - sy, r); syncRect(false); }
      function up() { document.removeEventListener('mousemove', mv); document.removeEventListener('mouseup', up); syncRect(true); }
      document.addEventListener('mousemove', mv);
      document.addEventListener('mouseup', up);
    });
  }
  drag($('.vt'), function (dx, dy, r) {
    if (maximized) return;
    win.style.left = Math.max(-r.width + 120, Math.min(innerWidth - 120, r.left + dx)) + 'px';
    win.style.top = Math.max(0, Math.min(innerHeight - 80, r.top + dy)) + 'px';
  });
  drag($('.rz'), function (dx, dy, r) {
    if (maximized) return;
    win.style.width = Math.max(520, r.width + dx) + 'px';
    win.style.height = Math.max(360, r.height + dy) + 'px';
  });
  $('.vt').addEventListener('dblclick', function (e) { if (!e.target.closest('button')) toggleMax(); });

  function toggleMax() {
    maximized = !maximized;
    win.classList.toggle('max', maximized);
    $('.mx').innerHTML = maximized ? '&#10697;' : '&#9744;';
    $('.mx').title = maximized ? 'Khôi phục' : 'Phóng to';
    syncRect(true);
  }

  // ---------- Mở / đóng ----------
  function open() {
    visible = true;
    win.classList.add('show');
    send({ action: 'vmStatus' });
    render();
  }
  function hide() {
    visible = false;
    win.classList.remove('show');
    send({ action: 'vmBlur' });
    render();
  }
  function toggle() { visible ? hide() : open(); }
  // Cho bảng Ứng dụng gọi khi mở app của máy ảo
  window.__vmWinOpen = open;

  btn.addEventListener('click', function (e) { e.stopPropagation(); toggle(); });
  $('.mn').addEventListener('click', hide);
  $('.x').addEventListener('click', hide);
  $('.mx').addEventListener('click', toggleMax);

  // ---------- Nút điều khiển ----------
  $('.b-install').addEventListener('click', function () {
    if (confirm('Tải bộ cài macOS khoảng 15 GB từ Apple và tạo máy ảo (tối đa 64 GB ổ đĩa)?\n\nCó thể mất 30–60 phút. Bắt đầu?')) {
      send({ action: 'vmInstall' });
    }
  });
  $('.b-start').addEventListener('click', function () { send({ action: 'vmStart' }); });
  $('.b-stop').addEventListener('click', function () { send({ action: 'vmStop' }); });
  $('.b-force').addEventListener('click', function () {
    if (confirm('Buộc tắt máy ảo ngay (như rút điện)? Dữ liệu chưa lưu trong máy ảo có thể mất.')) send({ action: 'vmForceStop' });
  });
  $('.b-share').addEventListener('click', function () { send({ action: 'vmShare' }); });
  $('.b-delete').addEventListener('click', function () {
    if (confirm('Xóa máy ảo? Toàn bộ ổ cứng và dữ liệu bên trong máy ảo sẽ mất vĩnh viễn.\n(Thư mục chia sẻ ~/MayAo-ChiaSe không bị xóa.)')) {
      send({ action: 'vmDelete' });
    }
  });

  // Bấm ra ngoài cửa sổ máy ảo -> trả bàn phím về Win12
  document.addEventListener('mousedown', function (e) {
    if (!win.contains(e.target)) send({ action: 'vmBlur' });
  }, true);

  document.addEventListener('keydown', function (e) {
    if (e.ctrlKey && e.shiftKey && (e.key === 'M' || e.key === 'm')) { e.preventDefault(); toggle(); }
  });

  // ---------- Gắn vào Win12 ----------
  function mount() {
    document.head.appendChild(style);
    document.body.appendChild(win);
    var anchor = document.getElementById('macapps-btn') || document.getElementById('search-btn');
    if (anchor && anchor.parentNode) anchor.parentNode.insertBefore(btn, anchor.nextSibling);
    else {
      var dock = document.querySelector('#dock-box .dock');
      if (dock) dock.appendChild(btn);
    }
    render();
    send({ action: 'vmStatus' });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mount);
  else setTimeout(mount, 0);
})();
