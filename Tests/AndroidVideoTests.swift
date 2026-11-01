import AVFoundation
@testable import CableTests

@main
struct AndroidVideoTests {
    static func main() {
        let devices = AndroidDevice.connectedUSBDevices(in: """
        List of devices attached
        Z123 device usb:123 product:panther model:Pixel_7 device:panther transport_id:1
        A456 unauthorized usb:456 transport_id:2
        192.168.1.4:5555 device product:panther model:Wireless_Pixel transport_id:3
        emulator-5554 device product:sdk model:Emulator transport_id:4
        B789 offline usb:789 transport_id:5
        """)
        precondition(devices == [AndroidDevice(serial: "A456", authorized: false, name: "Android"),
                                 AndroidDevice(serial: "Z123", authorized: true, name: "Pixel 7")])
        precondition(AndroidDevice.connectedUSBDevices(in: "List of devices attached\n").isEmpty)
        print("PASS: only connected USB Android devices are selected, including pending authorization")

        let portraitConfiguration = Data(base64Encoded: "AAAAAWdCwAvaGFbARAAAAwAEAAADAMo8UKqAAAAAAWjOD8g=")!
        let portraitFrame = Data(base64Encoded: "AAABZYiEOhGKAAIRccAAQDI4AAg0ycnJycnXXXXXXXXXXXXXXXXXXXXXXXXgAAABZQ+IhDoRigACEXHAAEAyOAAINMnJycnJ1111111111111111111111114A==")!
        let landscapeConfiguration = Data(base64Encoded: "AAAAAWdCwAvaCjbARAAAAwAEAAADAMo8UKqAAAAAAWjOD8g=")!
        let landscapeFrame = Data(base64Encoded: "AAABZYiEOhGKAAISkcAAQs44AAguScnJycnJycnJ111111111111111111111111111111111111111111111111114=")!
        var video = AndroidVideo()
        precondition(video.sample(packet: portraitFrame, configuration: false) == nil)
        precondition(video.sample(packet: portraitConfiguration, configuration: true) == nil)
        let portrait = video.sample(packet: portraitFrame, configuration: false)!
        let dimensions = CMVideoFormatDescriptionGetDimensions(CMSampleBufferGetFormatDescription(portrait)!)
        precondition(dimensions.width == 96 && dimensions.height == 160)
        let attachments = CMSampleBufferGetSampleAttachmentsArray(portrait, createIfNecessary: false)! as NSArray
        precondition((attachments[0] as! NSDictionary)[kCMSampleAttachmentKey_DisplayImmediately] as? Bool == true)
        let block = CMSampleBufferGetDataBuffer(portrait)!
        var firstLength: UInt32 = 0
        precondition(CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: 4, destination: &firstLength) == noErr)
        precondition(UInt32(bigEndian: firstLength) == 42)
        precondition(CMSampleBufferGetTotalSampleSize(portrait) == portraitFrame.count + 2)
        _ = video.sample(packet: landscapeConfiguration, configuration: true)
        let landscape = video.sample(packet: landscapeFrame, configuration: false)!
        let rotated = CMVideoFormatDescriptionGetDimensions(CMSampleBufferGetFormatDescription(landscape)!)
        precondition(rotated.width == 160 && rotated.height == 96)
        _ = video.sample(packet: Data([0, 0, 1]), configuration: true)
        precondition(video.sample(packet: portraitFrame, configuration: false) == nil)
        print("PASS: H.264 frames preserve dimensions, rotate, and reset after invalid configuration")

        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        let android = AndroidCapture()
        let suite = "CableTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let capture = Capture(android: android, preferences: preferences)
        let firstSource = AndroidDevice(serial: "A", authorized: true, name: "Pixel 7")
        let pending = AndroidDevice(serial: "B", authorized: false, name: "Android")
        android.onDevices?([firstSource, pending])
        settle()
        precondition(capture.devices.map(\.id) == ["android:A", "android:B"])
        let first = capture.devices[0]
        let second = capture.devices[1]
        precondition(second.state == .androidAuthorization)
        android.onEvent?("A", .frame(portrait))
        settle()
        precondition(first.screenSize == CGSize(width: 96, height: 160) && second.screenSize == nil)
        android.onDevices?([firstSource, AndroidDevice(serial: "B", authorized: true, name: "Galaxy")])
        android.onEvent?("B", .frame(landscape))
        settle()
        precondition(first.state == .live("Pixel 7") && second.state == .live("Galaxy"))
        precondition(first.videoLayer !== second.videoLayer)
        precondition(second.screenSize == CGSize(width: 160, height: 96))
        capture.moveDevice(first.id, to: second.id)
        precondition(capture.devices[0] === second && capture.devices[1] === first)
        android.onEvent?("A", .failed("Connection interrupted"))
        settle()
        precondition(second.state == .live("Galaxy") && second.screenSize == CGSize(width: 160, height: 96))
        android.onEvent?("A", .frame(landscape))
        settle()
        precondition(first.screenSize == CGSize(width: 160, height: 96))
        android.onDevices?([AndroidDevice(serial: "B", authorized: true, name: "Galaxy")])
        android.onEvent?("A", .frame(portrait))
        settle()
        precondition(capture.devices.count == 1 && capture.devices[0] === second)
        precondition(second.state == .live("Galaxy"))
        android.onDevices?([firstSource, AndroidDevice(serial: "B", authorized: true, name: "Galaxy")])
        settle()
        precondition(capture.devices.map(\.id) == ["android:B", "android:A"])
        precondition(capture.devices[0] === second && capture.devices[1] !== first)
        android.onDevices?([])
        settle()
        precondition(capture.devices.isEmpty && capture.state == .waiting)
        android.onDevices?([firstSource])
        settle()
        capture.stop()
        settle()
        precondition(capture.devices.isEmpty && capture.state == .waiting)
        let restoredAndroid = AndroidCapture()
        let restored = Capture(android: restoredAndroid, preferences: preferences)
        restoredAndroid.onDevices?([firstSource, AndroidDevice(serial: "B", authorized: true, name: "Galaxy")])
        settle()
        precondition(restored.devices.map(\.id) == ["android:B", "android:A"])
        restored.moveDevice("android:B", to: "android:A")
        precondition(restored.devices.map(\.id) == ["android:A", "android:B"])
        restored.moveDevice("missing", to: "android:A")
        precondition(restored.devices.map(\.id) == ["android:A", "android:B"])
        let thirdSource = AndroidDevice(serial: "C", authorized: false, name: "Third")
        restoredAndroid.onDevices?([firstSource, pending, thirdSource])
        settle()
        restoredAndroid.onDevices?([firstSource, thirdSource])
        settle()
        restored.moveDevice("android:C", to: "android:A")
        restoredAndroid.onDevices?([firstSource, pending, thirdSource, AndroidDevice(serial: "D", authorized: false, name: "Fourth")])
        settle()
        precondition(restored.devices.map(\.id) == ["android:C", "android:B", "android:A", "android:D"])
        restored.stop()
        print("PASS: multiple device streams, authorization, failures, rotation, and reconnect stay independent")
        print("PASS: reordering preserves stream identity, persists on reconnect and relaunch, and moves in both directions")

        let serial = UUID().uuidString
        let named = DeviceCapture(id: "android:\(serial)", name: "Pixel 9", modelID: "Android")
        defer { named.rename(to: "") }
        named.rename(to: "  Front desk 📱  ")
        precondition(named.displayName == "Front desk 📱" && named.name == "Pixel 9")
        named.name = "Pixel 9 Pro"
        precondition(named.displayName == "Front desk 📱")
        let reconnected = DeviceCapture(id: named.id, name: "Pixel 9 Pro", modelID: "Android")
        precondition(reconnected.displayName == "Front desk 📱")
        let other = DeviceCapture(id: "ios:\(serial)", name: "iPhone", modelID: nil)
        precondition(other.displayName == "iPhone")
        named.rename(to: " \n ")
        let reset = DeviceCapture(id: named.id, name: "Pixel 9 Pro", modelID: "Android")
        precondition(named.displayName == "Pixel 9 Pro" && reset.displayName == "Pixel 9 Pro")
        print("PASS: local device names persist on reconnect, survive metadata updates, stay independent, and reset when cleared")
    }
}
