import AVFoundation

struct AndroidDevice: Equatable {
    let serial: String
    let authorized: Bool
    let name: String

    static func connectedUSBDevices(in output: String) -> [AndroidDevice] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2, fields.contains(where: { $0.hasPrefix("usb:") }),
                  fields[1] == "device" || fields[1] == "unauthorized" else { return nil }
            let name = fields.first(where: { $0.hasPrefix("model:") })
                .map { String($0.dropFirst(6)).replacingOccurrences(of: "_", with: " ") } ?? "Android"
            return AndroidDevice(serial: fields[0], authorized: fields[1] == "device", name: name)
        }.sorted { $0.serial < $1.serial }
    }
}

struct AndroidVideo {
    private var format: CMVideoFormatDescription?

    mutating func sample(packet: Data, configuration: Bool) -> CMSampleBuffer? {
        if configuration { format = nil }
        let bytes = [UInt8](packet)
        var starts: [(Int, Int)] = []
        var index = 0
        while index + 2 < bytes.count {
            if bytes[index] == 0 && bytes[index + 1] == 0 {
                if bytes[index + 2] == 1 {
                    starts.append((index, index + 3))
                    index += 3
                    continue
                }
                if index + 3 < bytes.count && bytes[index + 2] == 0 && bytes[index + 3] == 1 {
                    starts.append((index, index + 4))
                    index += 4
                    continue
                }
            }
            index += 1
        }
        let units = starts.enumerated().compactMap { offset, start -> [UInt8]? in
            let end = offset + 1 < starts.count ? starts[offset + 1].0 : bytes.count
            guard start.1 < end else { return nil }
            return Array(bytes[start.1..<end])
        }
        guard !units.isEmpty else { return nil }
        if configuration {
            guard let sps = units.first(where: { $0[0] & 31 == 7 }),
                  let pps = units.first(where: { $0[0] & 31 == 8 }) else { return nil }
            sps.withUnsafeBufferPointer { spsBuffer in
                pps.withUnsafeBufferPointer { ppsBuffer in
                    let pointers = [spsBuffer.baseAddress!, ppsBuffer.baseAddress!]
                    let sizes = [sps.count, pps.count]
                    _ = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                        allocator: kCFAllocatorDefault, parameterSetCount: 2,
                        parameterSetPointers: pointers, parameterSetSizes: sizes,
                        nalUnitHeaderLength: 4, formatDescriptionOut: &format
                    )
                }
            }
            return nil
        }
        guard let format else { return nil }
        var payload = Data()
        for unit in units {
            var length = UInt32(unit.count).bigEndian
            withUnsafeBytes(of: &length) { payload.append(contentsOf: $0) }
            payload.append(contentsOf: unit)
        }
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: payload.count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: payload.count, flags: 0, blockBufferOut: &block
        ) == noErr, let block else { return nil }
        let copied = payload.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: payload.count)
        }
        guard copied == noErr else { return nil }
        var sample: CMSampleBuffer?
        var size = payload.count
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample
        ) == noErr, let sample else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }
}
