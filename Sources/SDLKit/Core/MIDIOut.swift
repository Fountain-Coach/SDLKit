import Foundation

#if os(macOS)
import CoreMIDI

public final class MIDIOut {
    private var client: MIDIClientRef = 0
    private var outPort: MIDIPortRef = 0
    private var dest: MIDIEndpointRef = 0
    private var defaultChannel: UInt8 = 0
    private let midi1: Bool

    public init(midi1: Bool = true) throws {
        self.midi1 = midi1
        var cl = MIDIClientRef()
        let status = MIDIClientCreateWithBlock("SDLKitMIDIOut" as CFString, &cl, nil)
        guard status == 0 else { throw AgentError.internalError("MIDIClientCreate failed: \(status)") }
        client = cl
        var port = MIDIPortRef()
        let ps = MIDIOutputPortCreate(client, "SDLKitOut" as CFString, &port)
        guard ps == 0 else { throw AgentError.internalError("MIDIOutputPortCreate failed: \(ps)") }
        outPort = port
        try selectDestination(index: 0)
    }

    public func stop() {
        if outPort != 0 { MIDIPortDispose(outPort); outPort = 0 }
        if client != 0 { MIDIClientDispose(client); client = 0 }
    }

    deinit { stop() }

    public func send(noteOn: Bool, note: UInt8, velocity: UInt8, channel: UInt8? = nil) {
        if midi1 {
            var packetList = MIDIPacketList(numPackets: 1, packet: MIDIPacket())
            let ch = (channel ?? defaultChannel) & 0x0F
            let status: UInt8 = (noteOn ? 0x90 : 0x80) | ch
            var bytes: [UInt8] = [status, note, velocity]
            bytes.withUnsafeMutableBytes { raw in
                var pkt = MIDIPacketListInit(&packetList)
                pkt = MIDIPacketListAdd(&packetList, MemoryLayout<MIDIPacketList>.size + 3, pkt, 0, 3, raw.baseAddress!.assumingMemoryBound(to: UInt8.self))
            }
            // Send legacy MIDI 1.0 packet list via CoreMIDI output port
            MIDISend(outPort, dest, &packetList)
        } else {
            // TODO: Implement UMP (MIDI 2.0) when widely available
        }
    }

    public static func listDestinations() -> [String] {
        var names: [String] = []
        let count = MIDIGetNumberOfDestinations()
        for i in 0..<count {
            let ep = MIDIGetDestination(i)
            var cfName: Unmanaged<CFString>?
            var name: String = "Destination \(i)"
            if MIDIObjectGetStringProperty(ep, kMIDIPropertyName, &cfName) == 0, let cf = cfName?.takeRetainedValue() {
                name = cf as String
            }
            names.append(name)
        }
        return names
    }

    public func selectDestination(index: Int) throws {
        let count = MIDIGetNumberOfDestinations()
        guard index >= 0 && index < count else { throw AgentError.invalidArgument("MIDI destination index out of range") }
        dest = MIDIGetDestination(index)
    }

    public func selectDestination(nameContains: String) throws {
        let count = MIDIGetNumberOfDestinations()
        var found: Int? = nil
        for i in 0..<count {
            let ep = MIDIGetDestination(i)
            var cfName: Unmanaged<CFString>?
            if MIDIObjectGetStringProperty(ep, kMIDIPropertyName, &cfName) == 0, let cf = cfName?.takeRetainedValue() {
                let s = cf as String
                if s.lowercased().contains(nameContains.lowercased()) { found = i; break }
            }
        }
        if let idx = found { try selectDestination(index: idx) } else { throw AgentError.invalidArgument("MIDI destination not found: \(nameContains)") }
    }

    public func setDefaultChannel(_ ch: Int) throws {
        guard ch >= 0 && ch < 16 else { throw AgentError.invalidArgument("MIDI channel out of range (0-15)") }
        defaultChannel = UInt8(ch)
    }
}
#else
public final class MIDIOut {
    public init(midi1: Bool = true) throws {}
    public func stop() {}
    public func send(noteOn: Bool, note: UInt8, velocity: UInt8, channel: UInt8 = 0) {}
}
#endif
