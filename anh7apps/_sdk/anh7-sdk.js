/* =========================================================
   Anh 7 SDK — thư viện cho app chạy trong Anh 7
   Nạp: <script src="anh7app://_sdk/anh7-sdk.js"></script>

   Anh7.storage.get()            -> Promise<object>   dữ liệu đã lưu của app
   Anh7.storage.set(obj)         -> Promise            lưu đè toàn bộ dữ liệu
   Anh7.notify(tieuDe, noiDung)  -> Promise            (cần quyền "notify")
   Anh7.setTitle(chu)            -> Promise            đổi tiêu đề cửa sổ
   Anh7.close()                                        đóng app
   Anh7.info()                   -> Promise<{id,name,version,dark}>
   Anh7.system()                 -> Promise<thông tin máy>  (cần quyền "system")
   Anh7.call(lenh, thamSo)       -> Promise            gọi lệnh khác (vd "files.list", cần quyền "files")
   Anh7.onTheme(function (dark) {...})                 Win12 đổi sáng/tối
   Anh7.available                                      true nếu đang chạy trong Anh 7
   ========================================================= */
(function () {
  'use strict';
  var pending = {}, nextId = 1, themeCbs = [];
  var inAnh7 = window.parent && window.parent !== window;

  function applyTheme(dark) {
    document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light');
    themeCbs.forEach(function (cb) { try { cb(dark); } catch (e) {} });
  }

  window.addEventListener('message', function (e) {
    if (e.source !== window.parent) return;
    var d = e.data;
    if (!d || d.anh7 !== 1) return;
    if (d.event === 'theme') { applyTheme(!!d.dark); return; }
    var p = pending[d.id];
    if (!p) return;
    delete pending[d.id];
    if (d.error) p.reject(new Error(d.error)); else p.resolve(d.result);
  });

  function call(op, args) {
    return new Promise(function (resolve, reject) {
      if (!inAnh7) { reject(new Error('App này cần chạy trong Anh 7.')); return; }
      var id = nextId++;
      pending[id] = { resolve: resolve, reject: reject };
      window.parent.postMessage({ anh7: 1, id: id, op: op, args: args || {} }, '*');
      setTimeout(function () {
        if (pending[id]) { delete pending[id]; reject(new Error('Anh 7 không phản hồi.')); }
      }, 30000);
    });
  }

  // Ngoài Anh 7 (mở thử bằng trình duyệt): lưu tạm vào localStorage để vẫn chạy được
  var fallbackKey = 'anh7-sdk-data';
  var storage = inAnh7 ? {
    get: function () { return call('storage.get'); },
    set: function (data) { return call('storage.set', { data: data }); }
  } : {
    get: function () { try { return Promise.resolve(JSON.parse(localStorage.getItem(fallbackKey) || '{}')); } catch (e) { return Promise.resolve({}); } },
    set: function (data) { try { localStorage.setItem(fallbackKey, JSON.stringify(data)); } catch (e) {} return Promise.resolve(true); }
  };

  window.Anh7 = {
    available: inAnh7,
    call: call,
    storage: storage,
    notify: function (title, text) { return call('ui.notify', { title: title, text: text }); },
    setTitle: function (t) { return call('ui.setTitle', { title: t }); },
    close: function () { return call('ui.close'); },
    info: function () { return call('app.info'); },
    system: function () { return call('sys.info'); },
    onTheme: function (cb) { themeCbs.push(cb); },
    // Lưu có độ trễ: gọi nhiều lần liên tục chỉ ghi 1 lần (dùng khi gõ phím)
    saveLater: (function () {
      var timer = null, last = null;
      return function (data, ms) {
        last = data;
        clearTimeout(timer);
        timer = setTimeout(function () { storage.set(last); }, ms || 400);
      };
    })()
  };

  if (window.matchMedia && !inAnh7) applyTheme(window.matchMedia('(prefers-color-scheme: dark)').matches);
})();
