import Cocoa
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var webView: WKWebView!

    // Số bản sao lưu theo ngày được giữ lại (cũ hơn sẽ tự xóa)
    let backupKeepCount = 30

    // Trang mở đầu tiên: thử lần lượt, file nào có trong app thì dùng file đó
    // (Win12 dùng desktop.html; giao diện cũ dùng index.html)
    let entryCandidates = ["desktop", "index"]

    // =====================================================
    // VỊ TRÍ LƯU DỮ LIỆU
    // ~/Library/Application Support/MyApp/data.json
    // ~/Library/Application Support/MyApp/backups/data-YYYY-MM-DD.json
    // =====================================================
    // Bản di động: "Anh 7 Data" cạnh app; bản thường: Application Support/MyApp
    lazy var dataDir: URL = AppPaths.base

    lazy var backupDir: URL = {
        let dir = dataDir.appendingPathComponent("backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    var dataFile: URL {
        return dataDir.appendingPathComponent("data.json")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Tạo thanh menu: có menu này thì Cmd+C, Cmd+V, Cmd+A, Cmd+Z, Cmd+Q mới hoạt động
        buildMenu()

        // Cầu nối giữa giao diện HTML và Swift
        let controller = WKUserContentController()
        controller.add(self, name: "store")

        // Đưa dữ liệu đã lưu vào trang web TRƯỚC khi script của trang chạy
        let script = WKUserScript(
            source: "window.__NATIVE__ = { path: \(jsonString(dataFile.path)), data: \(loadDataJSON()) };",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true)
        controller.addUserScript(script)

        // Cài đặt của Win12 (ngôn ngữ, biểu tượng desktop, màu...) nằm trong localStorage.
        // - Luôn chụp lại mỗi 5 giây -> Anh 7 Data/webstate.json (để xuất bản di động mang theo)
        // - Bản di động: nạp lại từ file TRƯỚC khi Win12 chạy (máy mới vẫn giữ nguyên cài đặt)
        let webState = AppPaths.isPortable ? loadWebStateJSON() : "null"
        let stateScript = WKUserScript(source: """
            (function () {
              var saved = \(webState);
              if (saved && typeof saved === 'object') {
                try { for (var k in saved) localStorage.setItem(k, saved[k]); } catch (e) {}
              }
              var last = '';
              function snap() {
                try {
                  var o = {};
                  for (var i = 0; i < localStorage.length; i++) {
                    var key = localStorage.key(i); o[key] = localStorage.getItem(key);
                  }
                  var s = JSON.stringify(o);
                  if (s !== last) {
                    last = s;
                    window.webkit.messageHandlers.store.postMessage({ action: 'saveWebState', data: s });
                  }
                } catch (e) {}
              }
              setInterval(snap, 5000);
              window.addEventListener('pagehide', snap);
            })();
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        controller.addUserScript(stateScript)

        // Thông tin thật (tên người dùng, tên máy...) + pin thật cho Win12.
        // WebKit không có navigator.getBattery -> tự tạo, lấy số liệu từ Swift mỗi 30 giây.
        let hostJSON = (try? JSONSerialization.data(withJSONObject: host.hostInfo()))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let earlyScript = WKUserScript(source: """
            window.__anh7Host = \(hostJSON);
            (function () {
              if (navigator.getBattery) return;
              var bat = { level: 1, charging: true, chargingTime: 0, dischargingTime: Infinity, _l: {} };
              bat.addEventListener = function (t, fn) { (bat._l[t] = bat._l[t] || []).push(fn); };
              bat.removeEventListener = function (t, fn) { bat._l[t] = (bat._l[t] || []).filter(function (f) { return f !== fn; }); };
              function fire(t) {
                (bat._l[t] || []).forEach(function (fn) { try { fn({ type: t, target: bat }); } catch (e) {} });
                if (typeof bat['on' + t] === 'function') bat['on' + t]({ type: t, target: bat });
              }
              var ready, readyPromise = new Promise(function (r) { ready = r; });
              window.__anh7Battery = function (b) {
                if (b && b.available) {
                  var lv = Math.max(0, Math.min(1, b.percent / 100)), ch = !!(b.charging || b.plugged);
                  var lvChanged = lv !== bat.level, chChanged = ch !== bat.charging;
                  bat.level = lv; bat.charging = ch;
                  if (lvChanged) fire('levelchange');
                  if (chChanged) fire('chargingchange');
                }
                ready(bat);
              };
              function ask() { try { window.webkit.messageHandlers.store.postMessage({ action: 'battery' }); } catch (e) {} }
              ask(); setInterval(ask, 30000);
              setTimeout(function () { ready(bat); }, 1500);
              navigator.getBattery = function () { return readyPromise; };
            })();
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        controller.addUserScript(earlyScript)

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        // Win12 xem file thật qua đường dẫn anh7file:///Users/... (chỉ trong thư mục nhà)
        config.setURLSchemeHandler(host, forURLScheme: "anh7file")
        // App Anh 7 (app web tự cài) chạy từ anh7app://<mã app>/index.html
        config.setURLSchemeHandler(host, forURLScheme: "anh7app")

        // Cho phép trang chạy từ file trong app đọc các file khác cùng thư mục
        // (Win12 tải ảnh, ngôn ngữ, dữ liệu app bằng JavaScript; thiếu dòng này các phần đó sẽ trống)
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        // Cho phép video/âm thanh tự phát (âm thanh khởi động, trình phát nhạc...)
        config.mediaTypesRequiringUserActionForPlayback = []

        // Cửa sổ lớn, tiêu đề trong suốt để giao diện desktop phủ kín cửa sổ
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 880),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Anh 7"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 1000, height: 650)
        // Nút xanh lá / Ctrl+Cmd+F để vào toàn màn hình
        window.collectionBehavior = [.fullScreenPrimary]

        webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.uiDelegate = self
        webView.navigationDelegate = self
        // Cho phép bấm chuột phải > Kiểm tra phần tử (Safari > Develop) để gỡ lỗi
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        loadEntryPage()

        window.contentView!.addSubview(webView)

        // Màn hình máy ảo nằm đè lên trang web, đúng vị trí cửa sổ "Máy ảo macOS" của Win12
        window.contentView!.addSubview(vm.vmView, positioned: .above, relativeTo: webView)
        vm.onState = { [weak self] state, progress, message in
            guard let self = self else { return }
            let payload: [String: Any] = ["state": state, "progress": progress, "message": message]
            if let data = try? JSONSerialization.data(withJSONObject: payload),
               let json = String(data: data, encoding: .utf8) {
                self.webView.evaluateJavaScript("window.__vmState && window.__vmState(\(json));", completionHandler: nil)
            }
            // Máy ảo không chạy thì ẩn màn hình máy ảo
            if state != "running" && state != "starting" && state != "stopping" {
                self.vm.vmView.isHidden = true
            }
        }

        window.center()
        window.makeKeyAndOrderFront(nil)

        // Cài đặt khởi động (đặt trong Cài đặt Win12 > Máy Mac)
        let startup = host.loadSettings()
        if startup["startFullscreen"] as? Bool == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.window.toggleFullScreen(nil) }
        }
        if startup["autoStartVM"] as? Bool == true && vm.isInstalled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.vm.start() }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // Tìm trang mở đầu trong Contents/Resources và nạp vào
    func loadEntryPage() {
        for name in entryCandidates {
            if let url = Bundle.main.url(forResource: name, withExtension: "html") {
                webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
                return
            }
        }
        webView.loadHTMLString("<h2 style='font-family:-apple-system;padding:40px'>Không tìm thấy desktop.html hoặc index.html trong app.</h2>", baseURL: nil)
    }

    // Đóng cửa sổ cuối cùng thì thoát app
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // =====================================================
    // MÁY ẢO
    // =====================================================
    let vm = VMManager()
    let host = HostBridge()

    // Trang Win12 nạp xong: bỏ qua màn hình đăng nhập nếu đã bật trong cài đặt
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if host.loadSettings()["skipLogin"] as? Bool == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                webView.evaluateJavaScript("if (typeof win12FinishLogin === 'function') win12FinishLogin();", completionHandler: nil)
            }
        }
    }

    // Trả kết quả lệnh "host" về cho JavaScript: window.__hostReply(id, ketQua, loi)
    func replyHost(_ id: Any, result: Any?, error: String?) {
        func js(_ v: Any?) -> String {
            guard let v = v, let d = try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed]),
                  let s = String(data: d, encoding: .utf8) else { return "null" }
            return s
        }
        webView.evaluateJavaScript("window.__hostReply && window.__hostReply(\(js(id)), \(js(result)), \(js(error)));",
                                   completionHandler: nil)
    }

    // Thoát app khi máy ảo đang chạy: lưu trạng thái để lần sau mở lại đúng chỗ
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard vm.isRunning else { return .terminateNow }

        vm.saveForQuit { ok in
            if ok {
                NSApp.reply(toApplicationShouldTerminate: true)
                return
            }
            // Không lưu được (macOS cũ hơn 14): hỏi trước khi tắt ngang máy ảo
            let alert = NSAlert()
            alert.messageText = "Máy ảo đang chạy"
            alert.informativeText = "Thoát bây giờ sẽ tắt ngang máy ảo (như rút điện), dữ liệu chưa lưu bên trong có thể mất. Nên tắt máy từ menu bên trong máy ảo trước."
            alert.addButton(withTitle: "Hủy")
            alert.addButton(withTitle: "Vẫn thoát")
            let quit = alert.runModal() == .alertSecondButtonReturn
            if quit {
                self.vm.forceStop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    NSApp.reply(toApplicationShouldTerminate: true)
                }
            } else {
                NSApp.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }

    // =====================================================
    // XUẤT BẢN DI ĐỘNG
    // Tạo thư mục "Anh 7" ở nơi chọn (USB...), gồm:
    //   Anh 7.app + Anh 7 Data/ (máy ảo, ghi chú, thư mục chia sẻ)
    // Mở "Anh 7.app" trong thư mục đó ở máy nào cũng dùng đúng dữ liệu đi kèm.
    // =====================================================
    @objc func exportPortable(_ sender: Any?) {
        let busy = ["running", "starting", "stopping", "saving", "downloading", "installing"]
        if vm.isRunning || busy.contains(vm.state) {
            showInfo("Hãy tắt máy ảo trước",
                     "Bấm \"Tắt máy\" trong cửa sổ Máy ảo macOS, đợi tắt hẳn rồi xuất lại. Đang tải/cài thì đợi xong.")
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Xuất vào đây"
        panel.message = "Chọn nơi lưu bản di động (ví dụ ổ USB). App sẽ tạo thư mục \"Anh 7\" tại đó."
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let target = panel.url else { return }
            self.runExport(to: target)
        }
    }

    func runExport(to target: URL) {
        let fm = FileManager.default
        let dest = target.appendingPathComponent("Anh 7", isDirectory: true)
        if fm.fileExists(atPath: dest.path) {
            showInfo("Đã có thư mục \"Anh 7\" ở đó", "Chọn nơi khác, hoặc xóa/đổi tên thư mục cũ rồi xuất lại.")
            return
        }

        // Ước tính dung lượng cần (theo phần dữ liệu thật) và kiểm tra chỗ trống
        let need = allocatedSize(of: Bundle.main.bundleURL) + allocatedSize(of: AppPaths.base)
        let values = try? target.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeLocalizedFormatDescriptionKey])
        let free = Int64(values?.volumeAvailableCapacity ?? 0)
        if free > 0 && free < need + 500_000_000 {
            showInfo("Không đủ chỗ trống",
                     "Cần khoảng \(gb(need)), nơi chọn chỉ còn \(gb(free)).")
            return
        }

        // USB không phải APFS: ổ máy ảo sẽ chiếm đủ 64 GB -> hỏi trước
        let format = values?.volumeLocalizedFormatDescription ?? ""
        if !format.contains("APFS") && fm.fileExists(atPath: AppPaths.base.appendingPathComponent("VM/Disk.img").path) {
            let alert = NSAlert()
            alert.messageText = "Ổ đích không phải APFS (\(format))"
            alert.informativeText = "Ổ máy ảo sẽ chiếm đủ 64 GB và chép rất lâu. Nên định dạng USB sang APFS bằng Tiện ích Ổ đĩa trước. Vẫn tiếp tục?"
            alert.addButton(withTitle: "Hủy")
            alert.addButton(withTitle: "Vẫn tiếp tục")
            if alert.runModal() != .alertSecondButtonReturn { return }
        }

        // Bảng "Đang chép..." trong lúc làm
        let sheet = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 110),
                            styleMask: [.titled], backing: .buffered, defer: false)
        let label = NSTextField(labelWithString: "Đang tạo bản di động (khoảng \(gb(need)))...\nĐừng rút USB hay tắt app.")
        label.frame = NSRect(x: 20, y: 50, width: 340, height: 40)
        let spinner = NSProgressIndicator(frame: NSRect(x: 20, y: 20, width: 340, height: 20))
        spinner.isIndeterminate = true
        spinner.startAnimation(nil)
        sheet.contentView?.addSubview(label)
        sheet.contentView?.addSubview(spinner)
        window.beginSheet(sheet)

        DispatchQueue.global(qos: .userInitiated).async {
            var failure: String?
            do {
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)
                try fm.copyItem(at: Bundle.main.bundleURL, to: dest.appendingPathComponent("Anh 7.app"))
                try self.copyTreeSparse(from: AppPaths.base,
                                        to: dest.appendingPathComponent(AppPaths.portableFolderName, isDirectory: true))
            } catch {
                failure = error.localizedDescription
            }
            DispatchQueue.main.async {
                self.window.endSheet(sheet)
                if let failure = failure {
                    self.showInfo("Xuất thất bại", failure + "\nThư mục dở dang: " + dest.path)
                } else {
                    let alert = NSAlert()
                    alert.messageText = "Đã tạo bản di động"
                    alert.informativeText = "Chép nguyên thư mục \"Anh 7\" sang máy khác (chip Apple), mở \"Anh 7.app\" bên trong là dùng được, kèm máy ảo và dữ liệu."
                    alert.addButton(withTitle: "Mở thư mục")
                    alert.addButton(withTitle: "Xong")
                    if alert.runModal() == .alertFirstButtonReturn {
                        NSWorkspace.shared.activateFileViewerSelecting([dest])
                    }
                }
            }
        }
    }

    // Chép cả thư mục; file lớn (ổ máy ảo) chép kiểu "thưa": chỉ chép phần có dữ liệu
    func copyTreeSparse(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        let items = try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])
        for item in items {
            let target = dst.appendingPathComponent(item.lastPathComponent)
            let rv = try item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if rv.isDirectory == true {
                try copyTreeSparse(from: item, to: target)
            } else if (rv.fileSize ?? 0) > 256 * 1024 * 1024 {
                try sparseCopy(from: item, to: target)
            } else {
                try fm.copyItem(at: item, to: target)
            }
        }
    }

    // Dò từng vùng có dữ liệu (SEEK_DATA / SEEK_HOLE), chỉ chép các vùng đó;
    // phần trống giữ nguyên là "lỗ" nên file đích không chiếm thêm chỗ
    func sparseCopy(from src: URL, to dst: URL) throws {
        let inFd = open(src.path, O_RDONLY)
        guard inFd >= 0 else { throw posixError("Không đọc được \(src.lastPathComponent)") }
        defer { close(inFd) }
        let outFd = open(dst.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard outFd >= 0 else { throw posixError("Không ghi được \(dst.lastPathComponent)") }
        defer { close(outFd) }

        var st = stat()
        guard fstat(inFd, &st) == 0 else { throw posixError("Không đọc được kích thước file") }
        let total = off_t(st.st_size)
        guard ftruncate(outFd, total) == 0 else { throw posixError("Không tạo được file đích") }

        let chunk = 8 * 1024 * 1024
        var buffer = [UInt8](repeating: 0, count: chunk)
        var pos: off_t = 0
        while pos < total {
            let dataStart = lseek(inFd, pos, SEEK_DATA)
            if dataStart < 0 { break } // phần còn lại toàn là lỗ
            var dataEnd = lseek(inFd, dataStart, SEEK_HOLE)
            if dataEnd < 0 { dataEnd = total }
            var off = dataStart
            while off < dataEnd {
                let want = Int(min(off_t(chunk), dataEnd - off))
                let n = buffer.withUnsafeMutableBytes { pread(inFd, $0.baseAddress, want, off) }
                guard n > 0 else { throw posixError("Lỗi đọc dữ liệu") }
                let w = buffer.withUnsafeBytes { pwrite(outFd, $0.baseAddress, n, off) }
                guard w == n else { throw posixError("Lỗi ghi dữ liệu (ổ đầy?)") }
                off += off_t(n)
            }
            pos = dataEnd
        }
        guard fsync(outFd) == 0 else { throw posixError("Lỗi ghi xuống ổ") }
    }

    func posixError(_ msg: String) -> NSError {
        NSError(domain: "Export", code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: msg + " (" + String(cString: strerror(errno)) + ")"])
    }

    // Dung lượng thật đang chiếm trên ổ (file thưa chỉ tính phần có dữ liệu)
    func allocatedSize(of url: URL) -> Int64 {
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
        for case let file as URL in walker {
            let v = try? file.resourceValues(forKeys: Set(keys))
            total += Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        return total
    }

    func gb(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }

    func showInfo(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // Win12 báo vị trí vùng hiển thị máy ảo (đơn vị điểm CSS, gốc ở góc trên trái)
    func placeVMView(_ body: [String: Any]) {
        let visible = (body["visible"] as? Bool) ?? false
        guard visible, vm.isRunning,
              let x = body["x"] as? Double, let y = body["y"] as? Double,
              let w = body["w"] as? Double, let h = body["h"] as? Double,
              w > 20, h > 20 else {
            vm.vmView.isHidden = true
            return
        }
        // Đổi sang hệ tọa độ của macOS (gốc ở góc dưới trái)
        let height = webView.bounds.height
        vm.vmView.frame = NSRect(x: x, y: height - y - h, width: w, height: h)
        vm.vmView.isHidden = false
    }

    // =====================================================
    // LIÊN KẾT & CỬA SỔ MỚI
    // Link web bên ngoài (http/https) mở bằng trình duyệt mặc định;
    // link tới file trong app thì mở ngay trong cửa sổ hiện tại.
    // =====================================================
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if url.isFileURL {
                webView.load(navigationAction.request)
            } else {
                NSWorkspace.shared.open(url)
            }
        }
        return nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Người dùng bấm link ra trang web bên ngoài ở khung chính -> mở trình duyệt
        if navigationAction.navigationType == .linkActivated,
           navigationAction.targetFrame?.isMainFrame ?? true,
           let url = navigationAction.request.url,
           let scheme = url.scheme, scheme == "http" || scheme == "https" {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // =====================================================
    // HỘP THOẠI alert / confirm / prompt CỦA JAVASCRIPT
    // (WKWebView mặc định không hiện, phải tự vẽ bằng hộp thoại macOS)
    // =====================================================
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Hủy")
        alert.beginSheetModal(for: window) { response in
            completionHandler(response == .alertFirstButtonReturn)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = prompt
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.stringValue = defaultText ?? ""
        alert.accessoryView = input
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Hủy")
        alert.beginSheetModal(for: window) { response in
            completionHandler(response == .alertFirstButtonReturn ? input.stringValue : nil)
        }
        alert.window.initialFirstResponder = input
    }

    // Chọn file khi trang có ô <input type="file">
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.beginSheetModal(for: window) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    // =====================================================
    // NHẬN LỆNH TỪ JAVASCRIPT
    // { action: "save", data: "<chuỗi JSON>" } -> ghi file
    // { action: "openFolder" }                -> mở thư mục dữ liệu trong Finder
    // { action: "listApps" }                  -> gửi danh sách app Mac về trang
    // { action: "launchApp", path: "..." }    -> mở app Mac thật
    // =====================================================
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {
        case "save":
            if let text = body["data"] as? String {
                saveData(text)
            }
        case "openFolder":
            NSWorkspace.shared.open(dataDir)
        case "vmBlur":
            // Bấm ra ngoài cửa sổ máy ảo -> trả bàn phím về cho Win12
            if window.firstResponder === vm.vmView { window.makeFirstResponder(webView) }
        case "listApps":
            sendAppList(refresh: (body["refresh"] as? Bool) ?? false)
        case "launchApp":
            if let path = body["path"] as? String {
                launchApp(path)
            }
        case "saveWebState":
            if let text = body["data"] as? String, let data = text.data(using: .utf8), isValidDataObject(data) {
                try? data.write(to: AppPaths.base.appendingPathComponent("webstate.json"), options: .atomic)
            }
        case "host":
            let id = body["id"] ?? 0
            let op = body["op"] as? String ?? ""
            let args = body["args"] as? [String: Any] ?? [:]
            do {
                let result = try host.handle(op: op, args: args)
                replyHost(id, result: result, error: nil)
            } catch {
                replyHost(id, result: nil, error: error.localizedDescription)
            }
        case "battery":
            if let data = try? JSONSerialization.data(withJSONObject: host.batteryInfo()),
               let json = String(data: data, encoding: .utf8) {
                webView.evaluateJavaScript("window.__anh7Battery && window.__anh7Battery(\(json));", completionHandler: nil)
            }
        case "vmApps":
            let json = vm.guestAppsJSON()
            webView.evaluateJavaScript("window.__vmAppsReceive && window.__vmAppsReceive(\(json));", completionHandler: nil)
        case "vmLaunch":
            if let path = body["path"] as? String {
                vm.launchGuestApp(path)
            }
        case "vmStatus":
            vm.sendCurrentState()
        case "vmInstall":
            vm.install()
        case "vmStart":
            vm.start()
        case "vmStop":
            vm.requestStop()
        case "vmForceStop":
            vm.forceStop()
        case "vmShare":
            vm.openShareFolder()
        case "vmDelete":
            vm.deleteVM()
        case "vmRect":
            placeVMView(body)
        case "vmFocus":
            if vm.isRunning { window.makeFirstResponder(vm.vmView) }
        default:
            break
        }
    }

    // =====================================================
    // APP MAC THẬT
    // Quét các thư mục Ứng dụng chuẩn của macOS, lấy tên + icon,
    // gửi cho Win12 hiển thị. Chỉ mở app nằm trong danh sách đã quét
    // (trang web không thể yêu cầu mở file tùy ý trên máy).
    // =====================================================
    var appCacheJSON: String?
    var allowedAppPaths = Set<String>()

    var appFolders: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            home.appendingPathComponent("Applications"),
        ]
    }

    // Tìm tất cả .app trong các thư mục trên (và 1 cấp thư mục con, ví dụ "Microsoft Office/")
    func findApps() -> [URL] {
        let fm = FileManager.default
        var found: [URL] = []
        var seen = Set<String>()
        let ownPath = Bundle.main.bundleURL.standardizedFileURL.path

        func add(_ url: URL) {
            let path = url.standardizedFileURL.path
            guard path != ownPath, !seen.contains(path) else { return }
            seen.insert(path)
            found.append(url)
        }

        for folder in appFolders {
            let items = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles])) ?? []
            for item in items {
                if item.pathExtension == "app" {
                    add(item)
                } else if (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    let inner = (try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil,
                                                             options: [.skipsHiddenFiles])) ?? []
                    for sub in inner where sub.pathExtension == "app" {
                        add(sub)
                    }
                }
            }
        }
        return found
    }

    // Icon app -> ảnh PNG 64x64 dạng base64 để trang web hiển thị được
    func iconBase64(for url: URL, size: Int = 64) -> String {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return "" }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])?.base64EncodedString() ?? ""
    }

    func sendAppList(refresh: Bool) {
        if !refresh, let cached = appCacheJSON {
            webView.evaluateJavaScript("window.__macAppsReceive && window.__macAppsReceive(\(cached));", completionHandler: nil)
            return
        }

        // Chạy sau 1 nhịp để giao diện kịp hiện chữ "Đang tải..."
        DispatchQueue.main.async {
            let fm = FileManager.default
            var list: [[String: String]] = []
            var allowed = Set<String>()

            for url in self.findApps() {
                var name = fm.displayName(atPath: url.path)
                if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
                let path = url.standardizedFileURL.path
                allowed.insert(path)
                list.append(["name": name, "path": path, "icon": self.iconBase64(for: url)])
            }

            list.sort { $0["name"]!.localizedCaseInsensitiveCompare($1["name"]!) == .orderedAscending }

            guard let data = try? JSONSerialization.data(withJSONObject: list),
                  let json = String(data: data, encoding: .utf8) else { return }

            self.allowedAppPaths = allowed
            self.appCacheJSON = json
            self.webView.evaluateJavaScript("window.__macAppsReceive && window.__macAppsReceive(\(json));", completionHandler: nil)
        }
    }

    func launchApp(_ path: String) {
        let clean = URL(fileURLWithPath: path).standardizedFileURL.path
        guard allowedAppPaths.contains(clean) else {
            NSLog("MyApp: từ chối mở app ngoài danh sách: \(path)")
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: clean), configuration: config) { _, error in
            guard let error = error else { return }
            DispatchQueue.main.async {
                let msg = self.jsonString(error.localizedDescription)
                self.webView.evaluateJavaScript("window.__macAppsError && window.__macAppsError(\(msg));", completionHandler: nil)
            }
        }
    }

    // =====================================================
    // ĐỌC DỮ LIỆU KHI MỞ APP
    // Thử file chính trước; nếu hỏng thì lấy bản sao lưu mới nhất còn đọc được.
    // =====================================================
    func loadDataJSON() -> String {
        let candidates = [dataFile] + backupFilesNewestFirst()
        for url in candidates {
            if let data = try? Data(contentsOf: url),
               isValidDataObject(data),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
        }
        return "null"
    }

    // =====================================================
    // GHI DỮ LIỆU: kiểm tra hợp lệ -> sao lưu đầu ngày -> ghi atomic
    // =====================================================
    func saveData(_ text: String) {
        guard let data = text.data(using: .utf8), isValidDataObject(data) else {
            NSLog("MyApp: bỏ qua dữ liệu không hợp lệ")
            return
        }

        makeDailyBackupIfNeeded()

        do {
            try data.write(to: dataFile, options: .atomic)
        } catch {
            NSLog("MyApp: không ghi được dữ liệu: \(error)")
        }
    }

    func makeDailyBackupIfNeeded() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dataFile.path) else { return }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        let backupFile = backupDir.appendingPathComponent("data-\(today).json")
        guard !fm.fileExists(atPath: backupFile.path) else { return }

        do {
            try fm.copyItem(at: dataFile, to: backupFile)
        } catch {
            NSLog("MyApp: không sao lưu được: \(error)")
            return
        }

        let backups = backupFilesNewestFirst()
        if backups.count > backupKeepCount {
            for old in backups[backupKeepCount...] {
                try? fm.removeItem(at: old)
            }
        }
    }

    func backupFilesNewestFirst() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: backupDir, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("data-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func loadWebStateJSON() -> String {
        let url = AppPaths.base.appendingPathComponent("webstate.json")
        if let data = try? Data(contentsOf: url), isValidDataObject(data),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "null"
    }

    func isValidDataObject(_ data: Data) -> Bool {
        return (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
    }

    func jsonString(_ value: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "\"\""
    }

    // =====================================================
    // THANH MENU
    // =====================================================
    @objc func reloadPage(_ sender: Any?) {
        webView.reload()
    }

    @objc func openDataFolder(_ sender: Any?) {
        NSWorkspace.shared.open(AppPaths.base)
    }

    @objc func toggleFullScreen(_ sender: Any?) {
        window.toggleFullScreen(sender)
    }

    func buildMenu() {
        let mainMenu = NSMenu()

        // ----- Menu ứng dụng -----
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Ẩn Anh 7",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Thoát Anh 7",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // ----- Menu Tệp -----
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "Tệp")
        let exportItem = fileMenu.addItem(withTitle: "Xuất bản di động...", action: #selector(exportPortable(_:)), keyEquivalent: "e")
        exportItem.keyEquivalentModifierMask = [.command, .shift]
        exportItem.target = self
        let dataItem = fileMenu.addItem(withTitle: "Mở thư mục dữ liệu", action: #selector(openDataFolder(_:)), keyEquivalent: "")
        dataItem.target = self
        fileMenuItem.submenu = fileMenu

        // ----- Menu Sửa -----
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Sửa")
        editMenu.addItem(withTitle: "Hoàn tác", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: "Làm lại", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cắt", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Chép", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Dán", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Chọn tất cả", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        // ----- Menu Xem -----
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "Xem")
        let reloadItem = viewMenu.addItem(withTitle: "Tải lại", action: #selector(reloadPage(_:)), keyEquivalent: "r")
        reloadItem.target = self
        let fullItem = viewMenu.addItem(withTitle: "Toàn màn hình", action: #selector(toggleFullScreen(_:)), keyEquivalent: "f")
        fullItem.keyEquivalentModifierMask = [.command, .control]
        fullItem.target = self
        viewMenuItem.submenu = viewMenu

        NSApp.mainMenu = mainMenu
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)   // Hiện icon trên Dock
app.run()
