import AVFoundation
import Darwin
@testable import CableTests

@main
struct AndroidCaptureTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CableCaptureTests-\(UUID())")
        let resources = root.appendingPathComponent("Android")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let listener = socket(AF_INET, SOCK_STREAM, 0)
        precondition(listener >= 0)
        defer { close(listener) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        precondition(bound == 0 && listen(listener, 1) == 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { precondition(getsockname(listener, $0, &length) == 0) }
        }
        let script = """
        #!/bin/bash
        ROOT="$(dirname "$0")"
        if [[ "$1" == devices ]]; then
            COUNT=$(cat "$ROOT/count" 2>/dev/null || echo 0)
            COUNT=$((COUNT + 1))
            echo "$COUNT" > "$ROOT/count"
            if [[ "$COUNT" -gt 1 ]]; then sleep 2; fi
            printf 'List of devices attached\\nTEST device usb:1 model:Test_Phone\\n'
            echo "$COUNT" > "$ROOT/finished"
        elif [[ "$3" == forward && "$4" == tcp:0 ]]; then
            echo \(UInt16(bigEndian: address.sin_port))
        elif [[ "$3" == shell ]]; then
            exec sleep 30
        fi
        """
        let adb = resources.appendingPathComponent("adb")
        try script.write(to: adb, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: adb.path)
        let server = DispatchGroup()
        server.enter()
        DispatchQueue.global().async {
            defer { server.leave() }
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            defer { close(client) }
            var noSignal: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            func write(_ data: Data) -> Bool {
                data.withUnsafeBytes { bytes in
                    var sent = 0
                    while sent < data.count {
                        let count = send(client, bytes.baseAddress!.advanced(by: sent), data.count - sent, 0)
                        guard count > 0 else { return false }
                        sent += count
                    }
                    return true
                }
            }
            func packet(_ encoded: String, configuration: Bool) -> Bool {
                let data = Data(base64Encoded: encoded)!
                var size = UInt32(data.count).bigEndian
                var header = Data(repeating: 0, count: 8)
                header[0] = configuration ? 0x80 : 0
                withUnsafeBytes(of: &size) { header.append(contentsOf: $0) }
                return write(header + data)
            }
            guard write(Data([0])), packet("AAAAAWdCwAvaGFbARAAAAwAEAAADAMo8UKqAAAAAAWjOD8g=", configuration: true) else { return }
            for _ in 0..<300 {
                guard packet("AAABZYiEOhGKAAIRccAAQDI4AAg0ycnJycnXXXXXXXXXXXXXXXXXXXXXXXXgAAABZQ+IhDoRigACEXHAAEAyOAAINMnJycnJ1111111111111111111111114A==", configuration: false) else { return }
                Thread.sleep(forTimeInterval: 0.04)
            }
        }

        let capture = AndroidCapture(resources: root)
        let lock = NSLock()
        var frames: [TimeInterval] = []
        var stopped = false
        var eventsAfterStop = 0
        capture.onDevices = { _ in
            lock.lock()
            if stopped { eventsAfterStop += 1 }
            lock.unlock()
        }
        capture.onEvent = { _, event in
            lock.lock()
            defer { lock.unlock() }
            if stopped { eventsAfterStop += 1 }
            if case .frame = event { frames.append(ProcessInfo.processInfo.systemUptime) }
        }
        func wait(_ condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(12)
            while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
            precondition(condition(), "Timed out waiting for fake USB transport")
        }
        func count(_ file: String) -> Int {
            Int((try? String(contentsOf: resources.appendingPathComponent(file), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
        }
        capture.start()
        wait { count("finished") >= 2 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        lock.lock()
        let delivered = frames
        lock.unlock()
        precondition(delivered.count > 40)
        let gap = zip(delivered, delivered.dropFirst()).map { $1 - $0 }.max()!
        precondition(gap < 0.5, "Slow device enumeration stalled a live stream for \(gap)s")
        print("PASS: live Android frames continue during two-second USB discovery (largest gap \(gap)s)")

        wait { count("count") >= 3 }
        let start = ProcessInfo.processInfo.systemUptime
        var cleanupFinished = false
        capture.stop { cleanupFinished = true }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        precondition(elapsed < 0.5, "Stopping must not block the caller on adb discovery")
        wait { cleanupFinished }
        precondition(ProcessInfo.processInfo.systemUptime - start < 0.5, "Cleanup must finish without waiting for device discovery")
        lock.lock()
        stopped = true
        lock.unlock()
        RunLoop.main.run(until: Date().addingTimeInterval(2.2))
        lock.lock()
        let lateEvents = eventsAfterStop
        lock.unlock()
        precondition(lateEvents == 0, "An in-flight discovery must not revive devices after stop")
        precondition(server.wait(timeout: .now() + 1) == .success)
        print("PASS: stopping is nonblocking and late discovery cannot revive streams")
    }
}
