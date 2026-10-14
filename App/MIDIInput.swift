import Foundation
import CoreMIDI
import Darwin

struct MIDISource: Identifiable, Equatable {
    let id: Int32
    let endpoint: MIDIEndpointRef
    let name: String
}

/// MIDI byte parser keeps running status across packets and permits realtime
/// messages between data bytes, including inside system-exclusive messages.
struct MIDIByteParser {
    var status: UInt8 = 0
    var bytes: [UInt8] = []
    var sysex = false
    mutating func feed(_ byte: UInt8, emit: (UInt8, Int32) -> Void) {
        if byte >= 0xF8 { if [0xF8, 0xFA, 0xFB, 0xFC].contains(byte) { emit(byte, 0) }; return }
        if byte == 0xF0 { sysex = true; status = 0; bytes.removeAll(keepingCapacity: true); return }
        if byte == 0xF7 { sysex = false; return }
        if sysex { return }
        if byte & 0x80 != 0 { status = byte; bytes.removeAll(keepingCapacity: true); return }
        guard status != 0 else { return }
        bytes.append(byte)
        let length = status == 0xF2 ? 2 : ((status & 0xE0) == 0xC0 || status == 0xF1 || status == 0xF3 ? 1 : 2)
        if bytes.count == length {
            if status == 0xF2 { emit(status, Int32(bytes[0]) | Int32(bytes[1]) << 7) }
            else if status < 0xF0 { emit(status, Int32(bytes[0]) | (bytes.count > 1 ? Int32(bytes[1]) << 8 : 0)) }
            bytes.removeAll(keepingCapacity: true)
            if status >= 0xF0 { status = 0 }
        }
    }
}

final class MIDIInput {
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var connected = MIDIEndpointRef()
    private var parser = MIDIByteParser()
    private let queue: DispatchQueue
    private let receive: (UInt8, Int32, Double) -> Void
    var sourcesChanged: (([MIDISource]) -> Void)?
    private var scale: Double = 0
    var selectedID: Int32 = 0
    init(queue: DispatchQueue, receive: @escaping (UInt8, Int32, Double) -> Void) {
        self.queue = queue; self.receive = receive
        var info = mach_timebase_info_data_t(); mach_timebase_info(&info)
        scale = Double(info.numer) / Double(info.denom) / 1_000_000_000
        MIDIClientCreateWithBlock("Breakwater" as CFString, &client) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        MIDIInputPortCreateWithBlock(client, "Clock + pads" as CFString, &port) { [weak self] packets, _ in
            guard let self else { return }
            let offset = MemoryLayout<MIDIPacketList>.offset(of: \.packet)!
            var packet = UnsafeRawPointer(packets).advanced(by: offset).assumingMemoryBound(to: MIDIPacket.self)
            for _ in 0..<packets.pointee.numPackets {
                let stamp = packet.pointee.timeStamp == 0 ? mach_absolute_time() : packet.pointee.timeStamp
                let time = Double(stamp) * self.scale
                let dataOffset = MemoryLayout<MIDIPacket>.offset(of: \.data)!
                let bytes = Array(UnsafeBufferPointer(start: UnsafeRawPointer(packet).advanced(by: dataOffset).assumingMemoryBound(to: UInt8.self), count: Int(packet.pointee.length)))
                self.queue.async { [weak self] in
                    guard let self else { return }
                    for byte in bytes { self.parser.feed(byte) { self.receive($0, $1, time) } }
                }
                packet = UnsafePointer(MIDIPacketNext(packet))
            }
        }
    }
    func refresh() {
        let sources = (0..<MIDIGetNumberOfSources()).map { index -> MIDISource in
            let endpoint = MIDIGetSource(index)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
            var id: Int32 = 0; MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &id)
            return MIDISource(id: id, endpoint: endpoint, name: name?.takeRetainedValue() as String? ?? "MIDI input")
        }
        let next = sources.first(where: { $0.id == selectedID }) ?? (selectedID == 0 ? sources.first : nil)
        if next?.endpoint != connected {
            if connected != 0 { MIDIPortDisconnectSource(port, connected) }
            connected = next?.endpoint ?? 0
            if connected != 0 { MIDIPortConnectSource(port, connected, nil) }
            queue.async { [weak self] in self?.parser = MIDIByteParser() }
        }
        sourcesChanged?(sources)
    }
    deinit { if port != 0 { MIDIPortDispose(port) }; if client != 0 { MIDIClientDispose(client) } }
}
