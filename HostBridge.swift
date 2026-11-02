import Cocoa
import WebKit
import IOKit.ps
import CoreWLAN
import UniformTypeIdentifiers

// =========================================================
// CẦU NỐI WIN12 <-> MÁY MAC THẬT
//
// JavaScript gọi: postMessage({ action: "host", id, op, args })
// Swift trả lời:  window.__hostReply(id, ketQua, loi)
//
// AN TOÀN:
// - Chỉ làm việc với file trong thư mục nhà (~). Đường dẫn được chuẩn hóa,
//   giải liên kết tắt (symlink) rồi mới kiểm tra, nên không "lách" ra ngoài được.
// - Không sửa/xóa trong ~/Library và thư mục dữ liệu của chính Anh 7.
// - Xóa = đưa vào Thùng rác (khôi phục được), không xóa hẳn.
// =========================================================
final class HostBridge: NSObject, WKURLSchemeHandler {

    let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.resolvingSymlinksInPath()
    private let fm = FileManager.default
    private var iconCache: [String: String] = [:]
    private var lastCPU: (busy: UInt64, total: UInt64)?

    // ---------- Cài đặt app (Anh 7 Data/settings.json) ----------
    var settingsURL: URL { AppPaths.base.appendingPathComponent("settings.json") }

    func loadSettings() -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    func saveSettings(_ s: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: s, options: [.prettyPrinted]) {
            try? data.write(to: settingsURL, options: .atomic)
        }
    }

    // =====================================================
    // KIỂM TRA ĐƯỜNG DẪN
    // =====================================================
    enum BridgeError: LocalizedError {
        case msg(String)
        var errorDescription: String? { if case .msg(let m) = self { return m }; return nil }
    }

    // Đường dẫn hợp lệ để XEM: nằm trong thư mục nhà
    func safeURL(_ path: String?) throws -> URL {
        guard let path = path, !path.isEmpty else { throw BridgeError.msg("Thiếu đường dẫn.") }
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let p = url.path, h = home.path
        guard p == h || p.hasPrefix(h + "/") else {
            throw BridgeError.msg("Chỉ được truy cập file trong thư mục nhà của bạn.")
        }
        return url
    }

    // Đường dẫn hợp lệ để SỬA/XÓA: như trên, trừ thư mục hệ thống của người dùng
    func writableURL(_ path: String?) throws -> URL {
        let url = try safeURL(path)
        let protected = [home.appendingPathComponent("Library").path,
                         AppPaths.base.standardizedFileURL.resolvingSymlinksInPath().path]
        for p in protected where url.path == p || url.path.hasPrefix(p + "/") {
            throw BridgeError.msg("Thư mục này được bảo vệ, không sửa/xóa từ Win12.")
        }
        guard url.path != home.path else { throw BridgeError.msg("Không thể sửa/xóa thư mục nhà.") }
        return url
    }

    func validName(_ name: String?) throws -> String {
        let n = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, n != ".", n != "..", !n.contains("/"), !n.contains(":") else {
            throw BridgeError.msg("Tên không hợp lệ (không chứa / hoặc :).")
        }
        return n
    }

    // =====================================================
    // XỬ LÝ LỆNH
    // =====================================================
    func handle(op: String, args: [String: Any]) throws -> Any {
        switch op {

        // ---------- TỆP ----------
        case "files.places":
            var places: [[String: String]] = [["name": "Thư mục nhà", "path": home.path, "icon": "home"]]
            let named: [(String, String, String)] = [
                ("Màn hình nền", "Desktop", "desktop"), ("Tài liệu", "Documents", "doc"),
                ("Tải về", "Downloads", "down"), ("Ảnh", "Pictures", "pic"),
                ("Nhạc", "Music", "music"), ("Phim", "Movies", "movie"),
                ("Chia sẻ máy ảo", "MayAo-ChiaSe", "share")]
            for (name, folder, icon) in named {
                let u = home.appendingPathComponent(folder)
                if fm.fileExists(atPath: u.path) { places.append(["name": name, "path": u.path, "icon": icon]) }
            }
            return places

        case "files.list":
            let url = try safeURL(args["path"] as? String)
            let showHidden = (args["hidden"] as? Bool) ?? false
            let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isPackageKey]
            let opts: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]
            let items = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: opts)
            var out: [[String: Any]] = []
            for item in items {
                let v = try? item.resourceValues(forKeys: Set(keys))
                let isDir = (v?.isDirectory ?? false) && !(v?.isPackage ?? false) // .app coi như file
                out.append([
                    "name": item.lastPathComponent,
                    "path": item.path,
                    "dir": isDir,
                    "size": v?.fileSize ?? 0,
                    "mtime": (v?.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1000,
                    "ext": item.pathExtension.lowercased(),
                ])
            }
            let parent = url.path == home.path ? "" : url.deletingLastPathComponent().path
            let result: [String: Any] = ["path": url.path, "parent": parent, "items": out, "home": home.path]
            return result

        case "files.icon":
            let url = try safeURL(args["path"] as? String)
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            // File thường cùng đuôi dùng chung icon -> lưu đệm theo đuôi cho nhanh
            let key = (isDir || url.pathExtension == "app" || url.pathExtension.isEmpty) ? url.path : "ext:" + url.pathExtension.lowercased()
            if let cached = iconCache[key] { return cached }
            let b64 = iconBase64(NSWorkspace.shared.icon(forFile: url.path), size: 48)
            iconCache[key] = b64
            return b64

        case "files.readText":
            let url = try safeURL(args["path"] as? String)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            guard size <= 2 * 1024 * 1024 else { throw BridgeError.msg("File quá lớn để sửa (tối đa 2 MB).") }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                throw BridgeError.msg("Không phải file văn bản UTF-8.")
            }
            return text

        case "files.writeText":
            let url = try writableURL(args["path"] as? String)
            guard let text = args["text"] as? String else { throw BridgeError.msg("Thiếu nội dung.") }
            try Data(text.utf8).write(to: url, options: .atomic)
            return true

        case "files.mkdir":
            let parent = try writableOrHome(args["path"] as? String)
            let name = try validName(args["name"] as? String)
            let target = parent.appendingPathComponent(name)
            guard !fm.fileExists(atPath: target.path) else { throw BridgeError.msg("Đã có mục cùng tên.") }
            try fm.createDirectory(at: target, withIntermediateDirectories: false)
            return target.path

        case "files.newText":
            let parent = try writableOrHome(args["path"] as? String)
            let name = try validName(args["name"] as? String)
            let target = parent.appendingPathComponent(name)
            guard !fm.fileExists(atPath: target.path) else { throw BridgeError.msg("Đã có mục cùng tên.") }
            try Data().write(to: target)
            return target.path

        case "files.rename":
            let url = try writableURL(args["path"] as? String)
            let name = try validName(args["name"] as? String)
            let target = url.deletingLastPathComponent().appendingPathComponent(name)
            guard !fm.fileExists(atPath: target.path) else { throw BridgeError.msg("Đã có mục cùng tên.") }
            try fm.moveItem(at: url, to: target)
            return target.path

        case "files.trash":
            let url = try writableURL(args["path"] as? String)
            try fm.trashItem(at: url, resultingItemURL: nil)
            return true

        case "files.open":
            let url = try safeURL(args["path"] as? String)
            NSWorkspace.shared.open(url)
            return true

        case "files.reveal":
            let url = try safeURL(args["path"] as? String)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return true

        // ---------- HỆ THỐNG: điều khiển thêm ----------
        case "sys.setBrightness":
            let level = Float(max(0.0, min(1.0, (args["level"] as? Double) ?? 0.5)))
            try setBrightness(level)
            return true

        case "sys.setWifi":
            let on = (args["on"] as? Bool) ?? true
            guard let wifi = CWWiFiClient.shared().interface() else { throw BridgeError.msg("Không tìm thấy Wi-Fi.") }
            do { try wifi.setPower(on) } catch {
                throw BridgeError.msg("macOS không cho đổi Wi-Fi từ app này: \(error.localizedDescription)")
            }
            return true

        case "sys.setBluetooth":
            let on = (args["on"] as? Bool) ?? true
            try setBluetooth(on)
            return true

        case "sys.lock":
            lockScreen()
            return true

        case "sys.sleep":
            // Đợi 1 giây để giao diện kịp trả lời trước khi máy ngủ
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { _ = self.run("/usr/bin/pmset", ["sleepnow"]) }
            return true

        case "sys.setMacWallpaper":
            let src = try safeURL(args["path"] as? String)
            // Chép ảnh vào ~/Pictures/Anh 7 Hình nền để hình nền không mất khi dọn dữ liệu Anh 7
            let dir = home.appendingPathComponent("Pictures/Anh 7 Hình nền", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(src.lastPathComponent)
            if dest.path != src.path {
                try? fm.removeItem(at: dest)
                try fm.copyItem(at: src, to: dest)
            }
            for screen in NSScreen.screens {
                try NSWorkspace.shared.setDesktopImageURL(dest, for: screen, options: [:])
            }
            return true

        // Hộp thoại chọn ảnh của macOS; ảnh được chép vào thư mục dữ liệu Anh 7 (media/)
        // để Win12 hiển thị được và đi theo bản di động. Trả về { rel, path } hoặc null nếu hủy.
        case "app.pickImage":
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            panel.message = (args["message"] as? String) ?? "Chọn ảnh"
            panel.directoryURL = home.appendingPathComponent("Pictures")
            guard panel.runModal() == .OK, let picked = panel.url else { return NSNull() }
            let media = AppPaths.base.appendingPathComponent("media", isDirectory: true)
            try fm.createDirectory(at: media, withIntermediateDirectories: true)
            let ext = picked.pathExtension.isEmpty ? "png" : picked.pathExtension.lowercased()
            let name = String(UUID().uuidString.prefix(8)) + "." + ext
            let dest = media.appendingPathComponent(name)
            try fm.copyItem(at: picked, to: dest)
            let picked2: [String: Any] = ["rel": "media/" + name, "path": dest.path, "name": picked.lastPathComponent]
            return picked2

        // ---------- HỆ THỐNG ----------
        case "sys.info":
            return systemInfo()

        case "sys.setVolume":
            let level = max(0, min(100, (args["level"] as? Double).map { Int($0) } ?? 50))
            try runAppleScript("set volume output volume \(level)")
            return true

        case "sys.setMuted":
            let muted = (args["muted"] as? Bool) ?? false
            try runAppleScript("set volume output muted \(muted)")
            return true

        case "sys.setDark":
            let dark = (args["dark"] as? Bool) ?? false
            try runAppleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)")
            return true

        // ---------- CÀI ĐẶT APP ----------
        case "app.getSettings":
            let gb: UInt64 = 1024 * 1024 * 1024
            let physGB = Int(ProcessInfo.processInfo.physicalMemory / gb)
            let limits: [String: Int] = [
                "maxMemGB": max(4, physGB - 2),
                "physMemGB": physGB,
                "maxCPU": max(2, ProcessInfo.processInfo.processorCount - 1),
            ]
            let result: [String: Any] = [
                "settings": loadSettings(),
                "limits": limits,
                "portable": AppPaths.isPortable,
                "dataPath": AppPaths.base.path,
            ]
            return result

        case "app.setSettings":
            guard let incoming = args["settings"] as? [String: Any] else { throw BridgeError.msg("Thiếu cài đặt.") }
            var s = loadSettings()
            for (k, v) in incoming { s[k] = v }
            saveSettings(s)
            return true

        // ---------- APP ANH 7 (app web chạy trong Win12, không cần máy chủ) ----------
        case "apps.list":
            return listApps()

        case "apps.install":
            return try installAppFromPanel()

        case "apps.remove":
            let id = try validAppId(args["id"] as? String)
            guard !isBuiltinApp(id) else { throw BridgeError.msg("Không gỡ được app có sẵn của Anh 7.") }
            let dir = userAppsDir.appendingPathComponent(id, isDirectory: true)
            guard fm.fileExists(atPath: dir.path) else { throw BridgeError.msg("Không tìm thấy app.") }
            try fm.trashItem(at: dir, resultingItemURL: nil)   // vào Thùng rác, khôi phục được
            if (args["keepData"] as? Bool) != true {
                let data = appDataDir.appendingPathComponent(id + ".json")
                if fm.fileExists(atPath: data.path) { try? fm.trashItem(at: data, resultingItemURL: nil) }
            }
            return true

        // Dữ liệu riêng của từng app: appdata/<id>.json (chuỗi JSON, tối đa 5 MB)
        case "apps.dataGet":
            let id = try validAppId(args["id"] as? String)
            let url = appDataDir.appendingPathComponent(id + ".json")
            guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return "{}" }
            return text

        case "apps.dataSet":
            let id = try validAppId(args["id"] as? String)
            guard let text = args["json"] as? String else { throw BridgeError.msg("Thiếu dữ liệu.") }
            guard text.utf8.count <= 5 * 1024 * 1024 else { throw BridgeError.msg("Dữ liệu app quá lớn (tối đa 5 MB).") }
            guard (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil else { throw BridgeError.msg("Dữ liệu không phải JSON.") }
            try fm.createDirectory(at: appDataDir, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: appDataDir.appendingPathComponent(id + ".json"), options: .atomic)
            return true

        case "apps.openFolder":
            try fm.createDirectory(at: userAppsDir, withIntermediateDirectories: true)
            NSWorkspace.shared.open(userAppsDir)
            return true

        default:
            throw BridgeError.msg("Lệnh không hỗ trợ: \(op)")
        }
    }

    // =====================================================
    // APP ANH 7
    // - App có sẵn: trong app, Contents/Resources/anh7apps/<id>/
    // - App tự cài: <dữ liệu Anh 7>/apps/<id>/  (đi theo bản di động)
    // - Mỗi app là 1 thư mục có app.json + index.html (HTML/CSS/JS thuần)
    // =====================================================
    var userAppsDir: URL { AppPaths.base.appendingPathComponent("apps", isDirectory: true) }
    var appDataDir: URL { AppPaths.base.appendingPathComponent("appdata", isDirectory: true) }
    var builtinAppsDir: URL? { Bundle.main.resourceURL?.appendingPathComponent("anh7apps", isDirectory: true) }

    // Mã app: chữ thường, số, dấu . _ - (vd "vn.anh7.ghichu"); "_sdk" dành riêng cho thư viện
    func validAppId(_ s: String?) throws -> String {
        guard let s = s, s.range(of: "^[a-z0-9][a-z0-9._-]{0,62}$", options: .regularExpression) != nil,
              !s.contains("..") else { throw BridgeError.msg("Mã app không hợp lệ.") }
        return s
    }

    func isBuiltinApp(_ id: String) -> Bool {
        guard let b = builtinAppsDir else { return false }
        return fm.fileExists(atPath: b.appendingPathComponent(id).appendingPathComponent("app.json").path)
    }

    func readManifest(_ dir: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("app.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }

    func listApps() -> [[String: Any]] {
        var out: [[String: Any]] = []
        var seen = Set<String>()
        let sources: [(URL?, Bool)] = [(builtinAppsDir, true), (userAppsDir, false)]
        for (root, builtin) in sources {
            guard let root = root, let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for dir in dirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let id = dir.lastPathComponent
                guard !id.hasPrefix("_"), !seen.contains(id), (try? validAppId(id)) != nil,
                      let m = readManifest(dir) else { continue }
                seen.insert(id)
                var app: [String: Any] = [
                    "id": id,
                    "name": (m["name"] as? String) ?? id,
                    "version": (m["version"] as? String) ?? "",
                    "description": (m["description"] as? String) ?? "",
                    "author": (m["author"] as? String) ?? "",
                    "entry": (m["entry"] as? String) ?? "index.html",
                    "icon": (m["icon"] as? String) ?? "",
                    "width": (m["width"] as? Int) ?? 720,
                    "height": (m["height"] as? Int) ?? 480,
                    "permissions": (m["permissions"] as? [String]) ?? [],
                    "builtin": builtin,
                ]
                if let c = m["color"] as? String { app["color"] = c }
                out.append(app)
            }
        }
        return out
    }

    // Chọn thư mục app hoặc file .zip / .anh7app rồi cài vào <dữ liệu>/apps/<id>
    func installAppFromPanel() throws -> Any {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Chọn thư mục app (có app.json) hoặc file .zip / .anh7app"
        panel.directoryURL = home.appendingPathComponent("Downloads")
        guard panel.runModal() == .OK, let picked = panel.url else { return NSNull() }

        var temp: URL?
        defer { if let t = temp { try? fm.removeItem(at: t) } }
        var root = picked
        let ext = picked.pathExtension.lowercased()
        if ext == "zip" || ext == "anh7app" {
            let t = fm.temporaryDirectory.appendingPathComponent("anh7-install-" + UUID().uuidString, isDirectory: true)
            temp = t
            try fm.createDirectory(at: t, withIntermediateDirectories: true)
            guard run("/usr/bin/ditto", ["-x", "-k", picked.path, t.path]) == 0 else {
                throw BridgeError.msg("Không giải nén được file.")
            }
            root = t
        }
        // app.json nằm ngay gốc, hoặc trong 1 thư mục con duy nhất (kiểu nén cả thư mục)
        if readManifest(root) == nil {
            let subs = ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
                .filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != "__MACOSX" }
            if subs.count == 1, readManifest(subs[0]) != nil { root = subs[0] }
        }
        guard let m = readManifest(root) else { throw BridgeError.msg("Không thấy file app.json hợp lệ.") }
        let id = try validAppId(m["id"] as? String)
        guard let name = m["name"] as? String, !name.isEmpty else { throw BridgeError.msg("app.json thiếu \"name\".") }
        guard !isBuiltinApp(id) else { throw BridgeError.msg("Mã app \"\(id)\" trùng app có sẵn của Anh 7.") }
        let entry = (m["entry"] as? String) ?? "index.html"
        guard !entry.contains(".."), fm.fileExists(atPath: root.appendingPathComponent(entry).path) else {
            throw BridgeError.msg("Không thấy file khởi chạy \"\(entry)\".")
        }

        try fm.createDirectory(at: userAppsDir, withIntermediateDirectories: true)
        let dest = userAppsDir.appendingPathComponent(id, isDirectory: true)
        let replaced = fm.fileExists(atPath: dest.path)
        if replaced { try fm.trashItem(at: dest, resultingItemURL: nil) }   // bản cũ vào Thùng rác
        try fm.copyItem(at: root, to: dest)
        let result: [String: Any] = ["id": id, "name": name, "replaced": replaced]
        return result
    }

    // anh7app://<id>/<đường dẫn> -> file thật trong thư mục app (không cho thoát ra ngoài)
    func appFileURL(host: String?, path: String) throws -> URL {
        guard let host = host?.lowercased() else { throw BridgeError.msg("Thiếu mã app.") }
        var roots: [URL] = []
        if host == "_sdk" {
            if let b = builtinAppsDir { roots.append(b.appendingPathComponent("_sdk", isDirectory: true)) }
        } else {
            let id = try validAppId(host)
            if let b = builtinAppsDir, isBuiltinApp(id) { roots.append(b.appendingPathComponent(id, isDirectory: true)) }
            roots.append(userAppsDir.appendingPathComponent(id, isDirectory: true))
        }
        let rel = path.hasPrefix("/") ? String(path.dropFirst()) : path
        for root in roots {
            let r = root.standardizedFileURL.resolvingSymlinksInPath()
            let f = r.appendingPathComponent(rel.isEmpty ? "index.html" : rel).standardizedFileURL.resolvingSymlinksInPath()
            guard f.path.hasPrefix(r.path + "/") else { continue }
            if fm.fileExists(atPath: f.path) { return f }
        }
        throw BridgeError.msg("Không tìm thấy file của app.")
    }

    // Thư mục cha để tạo mới: cho phép cả thư mục nhà
    private func writableOrHome(_ path: String?) throws -> URL {
        let url = try safeURL(path)
        if url.path == home.path { return url }
        return try writableURL(path)
    }

    // =====================================================
    // THÔNG TIN MÁY
    // =====================================================
    func systemInfo() -> [String: Any] {
        var info: [String: Any] = [:]

        info["battery"] = batteryInfo()

        // RAM
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
            info["memory"] = ["total": Double(total), "used": Double(used)]
        }

        // CPU (% bận rộn giữa 2 lần hỏi)
        var load = host_cpu_load_info()
        var cpuCount = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr2 = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(cpuCount)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &cpuCount)
            }
        }
        if kr2 == KERN_SUCCESS {
            let user = UInt64(load.cpu_ticks.0), sys = UInt64(load.cpu_ticks.1)
            let idle = UInt64(load.cpu_ticks.2), nice = UInt64(load.cpu_ticks.3)
            let busy = user + sys + nice, all = busy + idle
            if let last = lastCPU, all > last.total {
                info["cpu"] = Double(busy - last.busy) / Double(all - last.total) * 100
            }
            lastCPU = (busy, all)
        }

        // Ổ đĩa
        if let v = try? URL(fileURLWithPath: "/").resourceValues(
            forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            info["disk"] = ["total": Double(v.volumeTotalCapacity ?? 0),
                            "free": Double(v.volumeAvailableCapacityForImportantUsage ?? 0)]
        }

        // Độ sáng màn hình (0...1) và Bluetooth; nil nếu máy không hỗ trợ
        if let b = getBrightness() { info["brightness"] = b }
        if let bt = getBluetooth() { info["bluetooth"] = bt }
        info["host"] = hostInfo()

        // Wi-Fi (macOS mới chỉ trả tên mạng khi app có quyền Vị trí -> có thể trống)
        let wifi = CWWiFiClient.shared().interface()
        let ssid: Any = wifi?.ssid() ?? NSNull()
        info["wifi"] = ["on": wifi?.powerOn() ?? false, "ssid": ssid] as [String: Any]

        // Giao diện + âm lượng
        let appearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        info["dark"] = appearance == .darkAqua
        if let v = try? runAppleScript("output volume of (get volume settings)"), let level = Int(v) {
            info["volume"] = level
        }
        if let m = try? runAppleScript("output muted of (get volume settings)") {
            info["muted"] = m == "true"
        }
        return info
    }

    // Pin thật: { available, percent, charging, plugged }
    func batteryInfo() -> [String: Any] {
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
           let first = list.first,
           let desc = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any] {
            let cur = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            return [
                "available": true,
                "percent": max > 0 ? Int(Double(cur) / Double(max) * 100) : cur,
                "charging": desc[kIOPSIsChargingKey] as? Bool ?? false,
                "plugged": (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue,
            ]
        } else {
            return ["available": false]
        }

    }

    // =====================================================
    // THÔNG TIN NGƯỜI DÙNG & MÁY (thay dữ liệu giả của Win12)
    // =====================================================
    func hostInfo() -> [String: Any] {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return [
            "fullName": NSFullUserName(),
            "userName": NSUserName(),
            "computerName": Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            "model": String(cString: model),
            "macOS": "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)",
            "dataPath": AppPaths.base.path,
        ]
    }

    // =====================================================
    // ĐỘ SÁNG / BLUETOOTH / KHÓA MÁY
    // Dùng thư viện nội bộ của macOS (không công khai) qua dlopen:
    // có thể không chạy trên mọi máy/phiên bản -> báo lỗi rõ ràng thay vì sập app.
    // =====================================================
    private typealias GetBrightnessFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFn = @convention(c) (UInt32, Float) -> Int32
    private lazy var displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)

    func getBrightness() -> Double? {
        guard let h = displayServices, let sym = dlsym(h, "DisplayServicesGetBrightness") else { return nil }
        let fn = unsafeBitCast(sym, to: GetBrightnessFn.self)
        var value: Float = 0
        return fn(CGMainDisplayID(), &value) == 0 ? Double(value) : nil
    }

    func setBrightness(_ level: Float) throws {
        guard let h = displayServices, let sym = dlsym(h, "DisplayServicesSetBrightness") else {
            throw BridgeError.msg("Máy này không hỗ trợ chỉnh độ sáng từ app.")
        }
        let fn = unsafeBitCast(sym, to: SetBrightnessFn.self)
        guard fn(CGMainDisplayID(), level) == 0 else {
            throw BridgeError.msg("Không chỉnh được độ sáng (màn hình ngoài thường không hỗ trợ).")
        }
    }

    private typealias BTGetFn = @convention(c) () -> Int32
    private typealias BTSetFn = @convention(c) (Int32) -> Void
    private lazy var bluetoothLib = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_NOW)

    func getBluetooth() -> Bool? {
        guard let h = bluetoothLib, let sym = dlsym(h, "IOBluetoothPreferenceGetControllerPowerState") else { return nil }
        return unsafeBitCast(sym, to: BTGetFn.self)() != 0
    }

    func setBluetooth(_ on: Bool) throws {
        guard let h = bluetoothLib, let sym = dlsym(h, "IOBluetoothPreferenceSetControllerPowerState") else {
            throw BridgeError.msg("Máy này không hỗ trợ bật/tắt Bluetooth từ app.")
        }
        unsafeBitCast(sym, to: BTSetFn.self)(on ? 1 : 0)
        // Kiểm tra lại sau khi đặt: macOS mới có thể âm thầm từ chối
        usleep(400_000)
        if let now = getBluetooth(), now != on {
            throw BridgeError.msg("macOS không cho đổi Bluetooth từ app này. Dùng Trung tâm điều khiển của Mac.")
        }
    }

    private typealias LockFn = @convention(c) () -> Int32
    func lockScreen() {
        if let h = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
           let sym = dlsym(h, "SACLockScreenImmediate") {
            _ = unsafeBitCast(sym, to: LockFn.self)()
            return
        }
        // Dự phòng: tắt màn hình (khóa nếu Mac đặt "yêu cầu mật khẩu ngay")
        _ = run("/usr/bin/pmset", ["displaysleepnow"])
    }

    @discardableResult
    func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus } catch { return -1 }
    }

    // Chạy AppleScript, trả về kết quả dạng chữ
    @discardableResult
    func runAppleScript(_ source: String) throws -> String {
        var err: NSDictionary?
        guard let script = NSAppleScript(source: source) else { throw BridgeError.msg("Lỗi AppleScript.") }
        let result = script.executeAndReturnError(&err)
        if let err = err {
            let code = err[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 {
                throw BridgeError.msg("Chưa cấp quyền: Cài đặt hệ thống > Quyền riêng tư & Bảo mật > Tự động hóa > bật Anh 7 > System Events.")
            }
            throw BridgeError.msg(err[NSAppleScript.errorMessage] as? String ?? "Lỗi AppleScript (\(code)).")
        }
        return result.stringValue ?? ""
    }

    func iconBase64(_ icon: NSImage, size: Int) -> String {
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

    // =====================================================
    // PHỤC VỤ FILE THẬT CHO WIN12 XEM (anh7file:///Users/.../anh.jpg)
    // Hỗ trợ "Range" để video tua được mà không nạp cả file vào bộ nhớ.
    // =====================================================
    private var stoppedTasks = Set<ObjectIdentifier>()

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let id = ObjectIdentifier(task)
        guard let reqURL = task.request.url else { return }
        let path = reqURL.path  // URL.path đã tự giải mã %20...
        let rangeHeader = task.request.value(forHTTPHeaderField: "Range")
        let isApp = reqURL.scheme?.lowercased() == "anh7app"
        let appHost = reqURL.host

        DispatchQueue.global(qos: .userInitiated).async {
            var response: URLResponse?
            var body = Data()
            var failure: Error?
            do {
                // anh7app://  -> file trong thư mục app;  anh7file:// -> file thật trong thư mục nhà
                let url = try (isApp ? self.appFileURL(host: appHost, path: path) : self.safeURL(path))
                let total = (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
                var mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                if ["html", "htm", "css", "js", "json", "txt", "svg"].contains(url.pathExtension.lowercased()) {
                    mime += "; charset=utf-8"
                }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }

                var headers = ["Content-Type": mime, "Accept-Ranges": "bytes", "Cache-Control": "no-cache"]
                if isApp {
                    // App chỉ được nạp tài nguyên của chính nó, thư viện Anh 7 và Internet;
                    // KHÔNG đọc trực tiếp file trong máy (anh7file://, file://)
                    headers["Content-Security-Policy"] =
                        "default-src anh7app: data: blob: 'unsafe-inline' 'unsafe-eval'; " +
                        "img-src anh7app: data: blob: https:; media-src anh7app: data: blob: https:; " +
                        "connect-src anh7app: https: wss:; font-src anh7app: data: https:; " +
                        "style-src anh7app: 'unsafe-inline' https:"
                }
                var status = 200
                if let r = rangeHeader, r.hasPrefix("bytes="), total > 0 {
                    // "bytes=start-end" hoặc "bytes=start-"; mỗi lần trả tối đa 4 MB
                    let parts = r.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
                    let start = Int(parts.first ?? "") ?? 0
                    var end = parts.count > 1 ? (Int(parts[1]) ?? total - 1) : total - 1
                    end = min(end, total - 1, start + 4 * 1024 * 1024 - 1)
                    guard start < total, end >= start else { throw BridgeError.msg("Range không hợp lệ.") }
                    try handle.seek(toOffset: UInt64(start))
                    body = handle.readData(ofLength: end - start + 1)
                    headers["Content-Range"] = "bytes \(start)-\(end)/\(total)"
                    status = 206
                } else {
                    body = handle.readDataToEndOfFile()
                }
                headers["Content-Length"] = String(body.count)
                response = HTTPURLResponse(url: reqURL, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
            } catch {
                failure = error
            }

            DispatchQueue.main.async {
                guard !self.stoppedTasks.contains(id) else { self.stoppedTasks.remove(id); return }
                if let failure = failure {
                    task.didFailWithError(failure)
                } else if let response = response {
                    task.didReceive(response)
                    task.didReceive(body)
                    task.didFinish()
                }
            }
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        stoppedTasks.insert(ObjectIdentifier(task))
    }
}
