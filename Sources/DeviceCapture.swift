import AppKit
import AVFoundation
import Combine

final class DeviceCapture: ObservableObject, Identifiable {
    let id: String
    let modelID: String?
    let session: AVCaptureSession?
    let videoLayer: CALayer
    @Published var name: String
    @Published private(set) var customName: String
    @Published private(set) var state: Capture.State
    @Published private(set) var screenSize: CGSize?
    var retry: (() -> Void)?
    var onDisconnect: (() -> Void)?
    private let queue = DispatchQueue(label: "inc.phone.cable.device")
    private var observers: [NSObjectProtocol] = []
    private var stopped = false

    init(id: String, name: String, modelID: String?, session: AVCaptureSession? = nil) {
        self.id = id
        self.name = name
        self.modelID = modelID
        self.session = session
        customName = UserDefaults.standard.string(forKey: "deviceName.\(id)") ?? ""
        state = .connecting(name)
        if let session {
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspect
            videoLayer = preview
        } else {
            let preview = AVSampleBufferDisplayLayer()
            preview.videoGravity = .resizeAspect
            videoLayer = preview
        }
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    var displayName: String { customName.isEmpty ? name : customName }

    func rename(to value: String) {
        customName = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if customName.isEmpty {
            UserDefaults.standard.removeObject(forKey: "deviceName.\(id)")
        } else {
            UserDefaults.standard.set(customName, forKey: "deviceName.\(id)")
        }
    }

    var canvasSize: CGSize {
        let size: CGSize?
        if case .live = state { size = screenSize } else { size = nil }
        return DeviceFrame.matching(modelID: modelID, screenSize: size ?? CGSize(width: 1170, height: 2532)).canvasSize
    }

    func startIOS(_ device: AVCaptureDevice) {
        queue.async { [self] in
            guard !stopped, let session else { return }
            if observers.isEmpty {
                observers.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] notification in
                    let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
                    self?.queue.async {
                        guard let self, !self.stopped else { return }
                        if !device.isConnected || device.isSuspended || error?.code == .deviceWasDisconnected || error?.code == .deviceNotConnected {
                            self.onDisconnect?()
                        } else {
                            session.stopRunning()
                            self.publish(.failed(error?.localizedDescription ?? "The screen connection was interrupted."))
                        }
                    }
                })
                observers.append(NotificationCenter.default.addObserver(forName: AVCaptureInput.Port.formatDescriptionDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
                    self?.queue.async { self?.updateScreenSize() }
                })
            }
            publish(.connecting(device.localizedName))
            session.stopRunning()
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    publish(.failed("Screen unavailable. Close other capture apps and try again."))
                    return
                }
                session.addInput(input)
                session.commitConfiguration()
                session.startRunning()
                guard session.isRunning else {
                    publish(.failed("Unlock your iPhone and check its USB cable."))
                    return
                }
                publish(.live(device.localizedName))
                updateScreenSize()
            } catch {
                session.commitConfiguration()
                publish(.failed(error.localizedDescription))
            }
        }
    }

    func receiveAndroid(_ event: AndroidCapture.Event) {
        switch event {
        case let .frame(sample):
            guard let preview = videoLayer as? AVSampleBufferDisplayLayer,
                  let format = CMSampleBufferGetFormatDescription(sample) else { return }
            let dimensions = CMVideoFormatDescriptionGetDimensions(format)
            let size = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
            if screenSize != size { screenSize = size }
            if state != .live(name) { state = .live(name) }
            if preview.requiresFlushToResumeDecoding { preview.flush() }
            preview.enqueue(sample)
        case .waiting:
            (videoLayer as? AVSampleBufferDisplayLayer)?.flushAndRemoveImage()
            screenSize = nil
            state = .connecting(name)
        case .authorize:
            state = .androidAuthorization
        case .connecting:
            state = .connecting(name)
        case let .failed(message):
            state = .failed(message)
        }
    }

    func stop(wait: Bool = false) {
        let stop = { [self] in
            stopped = true
            session?.stopRunning()
        }
        if wait { queue.sync(execute: stop) } else { queue.async(execute: stop) }
    }

    private func updateScreenSize() {
        guard let session, session.isRunning,
              let port = session.inputs.flatMap(\.ports).first(where: { $0.mediaType == .video }),
              let format = port.formatDescription else { return }
        let size = CMVideoFormatDescriptionGetPresentationDimensions(format, usePixelAspectRatio: true, useCleanAperture: true)
        guard size.width > 0, size.height > 0 else { return }
        DispatchQueue.main.async {
            if self.screenSize != size { self.screenSize = size }
        }
    }

    private func publish(_ state: Capture.State) {
        DispatchQueue.main.async { self.state = state }
    }
}
