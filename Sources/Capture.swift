import AppKit
import AVFoundation
import Combine
import CoreMediaIO
import SwiftUI

final class Capture: ObservableObject {
    enum State: Equatable {
        case setup
        case waiting
        case connecting(String)
        case live(String)
        case permission
        case androidAuthorization
        case failed(String)
    }

    @Published private(set) var state: State = .waiting
    @Published private(set) var devices: [DeviceCapture] = []
    @Published private(set) var requestingPermission = false
    private let android: AndroidCapture
    private let preferences: UserDefaults
    private let authorizationStatus: () -> AVAuthorizationStatus
    private var deviceOrder: [String]
    private let queue = DispatchQueue(label: "inc.phone.cable.capture")
    private var discovery: AVCaptureDevice.DiscoverySession?
    private var observers: [NSObjectProtocol] = []
    private var iosDevices: [String: DeviceCapture] = [:]
    private var androidDevices: [String: DeviceCapture] = [:]
    private var subscriptions: [String: AnyCancellable] = [:]
    private var timer: DispatchSourceTimer?

    init(android: AndroidCapture = AndroidCapture(), preferences: UserDefaults = .standard,
         authorizationStatus: @escaping () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .video) }) {
        self.android = android
        self.preferences = preferences
        self.authorizationStatus = authorizationStatus
        deviceOrder = preferences.stringArray(forKey: "deviceOrder") ?? []
        android.onDevices = { [weak self] devices in
            self?.queue.async { self?.refreshAndroid(devices) }
        }
        android.onEvent = { [weak self] serial, event in
            self?.queue.async {
                guard let device = self?.androidDevices[serial] else { return }
                DispatchQueue.main.async { device.receiveAndroid(event) }
            }
        }
    }

    func start() {
        android.start()
        queue.async { [self] in
            guard discovery == nil else { return }
            switch authorizationStatus() {
            case .authorized:
                break
            case .notDetermined:
                publish(.setup)
                return
            default:
                publish(.permission)
                return
            }
            var address = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            var allow: UInt32 = 1
            let result = CMIOObjectSetPropertyData(
                CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil,
                UInt32(MemoryLayout.size(ofValue: allow)), &allow
            )
            guard result == noErr else {
                publish(.failed("macOS couldn’t enable iPhone screen capture (\(result))."))
                return
            }
            for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                    self?.queue.async { self?.refreshIOS() }
                })
            }
            discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .muxed, position: .unspecified)
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: 2)
            timer.setEventHandler { [weak self] in self?.refreshIOS() }
            self.timer = timer
            timer.resume()
            publish(.waiting)
        }
    }

    func requestPermission() {
        guard !requestingPermission else { return }
        requestingPermission = true
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                self.requestingPermission = false
                if granted { self.start() } else { self.state = .permission }
            }
        }
    }

    func retry() {
        start()
        queue.async { [self] in refreshIOS() }
    }

    func moveDevice(_ id: String, to targetID: String) {
        guard let source = devices.firstIndex(where: { $0.id == id }),
              let target = devices.firstIndex(where: { $0.id == targetID }), source != target else { return }
        devices.move(fromOffsets: IndexSet(integer: source), toOffset: target > source ? target + 1 : target)
        let visible = Set(devices.map(\.id))
        var reordered = devices.map(\.id).makeIterator()
        deviceOrder = deviceOrder.map { visible.contains($0) ? reordered.next()! : $0 }
        preferences.set(deviceOrder, forKey: "deviceOrder")
    }

    func stop(completion: @escaping () -> Void = {}) {
        let stopped = DispatchGroup()
        stopped.enter()
        android.stop { stopped.leave() }
        stopped.enter()
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.removeAll()
            discovery = nil
            iosDevices.values.forEach { $0.stop(wait: true) }
            iosDevices.removeAll()
            androidDevices.values.forEach { $0.stop(wait: true) }
            androidDevices.removeAll()
            subscriptions.removeAll()
            publishDevices()
            stopped.leave()
        }
        stopped.notify(queue: .main, execute: completion)
    }

    private func refreshIOS() {
        let connected = discovery?.devices.filter { $0.isConnected && !$0.isSuspended } ?? []
        let ids = Set(connected.map(\.uniqueID))
        var changed = false
        for id in Array(iosDevices.keys) where !ids.contains(id) {
            if let device = iosDevices.removeValue(forKey: id) {
                device.stop()
                subscriptions.removeValue(forKey: device.id)
                changed = true
            }
        }
        for source in connected.sorted(by: { $0.uniqueID < $1.uniqueID }) where iosDevices[source.uniqueID] == nil {
            let device = DeviceCapture(id: "ios:\(source.uniqueID)", name: source.localizedName, modelID: source.modelID, session: AVCaptureSession())
            device.retry = { [weak device] in device?.startIOS(source) }
            device.onDisconnect = { [weak self, weak device] in
                self?.queue.async {
                    guard let self, let device, self.iosDevices[source.uniqueID] === device else { return }
                    self.iosDevices.removeValue(forKey: source.uniqueID)
                    self.subscriptions.removeValue(forKey: device.id)
                    device.stop()
                    self.publishDevices()
                }
            }
            iosDevices[source.uniqueID] = device
            observe(device)
            device.startIOS(source)
            changed = true
        }
        if changed { publishDevices() }
    }

    private func refreshAndroid(_ connected: [AndroidDevice]) {
        let ids = Set(connected.map(\.serial))
        for id in Array(androidDevices.keys) where !ids.contains(id) {
            if let device = androidDevices.removeValue(forKey: id) {
                device.stop()
                subscriptions.removeValue(forKey: device.id)
            }
        }
        for source in connected {
            let device: DeviceCapture
            if let existing = androidDevices[source.serial] {
                device = existing
            } else {
                device = DeviceCapture(id: "android:\(source.serial)", name: source.name, modelID: "Android")
                device.retry = { [weak self] in self?.android.retry(source.serial) }
                androidDevices[source.serial] = device
                observe(device)
            }
            DispatchQueue.main.async {
                if device.name != source.name { device.name = source.name }
                if !source.authorized { device.receiveAndroid(.authorize) }
            }
        }
        publishDevices()
    }

    private func observe(_ device: DeviceCapture) {
        subscriptions[device.id] = device.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    private func publishDevices() {
        let connected = Array(iosDevices.values) + Array(androidDevices.values)
        DispatchQueue.main.async {
            let ids = Set(connected.map(\.id))
            let existing = Set(self.devices.map(\.id))
            let devices = self.devices.filter { ids.contains($0.id) } + connected.filter { !existing.contains($0.id) }.sorted { $0.id < $1.id }
            for device in devices where !self.deviceOrder.contains(device.id) {
                self.deviceOrder.append(device.id)
            }
            self.devices = devices.sorted { self.deviceOrder.firstIndex(of: $0.id)! < self.deviceOrder.firstIndex(of: $1.id)! }
            self.preferences.set(self.deviceOrder, forKey: "deviceOrder")
        }
    }

    private func publish(_ state: State) {
        DispatchQueue.main.async { self.state = state }
    }
}

struct ScreenPreview: NSViewRepresentable {
    let videoLayer: CALayer
    let screenSize: CGSize?
    let modelID: String?

    func makeNSView(context: Context) -> PreviewView {
        PreviewView(videoLayer: videoLayer)
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        nsView.setScreenSize(screenSize, modelID: modelID)
    }
}

final class PreviewView: NSView {
    private let videoLayer: CALayer
    private let body = CAShapeLayer()
    private let screenMask = CAShapeLayer()
    private var screenSize: CGSize?
    private var modelID: String?

    override var isFlipped: Bool { true }

    init(videoLayer: CALayer) {
        self.videoLayer = videoLayer
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.075, green: 0.082, blue: 0.087, alpha: 1).cgColor
        body.fillColor = NSColor(white: 0.025, alpha: 1).cgColor
        body.strokeColor = NSColor(white: 0.42, alpha: 1).cgColor
        body.lineWidth = 1
        body.shadowColor = NSColor.black.cgColor
        body.shadowOpacity = 0.35
        body.shadowRadius = 10
        body.shadowOffset = CGSize(width: 0, height: 5)
        layer?.addSublayer(body)
        layer?.addSublayer(videoLayer)
        videoLayer.mask = screenMask
    }

    required init?(coder: NSCoder) { nil }

    func setScreenSize(_ size: CGSize?, modelID: String? = nil) {
        guard screenSize != size || self.modelID != modelID else { return }
        screenSize = size
        self.modelID = modelID
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let screenSize {
            let frame = DeviceFrame.matching(modelID: modelID, screenSize: screenSize)
            let layout = frame.layout(in: bounds)
            body.frame = bounds
            body.path = frame.path(in: layout.body, scale: layout.scale, outer: true)
            body.shadowPath = body.path
            videoLayer.frame = layout.screen
            screenMask.frame = videoLayer.bounds
            screenMask.path = frame.path(in: videoLayer.bounds, scale: layout.scale)
            body.isHidden = false
            videoLayer.isHidden = false
        } else {
            body.isHidden = true
            videoLayer.isHidden = true
        }
        CATransaction.commit()
    }
}
