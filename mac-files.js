/* =========================================================
   "Tệp Mac" — trình quản lý tệp Win12 làm việc với file THẬT trên máy Mac
   - Duyệt thư mục nhà, xem ảnh/video/âm thanh/PDF/văn bản ngay trong Win12
   - Sửa file văn bản, tạo thư mục/tệp mới, đổi tên, đưa vào Thùng rác
   - Mở bằng app Mac, hiện trong Finder
   - Thay cho "Trình quản lý tệp" của Win12 (tắt được trong Cài đặt > Máy Mac)
   Phím tắt: Ctrl + Shift + F
   ========================================================= */
(function () {
  'use strict';
  if (!window.anh7) return;
  var anh7 = window.anh7;

  var EXT = {
    image: 'png jpg jpeg gif webp heic heif bmp tif tiff svg ico',
    video: 'mp4 mov m4v webm',
    audio: 'mp3 m4a wav aac flac aiff aif caf ogg',
    pdf: 'pdf',
    text: 'txt md markdown json js mjs ts tsx jsx css scss html htm xml csv tsv log swift py cs c cpp h hpp m java kt go rs rb php sh zsh bash yml yaml ini conf cfg toml sql lua properties gitignore env plist'
  };
  function kind(ext) {
    for (var k in EXT) if ((' ' + EXT[k] + ' ').indexOf(' ' + ext + ' ') !== -1) return k;
    return '';
  }

  var ICON = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M2 6.5A2.5 2.5 0 0 1 4.5 4h4.2l2 2h8.8A2.5 2.5 0 0 1 22 8.5v9A2.5 2.5 0 0 1 19.5 20h-15A2.5 2.5 0 0 1 2 17.5z" fill="#f7c64a"/><path d="M2 9h20v8.5a2.5 2.5 0 0 1-2.5 2.5h-15A2.5 2.5 0 0 1 2 17.5z" fill="#fbd768"/></svg>';

  var css = `
  #macfiles-btn { display:flex; align-items:center; justify-content:center; }
  #macfiles-btn svg { width:22px; height:22px; }
  #macfiles .mf-tb { display:flex; align-items:center; gap:6px; padding:6px 10px; border-bottom:1px solid #8883; flex-shrink:0; }
  #macfiles .mf-path { flex:1; display:flex; gap:2px; overflow:hidden; font-size:13px; white-space:nowrap; }
  #macfiles .mf-path a { padding:3px 6px; border-radius:5px; cursor:pointer; }
  #macfiles .mf-path a:hover { background: var(--hover, #8882); }
  #macfiles .mf-path i { opacity:.5; font-style:normal; padding:3px 0; }
  #macfiles .mf-main { flex:1; display:flex; min-height:0; }
  #macfiles .mf-side { width:170px; padding:8px; border-right:1px solid #8883; overflow-y:auto; flex-shrink:0; }
  #macfiles .mf-side a { display:block; padding:7px 10px; border-radius:7px; cursor:pointer; font-size:13px;
    white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  #macfiles .mf-side a:hover { background: var(--hover, #8882); }
  #macfiles .mf-side a.on { background: var(--hover-b, #8884); font-weight:600; }
  #macfiles .mf-list { flex:1; overflow-y:auto; padding:4px 6px; }
  #macfiles .mf-row { display:grid; grid-template-columns: 26px 1fr 140px 80px; align-items:center; gap:8px;
    padding:4px 8px; border-radius:6px; font-size:13px; cursor:default; user-select:none; }
  #macfiles .mf-row.head { opacity:.6; font-size:12px; position:sticky; top:0; background: var(--bg70, #f4f4fa); z-index:1; }
  #macfiles .mf-row:not(.head):hover { background: var(--hover, #8882); }
  #macfiles .mf-row.sel, #macfiles .mf-row.sel:hover { background: var(--theme-1, #2983cc); color:#fff; }
  #macfiles .mf-row img { width:22px; height:22px; }
  #macfiles .mf-row span { overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  #macfiles .mf-row .r { text-align:right; opacity:.7; }
  #macfiles .mf-row.sel .r { opacity:.9; }
  #macfiles .mf-empty { text-align:center; opacity:.6; padding:40px 0; font-size:13px; }
  #macfiles .mf-status { padding:4px 12px; font-size:12px; opacity:.7; border-top:1px solid #8883; flex-shrink:0;
    white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  #macfiles .mf-prev { position:absolute; inset:0; display:none; flex-direction:column; z-index:3;
    background: var(--bg70, rgba(245,245,252,.97)); backdrop-filter: blur(30px); -webkit-backdrop-filter: blur(30px); }
  #macfiles .mf-prev.show { display:flex; }
  #macfiles .mf-prev .ph { display:flex; align-items:center; gap:6px; padding:6px 10px; border-bottom:1px solid #8883; }
  #macfiles .mf-prev .ph b { flex:1; font-size:13px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  #macfiles .mf-prev .pc { flex:1; min-height:0; display:flex; align-items:center; justify-content:center; overflow:auto; }
  #macfiles .mf-prev .pc img, #macfiles .mf-prev .pc video { max-width:100%; max-height:100%; }
  #macfiles .mf-prev .pc iframe { width:100%; height:100%; border:0; background:#fff; }
  #macfiles .mf-prev .pc textarea { width:100%; height:100%; box-sizing:border-box; border:0; outline:none; resize:none;
    padding:12px 14px; font: 13px/1.55 ui-monospace, Menlo, monospace; background:transparent; color:inherit; }
  #macfiles .mf-prev .pc .other { text-align:center; font-size:13px; opacity:.8; }
  #macfiles .mf-prev .pc .other img { width:96px; height:96px; display:block; margin:0 auto 12px; }
  #macfiles-menu { position:fixed; z-index:200; min-width:200px; padding:5px; border-radius:9px; display:none;
    background: var(--contextmeu, rgba(250,250,255,.92)); backdrop-filter: blur(20px); -webkit-backdrop-filter: blur(20px);
    box-shadow: 0 1px 2px #44444460, 0 8px 28px #0004; font-size:13px; color: var(--text, #222); }
  #macfiles-menu a { display:block; padding:6px 12px; border-radius:6px; cursor:pointer; }
  #macfiles-menu a:hover { background: var(--hover, #8882); }
  #macfiles-menu a.dan { color:#d13438; }
  #macfiles-menu hr { border:0; border-top:1px solid #8883; margin:4px 2px; }
  `;
  var styleEl = document.createElement('style');
  styleEl.textContent = css;
  document.head.appendChild(styleEl);

  var w = anh7.makeWindow({ id: 'macfiles', title: 'Tệp Mac', icon: ICON, width: 920, height: 580, left: 160, top: 60,
    onShow: function () { if (!state.path) init(); } });
  w.body.innerHTML =
    '<div class="mf-tb">' +
      '<button type="button" class="anh7-btn b-back" title="Quay lại">&#8592;</button>' +
      '<button type="button" class="anh7-btn b-up" title="Lên thư mục cha">&#8593;</button>' +
      '<div class="mf-path"></div>' +
      '<button type="button" class="anh7-btn b-newdir">Thư mục mới</button>' +
      '<button type="button" class="anh7-btn b-newtxt">Tệp văn bản mới</button>' +
      '<button type="button" class="anh7-btn b-hidden" title="Hiện/ẩn file ẩn">File ẩn</button>' +
      '<button type="button" class="anh7-btn b-reload" title="Làm mới">&#10227;</button>' +
    '</div>' +
    '<div class="mf-main"><div class="mf-side"></div><div class="mf-list"></div></div>' +
    '<div class="mf-status"></div>' +
    '<div class="mf-prev"><div class="ph"><button type="button" class="anh7-btn p-back">&#8592; Quay lại</button><b></b>' +
      '<button type="button" class="anh7-btn pri p-save" hidden>Lưu</button>' +
      '<button type="button" class="anh7-btn p-open">Mở bằng app Mac</button>' +
      '<button type="button" class="anh7-btn p-reveal">Hiện trong Finder</button></div>' +
      '<div class="pc"></div></div>';
  document.body.appendChild(w.el);

  var $ = function (s) { return w.el.querySelector(s); };
  var listEl = $('.mf-list'), pathEl = $('.mf-path'), sideEl = $('.mf-side'), statusEl = $('.mf-status');
  var prev = $('.mf-prev'), prevBody = $('.mf-prev .pc');

  var menu = document.createElement('div');
  menu.id = 'macfiles-menu';
  document.body.appendChild(menu);

  var state = { path: '', home: '', items: [], sel: null, hidden: false, history: [], editing: null, dirty: false };

  // ---------- Tiện ích ----------
  function size(n) {
    if (!n) return '';
    var u = ['B', 'KB', 'MB', 'GB', 'TB'], i = 0;
    while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
    return (i ? n.toFixed(1).replace('.', ',') : n) + ' ' + u[i];
  }
  function date(ms) {
    if (!ms) return '';
    var d = new Date(ms), p = function (x) { return String(x).padStart(2, '0'); };
    return p(d.getDate()) + '/' + p(d.getMonth() + 1) + '/' + d.getFullYear() + ' ' + p(d.getHours()) + ':' + p(d.getMinutes());
  }
  function status(t) { statusEl.textContent = t; }
  function fail(e) { alert(e && e.message ? e.message : String(e)); }

  // ---------- Thanh bên ----------
  function loadPlaces() {
    anh7.call('files.places').then(function (places) {
      sideEl.innerHTML = '';
      places.forEach(function (pl) {
        var a = document.createElement('a');
        a.textContent = pl.name;
        a.title = pl.path;
        a.dataset.path = pl.path;
        a.addEventListener('click', function () { go(pl.path); });
        sideEl.appendChild(a);
      });
      markSide();
    }).catch(function () {});
  }
  function markSide() {
    sideEl.querySelectorAll('a').forEach(function (a) { a.classList.toggle('on', a.dataset.path === state.path); });
  }

  // ---------- Thanh đường dẫn ----------
  function renderPath() {
    pathEl.innerHTML = '';
    var rel = state.path.indexOf(state.home) === 0 ? state.path.slice(state.home.length) : state.path;
    var parts = rel.split('/').filter(Boolean);
    var acc = state.home;
    function crumb(label, p) {
      var a = document.createElement('a');
      a.textContent = label;
      a.addEventListener('click', function () { go(p); });
      pathEl.appendChild(a);
    }
    crumb('Thư mục nhà', state.home);
    parts.forEach(function (name) {
      acc += '/' + name;
      var sep = document.createElement('i'); sep.textContent = '›'; pathEl.appendChild(sep);
      crumb(name, acc);
    });
    pathEl.scrollLeft = pathEl.scrollWidth;
  }

  // ---------- Danh sách file ----------
  function go(path, noHistory) {
    if (!closePreview()) return;
    status('Đang mở...');
    return anh7.call('files.list', { path: path, hidden: state.hidden }).then(function (r) {
      if (!noHistory && state.path && state.path !== r.path) state.history.push(state.path);
      state.path = r.path; state.home = r.home; state.parent = r.parent;
      state.items = r.items.sort(function (a, b) {
        if (a.dir !== b.dir) return a.dir ? -1 : 1;
        return a.name.localeCompare(b.name, 'vi', { numeric: true, sensitivity: 'base' });
      });
      state.sel = null;
      renderPath(); markSide(); renderList();
      $('.b-up').disabled = !r.parent;
      $('.b-back').disabled = !state.history.length;
      w.setTitle('Tệp Mac — ' + (r.path === r.home ? 'Thư mục nhà' : r.path.split('/').pop()));
      status(state.items.length + ' mục');
    }).catch(function (e) { status(''); fail(e); });
  }

  function renderList() {
    listEl.innerHTML = '<div class="mf-row head"><span></span><span>Tên</span><span>Ngày sửa</span><span class="r">Kích thước</span></div>';
    if (!state.items.length) {
      listEl.insertAdjacentHTML('beforeend', '<div class="mf-empty">Thư mục trống</div>');
      return;
    }
    state.items.forEach(function (it, i) {
      var row = document.createElement('div');
      row.className = 'mf-row';
      row.dataset.i = i;
      row.innerHTML = '<img alt=""><span></span><span></span><span class="r"></span>';
      row.children[1].textContent = it.name;
      row.children[2].textContent = date(it.mtime);
      row.children[3].textContent = it.dir ? '' : size(it.size);
      row.addEventListener('click', function () { select(i); });
      row.addEventListener('dblclick', function () { openItem(it); });
      row.addEventListener('contextmenu', function (e) { e.preventDefault(); e.stopPropagation(); select(i); showMenu(e, it); });
      listEl.appendChild(row);
      if (i < 400) loadIcon(it, row.children[0]);
    });
  }

  function loadIcon(it, img) {
    anh7.call('files.icon', { path: it.path }).then(function (b64) {
      if (b64) img.src = 'data:image/png;base64,' + b64;
    }).catch(function () {});
  }

  function select(i) {
    state.sel = i;
    listEl.querySelectorAll('.mf-row.sel').forEach(function (r) { r.classList.remove('sel'); });
    var row = listEl.querySelector('.mf-row[data-i="' + i + '"]');
    if (row) row.classList.add('sel');
    var it = state.items[i];
    if (it) status(it.path + (it.dir ? '' : ' · ' + size(it.size)));
  }

  // ---------- Mở file / xem trước ----------
  function openItem(it) {
    if (it.dir) { go(it.path); return; }
    var k = kind(it.ext);
    if (it.ext === 'app') { anh7.call('files.open', { path: it.path }).catch(fail); return; }
    showPreview(it, k);
  }

  function showPreview(it, k) {
    state.editing = null; state.dirty = false;
    $('.mf-prev .ph b').textContent = it.name;
    $('.p-save').hidden = true;
    prevBody.innerHTML = '';
    prev.dataset.path = it.path;
    var url = anh7.fileURL(it.path);
    if (k === 'image') {
      prevBody.innerHTML = '<img alt="">'; prevBody.firstChild.src = url;
    } else if (k === 'video' || k === 'audio') {
      var v = document.createElement(k === 'video' ? 'video' : 'audio');
      v.controls = true; v.autoplay = true; v.src = url;
      prevBody.appendChild(v);
    } else if (k === 'pdf') {
      prevBody.innerHTML = '<iframe></iframe>'; prevBody.firstChild.src = url;
    } else if (k === 'text' || (it.size <= 64 * 1024 && !it.ext)) {
      prevBody.innerHTML = '<div class="other">Đang đọc...</div>';
      anh7.call('files.readText', { path: it.path }).then(function (text) {
        prevBody.innerHTML = '<textarea spellcheck="false"></textarea>';
        var ta = prevBody.firstChild;
        ta.value = text;
        state.editing = it;
        $('.p-save').hidden = false;
        ta.addEventListener('input', function () { state.dirty = true; $('.p-save').textContent = 'Lưu *'; });
        ta.addEventListener('keydown', function (e) {
          if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 's') { e.preventDefault(); save(); }
        });
        ta.focus();
      }).catch(function (e) { otherPreview(it, e.message); });
    } else {
      otherPreview(it, 'Win12 không xem trực tiếp được loại file này.');
    }
    prev.classList.add('show');
  }

  function otherPreview(it, note) {
    prevBody.innerHTML = '<div class="other"><img alt=""><div></div><br>' +
      '<button type="button" class="anh7-btn pri">Mở bằng app Mac</button> ' +
      '<button type="button" class="anh7-btn try">Thử mở dạng văn bản</button></div>';
    loadIcon(it, prevBody.querySelector('img'));
    prevBody.querySelector('.other div').textContent = note + ' (' + size(it.size) + ')';
    prevBody.querySelector('.pri').addEventListener('click', function () { anh7.call('files.open', { path: it.path }).catch(fail); });
    prevBody.querySelector('.try').addEventListener('click', function () { showPreview(it, 'text'); });
  }

  function save() {
    var it = state.editing;
    if (!it) return;
    var text = prevBody.querySelector('textarea').value;
    anh7.call('files.writeText', { path: it.path, text: text }).then(function () {
      state.dirty = false;
      $('.p-save').textContent = 'Lưu';
      status('Đã lưu ' + it.name);
    }).catch(fail);
  }

  // Đóng xem trước; hỏi nếu còn thay đổi chưa lưu. Trả về false nếu người dùng hủy.
  function closePreview() {
    if (!prev.classList.contains('show')) return true;
    if (state.dirty && !confirm('File có thay đổi chưa lưu. Bỏ thay đổi?')) return false;
    prev.classList.remove('show');
    prevBody.innerHTML = '';  // dừng video/âm thanh
    state.editing = null; state.dirty = false;
    return true;
  }

  // ---------- Thao tác ----------
  function newFolder() {
    var name = prompt('Tên thư mục mới:', 'Thư mục mới');
    if (!name) return;
    anh7.call('files.mkdir', { path: state.path, name: name }).then(function () { go(state.path, true); }).catch(fail);
  }
  function newText() {
    var name = prompt('Tên tệp văn bản mới:', 'Văn bản mới.txt');
    if (!name) return;
    anh7.call('files.newText', { path: state.path, name: name }).then(function (p) {
      return go(state.path, true).then(function () {
        showPreview({ name: name, path: p, ext: 'txt', size: 0 }, 'text');
      });
    }).catch(fail);
  }
  function rename(it) {
    var name = prompt('Đổi tên "' + it.name + '" thành:', it.name);
    if (!name || name === it.name) return;
    anh7.call('files.rename', { path: it.path, name: name }).then(function () { go(state.path, true); }).catch(fail);
  }
  function trash(it) {
    if (!confirm('Đưa "' + it.name + '" vào Thùng rác của Mac?\n(Khôi phục được từ Thùng rác)')) return;
    anh7.call('files.trash', { path: it.path }).then(function () { go(state.path, true); status('Đã đưa vào Thùng rác'); }).catch(fail);
  }
  function copyPath(it) {
    var done = function () { status('Đã chép đường dẫn: ' + it.path); };
    if (navigator.clipboard) navigator.clipboard.writeText(it.path).then(done, function () { prompt('Đường dẫn:', it.path); });
    else prompt('Đường dẫn:', it.path);
  }

  // ---------- Menu chuột phải ----------
  function showMenu(e, it) {
    menu.innerHTML = '';
    function add(label, fn, cls) {
      var a = document.createElement('a');
      a.textContent = label;
      if (cls) a.className = cls;
      a.addEventListener('click', function () { hideMenu(); fn(); });
      menu.appendChild(a);
    }
    function sep() { menu.appendChild(document.createElement('hr')); }
    if (it) {
      add(it.dir ? 'Mở thư mục' : 'Mở / xem trong Win12', function () { openItem(it); });
      add('Mở bằng app Mac', function () { anh7.call('files.open', { path: it.path }).catch(fail); });
      add('Hiện trong Finder', function () { anh7.call('files.reveal', { path: it.path }).catch(fail); });
      sep();
      add('Đổi tên...', function () { rename(it); });
      add('Sao chép đường dẫn', function () { copyPath(it); });
      sep();
      add('Đưa vào Thùng rác', function () { trash(it); }, 'dan');
    } else {
      add('Thư mục mới...', newFolder);
      add('Tệp văn bản mới...', newText);
      sep();
      add('Làm mới', function () { go(state.path, true); });
      add('Mở thư mục này trong Finder', function () { anh7.call('files.open', { path: state.path }).catch(fail); });
    }
    menu.style.display = 'block';
    var x = Math.min(e.clientX, innerWidth - menu.offsetWidth - 8);
    var y = Math.min(e.clientY, innerHeight - menu.offsetHeight - 8);
    menu.style.left = x + 'px'; menu.style.top = y + 'px';
  }
  function hideMenu() { menu.style.display = 'none'; }
  document.addEventListener('mousedown', function (e) { if (!menu.contains(e.target)) hideMenu(); }, true);
  listEl.addEventListener('contextmenu', function (e) { e.preventDefault(); showMenu(e, null); });

  // ---------- Nút & phím ----------
  $('.b-back').addEventListener('click', function () { if (state.history.length) go(state.history.pop(), true); });
  $('.b-up').addEventListener('click', function () { if (state.parent) go(state.parent); });
  $('.b-newdir').addEventListener('click', newFolder);
  $('.b-newtxt').addEventListener('click', newText);
  $('.b-reload').addEventListener('click', function () { go(state.path, true); });
  $('.b-hidden').addEventListener('click', function () {
    state.hidden = !state.hidden;
    $('.b-hidden').classList.toggle('pri', state.hidden);
    go(state.path, true);
  });
  $('.p-back').addEventListener('click', closePreview);
  $('.p-save').addEventListener('click', save);
  $('.p-open').addEventListener('click', function () { anh7.call('files.open', { path: prev.dataset.path }).catch(fail); });
  $('.p-reveal').addEventListener('click', function () { anh7.call('files.reveal', { path: prev.dataset.path }).catch(fail); });

  w.el.addEventListener('keydown', function (e) {
    if (e.target.tagName === 'TEXTAREA' || e.target.tagName === 'INPUT') return;
    var it = state.items[state.sel];
    if (prev.classList.contains('show')) { if (e.key === 'Escape') closePreview(); return; }
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      var n = state.sel == null ? 0 : state.sel + (e.key === 'ArrowDown' ? 1 : -1);
      if (n >= 0 && n < state.items.length) {
        select(n);
        var row = listEl.querySelector('.mf-row[data-i="' + n + '"]');
        if (row) row.scrollIntoView({ block: 'nearest' });
      }
    } else if (e.key === 'Enter' && it) openItem(it);
    else if (e.key === 'Backspace' && (e.metaKey || e.ctrlKey) && it) trash(it);
    else if (e.key === 'Backspace' && state.parent) go(state.parent);
    else if (e.key === 'F2' && it) rename(it);
  });
  w.el.tabIndex = -1;

  function init() {
    if (!anh7.available) {
      listEl.innerHTML = '<div class="mf-empty">Chỉ dùng được khi chạy trong app Anh 7.</div>';
      return;
    }
    loadPlaces();
    anh7.call('files.places').then(function (p) { go(p[0].path, true); }).catch(fail);
  }

  // ---------- Nút thanh tác vụ + thay Trình quản lý tệp Win12 ----------
  var btn = document.createElement('button');
  btn.type = 'button'; btn.className = 'dock-btn'; btn.id = 'macfiles-btn';
  btn.setAttribute('aria-label', 'Tệp Mac');
  btn.setAttribute('win12_title', 'Tệp Mac (Ctrl+Shift+F)');
  btn.innerHTML = ICON;
  btn.addEventListener('click', function (e) { e.stopPropagation(); w.toggle(); w.el.focus(); });
  anh7.addDockButton(btn, ['vmwin-btn', 'macapps-btn', 'search-btn']);

  document.addEventListener('keydown', function (e) {
    if (e.ctrlKey && e.shiftKey && (e.key === 'F' || e.key === 'f')) { e.preventDefault(); w.toggle(); w.el.focus(); }
  });

  window.anh7.openFiles = function (path) { w.show(); if (path) go(path); else if (!state.path) init(); };

  // Mặc định: mở "Trình quản lý tệp" / "PC này" của Win12 sẽ mở Tệp Mac
  // (tắt được trong Cài đặt > Máy Mac > "Dùng Tệp Mac thay Trình quản lý tệp Win12")
  function hookExplorer() {
    if (typeof window.openapp !== 'function' || window.openapp.__anh7) return;
    var original = window.openapp;
    window.openapp = function (name) {
      var replace = true;
      try { replace = localStorage.getItem('anh7.replaceExplorer') !== '0'; } catch (e) {}
      if (name === 'explorer' && replace && anh7.available) { window.anh7.openFiles(); return; }
      return original.apply(this, arguments);
    };
    window.openapp.__anh7 = true;
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', hookExplorer);
  else hookExplorer();
  setTimeout(hookExplorer, 3000);
})();
