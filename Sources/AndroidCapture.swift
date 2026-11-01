import AVFoundation
import Darwin

final class AndroidCapture {
    enum Event {
        case waiting
        case authorize
        case connecting
        case frame(CMSampleBuffer)
        case failed(String)
    }

    var onDevices: (([AndroidDevice]) -> Void)?
    var onEvent: ((String, Event) -> Void)?
    private let queue = DispatchQueue(label: "inc.phone.cable.android")
    private let discoveryQueue = DispatchQueue(label: "inc.phone.cable.android.discovery")
    private let bridge: AndroidBridge
    private var timer: DispatchSourceTimer?
    private var streams: [String: AndroidStream] = [:]
    private var devices: [AndroidDevice] = []
    private var generation = UUID()
    private var refreshing = false

    init(resources: URL = Bundle.main.resourceURL!) {
        bridge = AndroidBridge(resources: resources)
    }

    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            generation = UUID()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: 2)
            timer.setEventHandler { [weak self] in self?.refresh() }
            self.timer = timer
            timer.resume()
        }
    }

    func retry(_ serial: String) {
        queue.async { [self] in
            streams[serial]?.stop()
            streams.removeValue(forKey: serial)
            refresh()
        }
    }

    func stop(completion: @escaping () -> Void = {}) {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            generation = UUID()
            refreshing = false
            let stopped = DispatchGroup()
            for stream in streams.values {
                stopped.enter()
                stream.stop { stopped.leave() }
            }
            streams.removeAll()
            devices = []
            stopped.notify(queue: .main, execute: completion)
        }
    }

    private func refresh() {
        guard timer != nil, !refreshing else { return }
        refreshing = true
        let token = generation
        discoveryQueue.async { [weak self, bridge] in
            let output = bridge.command(["devices", "-l"])
            self?.queue.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.refreshing = false
                if let output { self.refreshDevices(output) }
            }
        }
    }

    private func refreshDevices(_ output: String) {
        let connected = AndroidDevice.connectedUSBDevices(in: output)
        if devices != connected {
            devices = connected
            onDevices?(connected)
        }
        let authorized = Set(connected.filter(\.authorized).map(\.serial))
        for serial in Array(streams.keys) where !authorized.contains(serial) {
            streams.removeValue(forKey: serial)?.stop()
        }
        for device in connected where device.authorized {
            if streams[device.serial] == nil {
                let stream = AndroidStream(bridge: bridge, device: device)
                streams[device.serial] = stream
                stream.onEvent = { [weak self, weak stream] event in
                    self?.queue.async {
                        guard let self, let stream, self.streams[device.serial] === stream else { return }
                        self.onEvent?(device.serial, event)
                    }
                }
            }
            streams[device.serial]?.start()
        }
    }
}

private struct AndroidBridge {
    let resources: URL
    var adb: URL { resources.appendingPathComponent("Android/adb") }
    var server: URL { resources.appendingPathComponent("Android/scrcpy-server") }

    func command(_ arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = adb
        task.arguments = arguments
        let output = Pipe()
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in finished.signal() }
        do { try task.run() } catch { return nil }
        guard finished.wait(timeout: .now() + 8) == .success else {
            task.terminate()
            return nil
        }
        guard task.terminationStatus == 0 else { return nil }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}

private final class AndroidStream {
    var onEvent: ((AndroidCapture.Event) -> Void)?
    private let queue = DispatchQueue(label: "inc.phone.cable.android.stream")
    private let reader = DispatchQueue(label: "inc.phone.cable.android.video")
    private let bridge: AndroidBridge
    private let device: AndroidDevice
    private var process: Process?
    private var descriptor: Int32 = -1
    private var port: String?
    private var generation = UUID()
    private var stopped = false
    private var lastStatus: String?
    private var retryAfter = Date.distantPast

    init(bridge: AndroidBridge, device: AndroidDevice) {
        self.bridge = bridge
        self.device = device
    }

    func start() {
        queue.async { [self] in
            guard !stopped, process?.isRunning != true, Date() >= retryAfter else { return }
            disconnect()
            connect()
        }
    }

    func stop(completion: @escaping () -> Void = {}) {
        queue.async { [self] in
            stopped = true
            disconnect()
            completion()
        }
    }

    private func status(_ key: String, _ event: AndroidCapture.Event) {
        guard lastStatus != key else { return }
        lastStatus = key
        onEvent?(event)
    }

    private func connect() {
        status("connecting", .connecting)
        let token = UUID()
        generation = token
        let scid = UInt32.random(in: 1...0x7fffffff)
        let socketName = String(format: "scrcpy_%08x", scid)
        let remote = "/data/local/tmp/cable-\(scid).jar"
        guard bridge.command(["-s", device.serial, "push", bridge.server.path, remote]) != nil,
              let forwarded = bridge.command(["-s", device.serial, "forward", "tcp:0", "localabstract:\(socketName)"])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let portNumber = UInt16(forwarded), portNumber > 0 else {
            connectionFailed()
            return
        }
        port = forwarded
        let task = Process()
        task.executableURL = bridge.adb
        task.arguments = ["-s", device.serial, "shell", "CLASSPATH=\(remote)", "app_process", "/",
                          "com.genymobile.scrcpy.Server", "3.3.3", "scid=\(String(scid, radix: 16))",
                          "tunnel_forward=true", "audio=false", "control=false", "video_codec=h264",
                          "max_size=2400", "max_fps=60", "send_device_meta=false", "send_codec_meta=false",
                          "power_on=false", "clipboard_autosync=false"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        process = task
        do { try task.run() } catch {
            connectionFailed()
            return
        }
        reader.async { [weak self] in
            self?.readStream(port: portNumber, token: token)
        }
    }

    private func connectionFailed() {
        disconnect()
        retryAfter = Date().addingTimeInterval(5)
        status("failed", .failed("Unlock your Android phone and allow USB debugging. Android 5 or later is required."))
    }

    private func disconnect() {
        generation = UUID()
        if descriptor >= 0 {
            shutdown(descriptor, SHUT_RDWR)
            descriptor = -1
        }
        if let process, process.isRunning { process.terminate() }
        process = nil
        if let port {
            _ = bridge.command(["-s", device.serial, "forward", "--remove", "tcp:\(port)"])
        }
        port = nil
    }

    private func readStream(port: UInt16, token: UUID) {
        var socket: Int32 = -1
        for _ in 0..<50 {
            guard queue.sync(execute: { generation == token }) else { return }
            socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard socket >= 0 else { break }
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            var timeout = timeval(tv_sec: 1, tv_usec: 0)
            setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            let connected = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                }
            }
            if connected, readExactly(1, from: socket) == Data([0]) { break }
            close(socket)
            socket = -1
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard socket >= 0 else {
            queue.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.connectionFailed()
            }
            return
        }
        let accepted = queue.sync { () -> Bool in
            guard generation == token else { return false }
            descriptor = socket
            return true
        }
        guard accepted else { close(socket); return }
        defer {
            queue.sync {
                if generation == token {
                    disconnect()
                    retryAfter = Date().addingTimeInterval(2)
                    status("waiting", .waiting)
                }
            }
            close(socket)
        }
        var timeout = timeval(tv_sec: 0, tv_usec: 0)
        setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var video = AndroidVideo()
        while let header = readExactly(12, from: socket) {
            let size = header.suffix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard size > 0, size <= 16 * 1024 * 1024,
                  let packet = readExactly(Int(size), from: socket) else { break }
            guard let sample = video.sample(packet: packet, configuration: header[0] & 0x80 != 0) else { continue }
            queue.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.lastStatus = "live"
                self.onEvent?(.frame(sample))
            }
        }
    }

    private func readExactly(_ count: Int, from descriptor: Int32) -> Data? {
        var data = Data(count: count)
        let success = data.withUnsafeMutableBytes { buffer -> Bool in
            var received = 0
            while received < count {
                let length = recv(descriptor, buffer.baseAddress!.advanced(by: received), count - received, 0)
                if length < 0 && errno == EINTR { continue }
                guard length > 0 else { return false }
                received += length
            }
            return true
        }
        return success ? data : nil
    }
}
