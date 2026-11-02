import Cocoa
import Virtualization

// =========================================================
// MÁY ẢO macOS CHẠY BÊN TRONG APP ANH 7
// Dùng Virtualization framework của Apple (chỉ có trên máy chip Apple M).
//
// Toàn bộ dữ liệu máy ảo nằm ở:
//   ~/Library/Application Support/MyApp/VM/
//     Disk.img              ổ cứng máy ảo (file thưa, tối đa 64 GB, dùng tới đâu chiếm tới đó)
//     AuxiliaryStorage      bộ nhớ khởi động của máy ảo
//     HardwareModel         thông tin phần cứng
//     MachineIdentifier     mã máy
//     SaveFile.vzvmsave     trạng thái lưu khi thoát app (để mở lại đúng chỗ đang dùng)
//     RestoreImage.ipsw     bộ cài macOS (tự xóa sau khi cài xong để tiết kiệm ~15 GB)
// Thư mục chia sẻ giữa máy thật và máy ảo: ~/MayAo-ChiaSe
//   Trong máy ảo hiện ở: /Volumes/My Shared Files
// =========================================================

// =========================================================
// NƠI LƯU DỮ LIỆU (dùng chung cho cả app)
// - Bản di động: nếu cạnh "Anh 7.app" có thư mục "Anh 7 Data" -> dùng thư mục đó
//   (chép nguyên thư mục chứa app sang USB / máy khác là mang theo máy ảo)
// - Bình thường: ~/Library/Application Support/MyApp
// =========================================================
enum AppPaths {
    static let portableFolderName = "Anh 7 Data"

    static var portableDir: URL {
        Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent(portableFolderName, isDirectory: true)
    }

    static var standardDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyApp", isDirectory: true)
    }

    static let isPortable: Bool = {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: portableDir.path, isDirectory: &isDir) && isDir.boolValue
    }()

    static let base: URL = {
        let dir = isPortable ? portableDir : standardDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}

final class VMManager: NSObject, VZVirtualMachineDelegate, URLSessionDownloadDelegate {

    // Gửi trạng thái cho giao diện Win12: (trạng thái, tiến độ 0...1, thông báo)
    var onState: ((String, Double, String) -> Void)?

    let diskSizeGB: UInt64 = 64

    // Trạng thái hiện tại: notSupported / notInstalled / downloading / installing /
    // stopped / starting / running / stopping / saving / error
    private(set) var state = "stopped"
    private var progress: Double = 0
    private var message = ""

    var virtualMachine: VZVirtualMachine?
    let vmView = VZVirtualMachineView()

    private var installer: VZMacOSInstaller?
    private var progressObserver: NSKeyValueObservation?
    private var downloadSession: URLSession?

    // ---------- Đường dẫn ----------
    lazy var vmDir: URL = {
        let dir = AppPaths.base.appendingPathComponent("VM", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // Thư mục chia sẻ: bản di động để trong "Anh 7 Data/ChiaSe" (đi theo USB),
    // bản thường để ở ~/MayAo-ChiaSe cho dễ tìm
    lazy var shareDir: URL = {
        let dir = AppPaths.isPortable
            ? AppPaths.base.appendingPathComponent("ChiaSe", isDirectory: true)
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("MayAo-ChiaSe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    var diskURL: URL { vmDir.appendingPathComponent("Disk.img") }
    var auxURL: URL { vmDir.appendingPathComponent("AuxiliaryStorage") }
    var hardwareURL: URL { vmDir.appendingPathComponent("HardwareModel") }
    var machineIdURL: URL { vmDir.appendingPathComponent("MachineIdentifier") }
    var saveURL: URL { vmDir.appendingPathComponent("SaveFile.vzvmsave") }
    var ipswURL: URL { vmDir.appendingPathComponent("RestoreImage.ipsw") }
    var installedMarker: URL { vmDir.appendingPathComponent(".installed") }

    var isInstalled: Bool { FileManager.default.fileExists(atPath: installedMarker.path) }
    var isRunning: Bool { virtualMachine?.state == .running || virtualMachine?.state == .paused }

    override init() {
        super.init()
        vmView.capturesSystemKeys = true
        if #available(macOS 14.0, *) {
            // Màn hình máy ảo tự đổi độ phân giải theo kích thước cửa sổ Win12
            vmView.automaticallyReconfiguresDisplay = true
        }
        vmView.isHidden = true
        refreshIdleState()
        installAgentFiles()
    }

    private func set(_ s: String, _ p: Double = 0, _ m: String = "") {
        state = s; progress = p; message = m
        DispatchQueue.main.async { self.onState?(s, p, m) }
    }

    func sendCurrentState() {
        DispatchQueue.main.async { self.onState?(self.state, self.progress, self.message) }
    }

    private func refreshIdleState() {
        #if arch(arm64)
        if virtualMachine == nil {
            state = isInstalled ? "stopped" : "notInstalled"
        }
        #else
        state = "notSupported"
        message = "Máy ảo macOS chỉ chạy trên máy Mac chip Apple (M1 trở lên)."
        #endif
    }

    // =====================================================
    // CẤU HÌNH PHẦN CỨNG MÁY ẢO
    // =====================================================
    #if arch(arm64)
    // Cấu hình người dùng chọn trong Cài đặt Win12 > Máy Mac (Anh 7 Data/settings.json)
    private var userSettings: [String: Any] {
        let url = AppPaths.base.appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    private func cpuCount(minimum: Int) -> Int {
        let host = ProcessInfo.processInfo.processorCount
        // Mặc định: chừa lại 2 nhân cho máy thật, tối đa 4 nhân
        var wanted = min(4, host - 2)
        if let chosen = userSettings["vmCPU"] as? Int, chosen > 0 { wanted = min(chosen, host - 1) }
        return min(max(minimum, wanted, VZVirtualMachineConfiguration.minimumAllowedCPUCount),
                   VZVirtualMachineConfiguration.maximumAllowedCPUCount)
    }

    private func memorySize(minimum: UInt64) -> UInt64 {
        let gb: UInt64 = 1024 * 1024 * 1024
        // Mặc định: một nửa RAM máy thật, tối thiểu 4 GB, tối đa 8 GB
        let half = ProcessInfo.processInfo.physicalMemory / 2
        var size = min(max(half, 4 * gb), 8 * gb)
        if let chosen = userSettings["vmMemGB"] as? Int, chosen > 0 {
            // Luôn chừa ít nhất 2 GB cho máy thật
            let cap = ProcessInfo.processInfo.physicalMemory - 2 * gb
            size = min(UInt64(chosen) * gb, cap)
        }
        size = max(size, minimum)
        size = min(size, VZVirtualMachineConfiguration.maximumAllowedMemorySize)
        return size - (size % (1024 * 1024)) // làm tròn theo MB
    }

    private func makeConfiguration(platform: VZMacPlatformConfiguration,
                                   minCPU: Int, minMemory: UInt64) throws -> VZVirtualMachineConfiguration {
        let config = VZVirtualMachineConfiguration()
        config.platform = platform
        config.bootLoader = VZMacOSBootLoader()
        config.cpuCount = cpuCount(minimum: minCPU)
        config.memorySize = memorySize(minimum: minMemory)

        // Màn hình
        let graphics = VZMacGraphicsDeviceConfiguration()
        let width = (userSettings["vmWidth"] as? Int) ?? 1920
        let height = (userSettings["vmHeight"] as? Int) ?? 1200
        graphics.displays = [VZMacGraphicsDisplayConfiguration(widthInPixels: width, heightInPixels: height, pixelsPerInch: 144)]
        config.graphicsDevices = [graphics]

        // Ổ cứng
        let disk = try VZDiskImageStorageDeviceAttachment(url: diskURL, readOnly: false)
        config.storageDevices = [VZVirtioBlockDeviceConfiguration(attachment: disk)]

        // Mạng: dùng chung internet của máy thật
        let net = VZVirtioNetworkDeviceConfiguration()
        net.attachment = VZNATNetworkDeviceAttachment()
        config.networkDevices = [net]

        // Chuột, bàn phím
        config.pointingDevices = [VZMacTrackpadConfiguration()]
        if #available(macOS 14.0, *) {
            config.keyboards = [VZMacKeyboardConfiguration()]
        } else {
            config.keyboards = [VZUSBKeyboardConfiguration()]
        }

        // Âm thanh ra loa máy thật
        let sound = VZVirtioSoundDeviceConfiguration()
        let output = VZVirtioSoundDeviceOutputStreamConfiguration()
        output.sink = VZHostAudioOutputStreamSink()
        sound.streams = [output]
        config.audioDevices = [sound]

        // Thư mục chia sẻ: chép file .app vào ~/MayAo-ChiaSe là thấy trong máy ảo
        let share = VZVirtioFileSystemDeviceConfiguration(tag: VZVirtioFileSystemDeviceConfiguration.macOSGuestAutomountTag)
        share.share = VZSingleDirectoryShare(directory: VZSharedDirectory(url: shareDir, readOnly: false))
        config.directorySharingDevices = [share]

        try config.validate()
        return config
    }
    #endif

    // =====================================================
    // CÀI ĐẶT: tải bộ cài macOS mới nhất -> cài vào máy ảo
    // =====================================================
    func install() {
        #if arch(arm64)
        guard state == "notInstalled" || state == "error" else { return }

        if FileManager.default.fileExists(atPath: ipswURL.path) {
            installFromIPSW()
            return
        }

        set("downloading", 0, "Đang tìm bản macOS phù hợp...")
        VZMacOSRestoreImage.fetchLatestSupported { result in
            switch result {
            case .failure(let error):
                self.set("error", 0, "Không lấy được thông tin bộ cài macOS: \(error.localizedDescription)")
            case .success(let image):
                DispatchQueue.main.async { self.download(from: image.url) }
            }
        }
        #endif
    }

    private func download(from url: URL) {
        set("downloading", 0, "Đang tải bộ cài macOS (khoảng 15 GB)...")
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        downloadSession = session
        session.downloadTask(with: url).resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let done = Double(totalBytesWritten) / 1_073_741_824
        let total = Double(totalBytesExpectedToWrite) / 1_073_741_824
        set("downloading", p, String(format: "Đang tải bộ cài macOS: %.1f / %.1f GB", done, total))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            try? FileManager.default.removeItem(at: ipswURL)
            try FileManager.default.moveItem(at: location, to: ipswURL)
            DispatchQueue.main.async { self.installFromIPSW() }
        } catch {
            set("error", 0, "Không lưu được bộ cài: \(error.localizedDescription)")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            set("error", 0, "Tải bộ cài thất bại: \(error.localizedDescription). Bấm Cài đặt để thử lại.")
        }
        session.finishTasksAndInvalidate()
    }

    private func installFromIPSW() {
        #if arch(arm64)
        set("installing", 0, "Đang chuẩn bị máy ảo...")
        VZMacOSRestoreImage.load(from: ipswURL) { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    try? FileManager.default.removeItem(at: self.ipswURL)
                    self.set("error", 0, "Bộ cài bị lỗi, đã xóa để tải lại: \(error.localizedDescription)")
                case .success(let image):
                    self.createAndInstall(image: image)
                }
            }
        }
        #endif
    }

    #if arch(arm64)
    private func createAndInstall(image: VZMacOSRestoreImage) {
        guard let req = image.mostFeaturefulSupportedConfiguration, req.hardwareModel.isSupported else {
            set("error", 0, "Máy này không chạy được bản macOS trong bộ cài.")
            return
        }

        do {
            let fm = FileManager.default
            // Tạo ổ cứng thưa 64 GB (chỉ chiếm chỗ thật khi máy ảo ghi dữ liệu)
            try? fm.removeItem(at: diskURL)
            fm.createFile(atPath: diskURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: diskURL)
            try handle.truncate(atOffset: diskSizeGB * 1024 * 1024 * 1024)
            try handle.close()

            let platform = VZMacPlatformConfiguration()
            platform.hardwareModel = req.hardwareModel
            platform.auxiliaryStorage = try VZMacAuxiliaryStorage(
                creatingStorageAt: auxURL, hardwareModel: req.hardwareModel, options: [.allowOverwrite])
            let machineId = VZMacMachineIdentifier()
            platform.machineIdentifier = machineId
            try req.hardwareModel.dataRepresentation.write(to: hardwareURL)
            try machineId.dataRepresentation.write(to: machineIdURL)

            let config = try makeConfiguration(platform: platform,
                                               minCPU: req.minimumSupportedCPUCount,
                                               minMemory: req.minimumSupportedMemorySize)
            let vm = VZVirtualMachine(configuration: config)
            vm.delegate = self
            virtualMachine = vm

            let installer = VZMacOSInstaller(virtualMachine: vm, restoringFromImageAt: ipswURL)
            self.installer = installer
            progressObserver = installer.progress.observe(\.fractionCompleted, options: [.new]) { p, _ in
                self.set("installing", p.fractionCompleted,
                         String(format: "Đang cài macOS vào máy ảo: %.0f%%", p.fractionCompleted * 100))
            }

            installer.install { result in
                DispatchQueue.main.async {
                    self.progressObserver = nil
                    self.installer = nil
                    switch result {
                    case .failure(let error):
                        self.virtualMachine = nil
                        self.set("error", 0, "Cài macOS thất bại: \(error.localizedDescription)")
                    case .success:
                        fm.createFile(atPath: self.installedMarker.path, contents: nil)
                        try? fm.removeItem(at: self.ipswURL) // xóa bộ cài, tiết kiệm ~15 GB
                        // Máy ảo đang tắt sau khi cài; tạo lại bản chạy mới khi bấm Bật
                        self.virtualMachine = nil
                        self.set("stopped", 0, "Đã cài xong. Bấm Bật máy để bắt đầu thiết lập macOS.")
                    }
                }
            }
        } catch {
            set("error", 0, "Không tạo được máy ảo: \(error.localizedDescription)")
        }
    }

    // Đọc lại cấu hình đã lưu để chạy máy ảo
    private func loadSavedVM() throws -> VZVirtualMachine {
        guard let hwData = try? Data(contentsOf: hardwareURL),
              let hw = VZMacHardwareModel(dataRepresentation: hwData),
              let idData = try? Data(contentsOf: machineIdURL),
              let machineId = VZMacMachineIdentifier(dataRepresentation: idData) else {
            throw NSError(domain: "VM", code: 1, userInfo: [NSLocalizedDescriptionKey: "Thiếu file cấu hình máy ảo."])
        }
        let platform = VZMacPlatformConfiguration()
        platform.hardwareModel = hw
        platform.machineIdentifier = machineId
        platform.auxiliaryStorage = VZMacAuxiliaryStorage(url: auxURL)

        let config = try makeConfiguration(platform: platform, minCPU: 2, minMemory: 4 * 1024 * 1024 * 1024)
        let vm = VZVirtualMachine(configuration: config)
        vm.delegate = self
        return vm
    }
    #endif

    // =====================================================
    // BẬT / TẮT
    // =====================================================
    func start() {
        #if arch(arm64)
        guard isInstalled, virtualMachine == nil || virtualMachine?.state == .stopped else { return }
        do {
            let vm = try loadSavedVM()
            virtualMachine = vm
            vmView.virtualMachine = vm
            set("starting", 0, "Đang bật máy ảo...")

            // Có trạng thái lưu từ lần thoát trước -> khôi phục đúng chỗ đang dùng
            if #available(macOS 14.0, *), FileManager.default.fileExists(atPath: saveURL.path) {
                vm.restoreMachineStateFrom(url: saveURL) { error in
                    DispatchQueue.main.async {
                        try? FileManager.default.removeItem(at: self.saveURL)
                        if error != nil {
                            // Không khôi phục được (ví dụ đổi cấu hình) -> khởi động bình thường
                            self.virtualMachine = nil
                            self.start()
                            return
                        }
                        vm.resume { r in
                            DispatchQueue.main.async {
                                if case .failure(let e) = r { self.set("error", 0, "Không chạy tiếp được: \(e.localizedDescription)") }
                                else { self.set("running") }
                            }
                        }
                    }
                }
                return
            }

            vm.start { result in
                DispatchQueue.main.async {
                    switch result {
                    case .failure(let error):
                        self.virtualMachine = nil
                        self.set("error", 0, "Không bật được máy ảo: \(error.localizedDescription)")
                    case .success:
                        self.set("running")
                    }
                }
            }
        } catch {
            set("error", 0, "Không bật được máy ảo: \(error.localizedDescription)")
        }
        #endif
    }

    // Tắt nhẹ nhàng: gửi lệnh tắt máy cho macOS bên trong (giống bấm nút nguồn)
    func requestStop() {
        guard let vm = virtualMachine, vm.state == .running else { return }
        do {
            try vm.requestStop()
            set("stopping", 0, "Đang yêu cầu macOS trong máy ảo tắt máy...")
        } catch {
            set("running", 0, "macOS trong máy ảo chưa phản hồi lệnh tắt. Thử tắt từ menu Apple bên trong máy ảo.")
        }
    }

    // Tắt ngay (như rút điện) - có thể mất dữ liệu chưa lưu trong máy ảo
    func forceStop() {
        guard let vm = virtualMachine, vm.state != .stopped else { return }
        vm.stop { _ in
            DispatchQueue.main.async {
                self.virtualMachine = nil
                self.vmView.virtualMachine = nil
                self.set("stopped", 0, "Đã tắt máy ảo.")
            }
        }
    }

    // Khi thoát app: tạm dừng + lưu trạng thái (macOS 14 trở lên), lần sau mở lại đúng chỗ.
    // Gọi completion(true) khi xong; false nếu không lưu được.
    func saveForQuit(completion: @escaping (Bool) -> Void) {
        guard let vm = virtualMachine, vm.state == .running else { completion(true); return }
        guard #available(macOS 14.0, *) else { completion(false); return }
        set("saving", 0, "Đang lưu trạng thái máy ảo...")
        vm.pause { r in
            DispatchQueue.main.async {
                if case .failure = r { completion(false); return }
                vm.saveMachineStateTo(url: self.saveURL) { error in
                    DispatchQueue.main.async { completion(error == nil) }
                }
            }
        }
    }

    // ---------- Sự kiện từ máy ảo ----------
    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        DispatchQueue.main.async {
            self.virtualMachine = nil
            self.vmView.virtualMachine = nil
            self.set("stopped", 0, "macOS trong máy ảo đã tắt.")
        }
    }

    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        DispatchQueue.main.async {
            self.virtualMachine = nil
            self.vmView.virtualMachine = nil
            self.set("error", 0, "Máy ảo dừng do lỗi: \(error.localizedDescription)")
        }
    }

    func openShareFolder() {
        NSWorkspace.shared.open(shareDir)
    }

    // =====================================================
    // APP CỦA MÁY ẢO (qua trợ lý Anh 7 chạy bên trong máy ảo)
    // =====================================================
    var agentDir: URL { shareDir.appendingPathComponent(".anh7", isDirectory: true) }

    // Đặt bộ cài trợ lý vào thư mục chia sẻ để cài từ bên trong máy ảo
    func installAgentFiles() {
        guard let src = Bundle.main.url(forResource: "agent", withExtension: nil) else { return }
        let fm = FileManager.default
        let dest = shareDir.appendingPathComponent("Tro ly Anh 7", isDirectory: true)
        try? fm.removeItem(at: dest)
        try? fm.copyItem(at: src, to: dest)
        let command = dest.appendingPathComponent("Cai dat tro ly Anh 7.command")
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: command.path)
    }

    // Trợ lý còn chạy không: file nhịp tim được ghi trong 15 giây gần đây
    var agentOnline: Bool {
        let url = agentDir.appendingPathComponent("agent.json")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(date) < 15
    }

    private var guestApps: [[String: Any]] {
        let url = agentDir.appendingPathComponent("apps.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let apps = obj["apps"] as? [[String: Any]] else { return [] }
        return apps
    }

    // Gói gửi cho Win12: { running, agent, apps: [...] }
    func guestAppsJSON() -> String {
        let payload: [String: Any] = [
            "running": state == "running",
            "agent": agentOnline,
            "apps": guestApps,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return "null" }
        return json
    }

    // Gửi yêu cầu mở app cho trợ lý (chỉ app có trong danh sách trợ lý đã báo)
    func launchGuestApp(_ path: String) {
        guard guestApps.contains(where: { ($0["path"] as? String) == path }) else { return }
        let dir = agentDir.appendingPathComponent("launch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let req = ["path": path]
        if let data = try? JSONSerialization.data(withJSONObject: req) {
            try? data.write(to: dir.appendingPathComponent(UUID().uuidString + ".json"), options: .atomic)
        }
    }

    // Xóa toàn bộ máy ảo (ổ cứng, cấu hình) - không xóa thư mục chia sẻ
    func deleteVM() {
        guard virtualMachine == nil || virtualMachine?.state == .stopped else { return }
        try? FileManager.default.removeItem(at: vmDir)
        try? FileManager.default.createDirectory(at: vmDir, withIntermediateDirectories: true)
        virtualMachine = nil
        set("notInstalled", 0, "Đã xóa máy ảo.")
    }
}
