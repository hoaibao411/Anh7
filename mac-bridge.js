/* =========================================================
   Cầu nối gọi lệnh Swift từ Win12 (dùng chung cho Tệp Mac, Cài đặt Máy Mac)
   anh7.call('files.list', { path: '/Users/...' }).then(ketQua).catch(loi)
   ========================================================= */
(function () {
  'use strict';
  var bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.store;
  var pending = {};
  var nextId = 1;

  window.__hostReply = function (id, result, error) {
    var p = pending[id];
    if (!p) return;
    delete pending[id];
    if (error) p.reject(new Error(error));
    else p.resolve(result);
  };

  window.anh7 = {
    available: !!bridge,
    call: function (op, args) {
      return new Promise(function (resolve, reject) {
        if (!bridge) { reject(new Error('Chỉ dùng được trong app Anh 7.')); return; }
        var id = nextId++;
        pending[id] = { resolve: resolve, reject: reject };
        bridge.postMessage({ action: 'host', id: id, op: op, args: args || {} });
        // Không có trả lời sau 20 giây thì báo lỗi, tránh treo giao diện
        setTimeout(function () {
          if (pending[id]) { delete pending[id]; reject(new Error('Không có phản hồi từ Anh 7.')); }
        }, 20000);
      });
    },
    // Đường dẫn để Win12 xem trực tiếp file thật (ảnh, video, PDF...)
    fileURL: function (path) {
      return 'anh7file://' + path.split('/').map(encodeURIComponent).join('/');
    }
  };

  // Cửa sổ kiểu Win12 dùng chung: kéo thả, đổi kích thước, phóng to, đóng
  window.anh7.makeWindow = function (opts) {
    var win = document.createElement('div');
    win.className = 'anh7-win';
    win.id = opts.id;
    win.style.left = (opts.left || 140) + 'px';
    win.style.top = (opts.top || 70) + 'px';
    win.style.width = (opts.width || 900) + 'px';
    win.style.height = (opts.height || 580) + 'px';
    win.innerHTML =
      '<div class="aw-t">' + (opts.icon || '') + '<span class="aw-ti"></span>' +
      '<button type="button" class="aw-mn" title="Thu nhỏ">&#8211;</button>' +
      '<button type="button" class="aw-mx" title="Phóng to">&#9744;</button>' +
      '<button type="button" class="aw-x" title="Đóng">&#10005;</button></div>' +
      '<div class="aw-body"></div><div class="aw-rz"></div>';
    win.querySelector('.aw-ti').textContent = opts.title;
    var maximized = false;

    function drag(handle, move) {
      handle.addEventListener('mousedown', function (e) {
        if (e.button !== 0 || e.target.closest('button')) return;
        e.preventDefault();
        var sx = e.clientX, sy = e.clientY, r = win.getBoundingClientRect();
        function mv(ev) { if (!maximized) move(ev.clientX - sx, ev.clientY - sy, r); }
        function up() { document.removeEventListener('mousemove', mv); document.removeEventListener('mouseup', up); }
        document.addEventListener('mousemove', mv);
        document.addEventListener('mouseup', up);
      });
    }
    drag(win.querySelector('.aw-t'), function (dx, dy, r) {
      win.style.left = Math.max(-r.width + 120, Math.min(innerWidth - 120, r.left + dx)) + 'px';
      win.style.top = Math.max(0, Math.min(innerHeight - 80, r.top + dy)) + 'px';
    });
    drag(win.querySelector('.aw-rz'), function (dx, dy, r) {
      win.style.width = Math.max(opts.minWidth || 560, r.width + dx) + 'px';
      win.style.height = Math.max(opts.minHeight || 360, r.height + dy) + 'px';
    });
    function toggleMax() {
      maximized = !maximized;
      win.classList.toggle('max', maximized);
    }
    win.querySelector('.aw-t').addEventListener('dblclick', function (e) { if (!e.target.closest('button')) toggleMax(); });
    win.querySelector('.aw-mx').addEventListener('click', toggleMax);
    var api = {
      el: win,
      body: win.querySelector('.aw-body'),
      setTitle: function (t) { win.querySelector('.aw-ti').textContent = t; },
      show: function () { win.classList.add('show'); api.front(); if (opts.onShow) opts.onShow(); },
      hide: function () { win.classList.remove('show'); },
      toggle: function () { win.classList.contains('show') ? api.hide() : api.show(); },
      visible: function () { return win.classList.contains('show'); },
      front: function () { window.anh7._z = (window.anh7._z || 91) + 1; win.style.zIndex = window.anh7._z; }
    };
    win.addEventListener('mousedown', api.front);
    win.querySelector('.aw-mn').addEventListener('click', api.hide);
    win.querySelector('.aw-x').addEventListener('click', api.hide);
    return api;
  };

  var css = `
  .anh7-win { position: fixed; display: none; flex-direction: column; overflow: hidden; z-index: 91;
    min-width: 560px; min-height: 360px; color: var(--text, #222);
    background: var(--bg70, rgba(245,245,252,.86));
    backdrop-filter: blur(40px) saturate(1.8); -webkit-backdrop-filter: blur(40px) saturate(1.8);
    border-radius: var(--radius-2xl, 12px); box-shadow: 0 1px 2px #44444460, 0 16px 48px #0005; }
  .anh7-win.show { display: flex; }
  .anh7-win.max { left: 0 !important; top: 0 !important; width: 100vw !important;
    height: calc(100vh - 60px) !important; border-radius: 0; }
  .anh7-win .aw-t { height: 38px; display: flex; align-items: center; gap: 8px; padding-left: 12px;
    flex-shrink: 0; user-select: none; }
  .anh7-win .aw-t svg { width: 16px; height: 16px; }
  .anh7-win .aw-ti { flex: 1; font-size: 13px; }
  .anh7-win .aw-t button { width: 46px; height: 38px; border: 0; background: transparent; color: inherit;
    font-size: 15px; cursor: pointer; }
  .anh7-win .aw-t button:hover { background: var(--hover, #8882); }
  .anh7-win .aw-t button.aw-x:hover { background: #e81123; color: #fff; }
  .anh7-win .aw-body { flex: 1; min-height: 0; display: flex; flex-direction: column; position: relative; }
  .anh7-win .aw-rz { position: absolute; right: 0; bottom: 0; width: 16px; height: 16px; cursor: nwse-resize; z-index: 5; }
  .anh7-btn { border: 0; border-radius: 6px; padding: 5px 11px; cursor: pointer; font: inherit; font-size: 12.5px;
    background: var(--hover, #8882); color: inherit; white-space: nowrap; }
  .anh7-btn:hover { filter: brightness(1.08); }
  .anh7-btn:disabled { opacity: .45; cursor: default; }
  .anh7-btn.pri { background: var(--theme-1, #2983cc); color: #fff; }
  .anh7-btn.dan { color: #d13438; }
  .anh7-switch { position: relative; width: 40px; height: 20px; flex-shrink: 0; }
  .anh7-switch input { opacity: 0; width: 0; height: 0; }
  .anh7-switch span { position: absolute; inset: 0; border-radius: 10px; background: #8886; cursor: pointer; transition: .2s; }
  .anh7-switch span::before { content: ''; position: absolute; width: 14px; height: 14px; left: 3px; top: 3px;
    border-radius: 50%; background: #fff; transition: .2s; }
  .anh7-switch input:checked + span { background: var(--theme-1, #2983cc); }
  .anh7-switch input:checked + span::before { transform: translateX(20px); }
  `;
  var style = document.createElement('style');
  style.textContent = css;
  (document.head || document.documentElement).appendChild(style);

  // Thêm nút vào thanh tác vụ Win12 (sau nút cho trước)
  window.anh7.addDockButton = function (btn, afterIds) {
    function mount() {
      for (var i = 0; i < afterIds.length; i++) {
        var a = document.getElementById(afterIds[i]);
        if (a && a.parentNode) { a.parentNode.insertBefore(btn, a.nextSibling); return; }
      }
      var dock = document.querySelector('#dock-box .dock');
      if (dock) dock.appendChild(btn);
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mount);
    else mount();
  };
})();
