/* =========================================================
   Thay dữ liệu giả của Win12 bằng dữ liệu thật của máy Mac
   - "Administrator" -> tên người dùng Mac (hoặc tên tự đặt trong Cài đặt > Máy Mac)
   - "Desktop-PingGai", "Blueteeth-PingGai" -> tên máy Mac
   - "PingGai - 5G" -> tên Wi-Fi thật (nếu macOS cho biết)
   - email giả -> tên tài khoản @ tên máy
   - Ảnh đại diện & hình nền Win12 tự chọn (lưu trong cài đặt Win12, đi theo bản di động)
   ========================================================= */
(function () {
  'use strict';
  var host = window.__anh7Host;
  if (!host) return;   // không chạy trong app Anh 7 -> giữ nguyên Win12 gốc

  function get(key) { try { return localStorage.getItem(key); } catch (e) { return null; } }

  function displayName() { return get('anh7.userName') || host.fullName || host.userName; }
  var account = (host.userName + '@' + (host.computerName || 'mac')).toLowerCase().replace(/\s+/g, '-');
  var subtitle = (host.model ? host.model + ' · ' : '') + (host.macOS || 'macOS');
  var ssid = null;

  // Chuỗi gốc (đã qua lớp dịch) -> giá trị thật; chỉ thay khi cả đoạn chữ trùng khớp
  function map() {
    var m = {
      'Administrator': displayName(),
      'Desktop-PingGai': host.computerName,
      'Blueteeth-PingGai': host.computerName,
      'starry-source@windows12.com': account,
      'starry-source@Win12.tech': account,
      'Nắp chai': subtitle,
      '瓶盖': subtitle
    };
    m['PingGai - 5G'] = ssid || 'Wi-Fi';
    return m;
  }

  var current = map();
  var wifiNodes = [];   // chỗ đã thay tên Wi-Fi, để cập nhật khi biết tên thật
  function fixText(node) {
    var t = node.nodeValue;
    if (!t) return;
    var key = t.trim();
    if (Object.prototype.hasOwnProperty.call(current, key) && current[key] && key !== current[key]) {
      // Dòng "Nắp chai" chỉ thay ở trang Cài đặt (tránh đổi tên file đề xuất trong menu Start)
      if ((key === 'Nắp chai' || key === '瓶盖') && !(node.parentElement && node.parentElement.closest('#win-setting'))) return;
      node.nodeValue = t.replace(key, current[key]);
      if (key === 'PingGai - 5G') wifiNodes.push(node);
    }
  }
  // Tên trong thanh bên Cài đặt do file dịch đặt (data-i18n="setting.usrname")
  function fixI18nName() {
    document.querySelectorAll('[data-i18n="setting.usrname"]').forEach(function (el) {
      if (el.textContent !== displayName()) el.textContent = displayName();
    });
  }

  function walk(root) {
    if (!root) return;
    if (root.nodeType === 3) { fixText(root); return; }
    if (root.nodeType !== 1 || root.closest('textarea,input,[contenteditable="true"],#bios')) return;
    var tw = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    var n;
    while ((n = tw.nextNode())) fixText(n);
  }

  // ---------- Ảnh đại diện ----------
  // Áp lên mọi biểu tượng người dùng của Win12 (đăng nhập, Start, Cài đặt, Tài khoản)
  function avatarURL() {
    var rel = get('anh7.avatar');
    return rel && window.anh7 ? window.anh7.fileURL(host.dataPath + '/' + rel) : '';
  }
  var avatarSeq = 0;
  function applyAvatar() {
    var url = avatarURL();
    document.querySelectorAll('svg').forEach(function (svg) {
      var isUser = svg.querySelector('linearGradient[id^="user-fill"]') || svg.dataset.anh7Avatar;
      if (!isUser) return;
      if (!svg.dataset.anh7Orig) {
        svg.dataset.anh7Orig = svg.innerHTML;
        svg.dataset.anh7View = svg.getAttribute('viewBox') || '';
        svg.dataset.anh7Avatar = '1';
      }
      if (url) {
        var id = 'anh7-av-' + (++avatarSeq);
        svg.setAttribute('viewBox', '0 0 100 100');
        svg.innerHTML = '<defs><clipPath id="' + id + '"><circle cx="50" cy="50" r="50"/></clipPath></defs>' +
          '<image width="100" height="100" preserveAspectRatio="xMidYMid slice" clip-path="url(#' + id + ')"/>';
        svg.querySelector('image').setAttribute('href', url);
      } else {
        svg.setAttribute('viewBox', svg.dataset.anh7View);
        svg.innerHTML = svg.dataset.anh7Orig;
      }
    });
    var login = document.querySelector('#loginback > .user');
    if (login) {
      login.style.backgroundImage = url ? 'url("' + url + '")' : '';
      login.style.backgroundSize = url ? 'cover' : '';
      login.style.backgroundPosition = url ? 'center' : '';
      login.style.borderRadius = url ? '50%' : '';
    }
  }

  // ---------- Hình nền Win12 ----------
  function applyWallpaper() {
    var rel = get('anh7.wallpaper');
    if (rel && window.anh7) {
      document.documentElement.style.setProperty('--bgul', 'url("' + window.anh7.fileURL(host.dataPath + '/' + rel) + '")');
    } else {
      document.documentElement.style.removeProperty('--bgul');
    }
  }

  // ---------- Chạy ----------
  function refreshAll() {
    current = map();
    walk(document.body);
    fixI18nName();
    applyAvatar();
    applyWallpaper();
  }
  window.anh7RealData = { refresh: refreshAll, displayName: displayName };

  function start() {
    refreshAll();
    var pending = false;
    new MutationObserver(function (list) {
      for (var i = 0; i < list.length; i++) {
        var m = list[i];
        if (m.type === 'characterData') fixText(m.target);
        else for (var j = 0; j < m.addedNodes.length; j++) walk(m.addedNodes[j]);
      }
      // Gom nhiều thay đổi thành 1 lần sửa tên/ảnh đại diện
      if (!pending) {
        pending = true;
        setTimeout(function () { pending = false; fixI18nName(); if (get('anh7.avatar')) applyAvatar(); }, 300);
      }
    }).observe(document.body, { childList: true, subtree: true, characterData: true });

    // Tên Wi-Fi thật (nếu macOS cho biết)
    if (window.anh7 && window.anh7.available) {
      window.anh7.call('sys.info').then(function (i) {
        if (i.wifi && i.wifi.ssid) {
          ssid = i.wifi.ssid; current = map();
          wifiNodes.forEach(function (n) { if (n.isConnected) n.nodeValue = n.nodeValue.replace(/\S.*\S|\S/, ssid); });
          walk(document.body);
        } else if (i.wifi && !i.wifi.on) {
          wifiNodes.forEach(function (n) { if (n.isConnected) n.nodeValue = n.nodeValue.replace(/\S.*\S|\S/, 'Wi-Fi đang tắt'); });
        }
      }).catch(function () {});
    }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
  setTimeout(refreshAll, 3000); // sau khi file dịch Win12 nạp xong
})();
