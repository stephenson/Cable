import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

@main
struct CableApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var capture = Capture()
    @StateObject private var updater = Updater()

    var body: some Scene {
        Window("Cable", id: "viewer") {
            ContentView(capture: capture)
                .preferredColorScheme(.dark)
                .onAppear {
                    delegate.capture = capture
                    capture.start()
                }
        }
        .defaultSize(width: 420, height: 700)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Cable") { showAboutCable() }
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) {
                Button("Allow iPhone Screen Access") {
                    if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                    } else {
                        capture.requestPermission()
                    }
                }
                Button("Connection Help") {
                    let alert = NSAlert()
                    alert.messageText = "Just plug in."
                    alert.informativeText = "iPhone: unlock and tap Trust.\nAndroid: enable USB debugging and tap Allow. Setup steps are in About Cable.\n\nUse a USB data cable. Nothing is recorded."
                    alert.runModal()
                }
            }
        }
    }
}

func showAboutCable() {
    let text = "Android setup\n1. About phone → Build number: tap 7 times.\n2. Developer options → USB debugging: on.\n3. Plug in, unlock, and tap Allow.\n\nadb + scrcpy · Apache 2.0"
    let credits = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13)])
    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var capture: Capture?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let capture else { return .terminateNow }
        capture.stop { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct ContentView: View {
    @ObservedObject var capture: Capture
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cableConnected = true
    private let mint = Color(red: 0.48, green: 0.88, blue: 0.73)

    var body: some View {
        ZStack {
            Color(red: 0.075, green: 0.082, blue: 0.087)
            if hasDevices {
                DeviceWall(devices: capture.devices, arrangement: ScreenArrangement(canvases: capture.devices.map(\.canvasSize)), move: capture.moveDevice)
            } else {
                VStack(spacing: 0) {
                    Spacer(minLength: 24)
                    phoneIllustration
                    Spacer().frame(height: 40)
                    status
                    Spacer(minLength: 24)
                    if capture.state != .waiting {
                        Label("Only a screen. Nothing recorded.", systemImage: "lock.shield")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(.bottom, 24)
                    }
                }
                .padding(.horizontal, 28)
            }
        }
        .frame(minWidth: hasDevices ? 180 : 360, minHeight: hasDevices ? 180 : 600)
        .background(WindowFit(canvas: ScreenArrangement(canvases: capture.devices.map(\.canvasSize)).canvasSize, deviceCount: capture.devices.count))
        .navigationTitle(title)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if capture.state == .permission && AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
                capture.retry()
            }
        }
    }

    private var hasDevices: Bool { !capture.devices.isEmpty }

    private var title: String {
        if capture.devices.count == 1 { return capture.devices[0].displayName }
        return hasDevices ? "\(capture.devices.count) devices" : "Cable"
    }

    private var phoneIllustration: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 28)
                    .fill(.white.opacity(0.025))
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(.white.opacity(0.24), lineWidth: 2)
                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(width: 38, height: 7)
                    .padding(.top, 15)
                Image(systemName: "cable.connector")
                    .font(.system(size: 28, weight: .ultraLight))
                    .foregroundStyle(mint.opacity(0.8))
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 132, height: 252)
            .background(Color(red: 0.075, green: 0.082, blue: 0.087), in: RoundedRectangle(cornerRadius: 28))
            .zIndex(1)
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.white.opacity(0.5))
                    .frame(width: 10, height: 8)
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(0.35))
                    .frame(width: 16, height: 23)
                Rectangle()
                    .fill(.white.opacity(0.16))
                    .frame(width: 3, height: 35)
            }
            .offset(y: cableConnected ? -8 : 24)
        }
        .accessibilityHidden(true)
        .task(id: capture.state) {
            cableConnected = true
            guard capture.state == .waiting, !reduceMotion else { return }
            cableConnected = false
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            withAnimation(.easeInOut(duration: 0.85)) {
                cableConnected = true
            }
        }
    }

    @ViewBuilder private var status: some View {
        VStack(spacing: 14) {
            switch capture.state {
            case .setup:
                Text("IPHONE · SCREEN ACCESS")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(mint)
                Text("One small permission.")
                    .font(.system(size: 25, weight: .semibold))
                    .tracking(-0.7)
                Text("macOS calls this Camera access.\nCable uses it to show your iPhone’s screen.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.65))
                Button(capture.requestingPermission ? "Waiting for permission…" : "Allow screen access") {
                    capture.requestPermission()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(mint, in: RoundedRectangle(cornerRadius: 9))
                .foregroundStyle(.black)
                .disabled(capture.requestingPermission)
                .opacity(capture.requestingPermission ? 0.65 : 1)
                .padding(.top, 4)
                Text("Android? See About Cable. No Camera access needed.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            case .waiting:
                Text("Connect via USB to see your phone’s screen")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.65))
            case let .connecting(name):
                ProgressView().controlSize(.small)
                Text("Connecting to \(name)…").font(.headline)
                Text("Keep your phone unlocked.").foregroundStyle(.secondary)
            case .androidAuthorization:
                Text("Tap Allow on your phone.").font(.title3.weight(.semibold))
                Text("Allow USB debugging to show its screen.")
                    .font(.callout).foregroundStyle(.secondary)
            case .permission:
                Text("Let’s turn on access.").font(.title3.weight(.semibold))
                Text("iPhone: turn on Cable in Camera settings.\nAndroid needs no Camera access.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Open Camera Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                }
                Button("Try Again") { capture.retry() }
            case let .failed(message):
                Text("Let’s reconnect.").font(.title3.weight(.semibold))
                Text(message).font(.callout).foregroundStyle(.secondary)
                Button("Try Again") { capture.retry() }
            case .live:
                EmptyView()
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct DeviceDrag: Codable, Transferable {
    let id: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "inc.phone.cable.device", conformingTo: .data))
            .visibility(.ownProcess)
    }
}

struct DeviceWall: View {
    let devices: [DeviceCapture]
    let arrangement: ScreenArrangement
    let move: (String, String) -> Void
    @State private var dropTarget: String?

    var body: some View {
        GeometryReader { geometry in
            let scale = arrangement.scale(in: geometry.size)
            HStack(spacing: 0) {
                ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                    VStack(spacing: 0) {
                        DeviceTile(device: device)
                            .overlay {
                                Button { NSApp.keyWindow?.makeFirstResponder(nil) } label: {
                                    Color.clear.contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .draggable(DeviceDrag(id: device.id)) { Text(device.displayName).padding(10) }
                                .accessibilityLabel(device.displayName)
                                .accessibilityHint("Drag to reorder")
                            }
                            .frame(height: 700 * scale)
                        DeviceName(device: device)
                            .frame(height: arrangement.labelHeight, alignment: .top)
                    }
                    .frame(width: arrangement.sizes[index].width * scale)
                    .overlay {
                        if dropTarget == device.id {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color(red: 0.48, green: 0.88, blue: 0.73).opacity(0.65), lineWidth: 1)
                                .padding(3)
                                .allowsHitTesting(false)
                        }
                    }
                    .dropDestination(for: DeviceDrag.self) { items, _ in
                        guard let item = items.first, devices.contains(where: { $0.id == item.id }), item.id != device.id else { return false }
                        move(item.id, device.id)
                        return true
                    } isTargeted: { active in
                        if active { dropTarget = device.id } else if dropTarget == device.id { dropTarget = nil }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

struct DeviceName: View {
    @ObservedObject var device: DeviceCapture
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if editing {
                TextField(device.name, text: $draft)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    .accessibilityLabel("Device name for \(device.name)")
                    .onSubmit { save() }
                    .onExitCommand { editing = false }
                    .task {
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        focused = true
                    }
            } else {
                Button {
                    draft = device.displayName
                    editing = true
                } label: {
                    Text(device.displayName)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.55))
                .help("Click to rename")
                .accessibilityLabel("Rename \(device.displayName)")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 6)
        .onChange(of: focused) { _, focused in
            if !focused { save() }
        }
    }

    private func save() {
        guard editing else { return }
        device.rename(to: draft)
        editing = false
    }
}

struct DeviceTile: View {
    @ObservedObject var device: DeviceCapture

    var body: some View {
        ZStack {
            if case .live = device.state, device.screenSize != nil {
                ScreenPreview(videoLayer: device.videoLayer, screenSize: device.screenSize, modelID: device.modelID)
                    .accessibilityLabel("Live screen of \(device.displayName)")
            } else {
                GeometryReader { geometry in
                    VStack(spacing: 16) {
                        Image(systemName: "iphone")
                            .font(.system(size: 64, weight: .ultraLight))
                            .foregroundStyle(.white.opacity(0.3))
                        switch device.state {
                        case .androidAuthorization:
                            Text("Tap Allow on your phone.")
                            Text("Allow USB debugging.").foregroundStyle(.secondary)
                        case let .failed(message):
                            Text(message)
                            Button("Try Again") { device.retry?() }
                        default:
                            ProgressView().controlSize(.small)
                            Text("Connecting…").foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .padding(20)
                    .frame(width: 280, height: 420)
                    .scaleEffect(min(1, geometry.size.width / 280, geometry.size.height / 420))
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
    }
}
