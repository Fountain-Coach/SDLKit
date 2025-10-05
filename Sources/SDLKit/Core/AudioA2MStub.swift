import Foundation

public struct MIDIEvent: Codable, Equatable {
    public enum Kind: String, Codable { case note_on, note_off }
    public let kind: Kind
    public let note: Int
    public let velocity: Int
    public let frameIndex: Int
}

public final class AudioA2MStub {
    private let melBands: Int
    private var lastNote: Int? = nil
    private var sustain: Int = 0
    private let minOnFrames: Int
    private let minOffFrames: Int
    private let energyThreshold: Float

    public init(melBands: Int, energyThreshold: Float = 1e-2, minOnFrames: Int = 2, minOffFrames: Int = 2) {
        self.melBands = melBands
        self.energyThreshold = energyThreshold
        self.minOnFrames = max(1, minOnFrames)
        self.minOffFrames = max(1, minOffFrames)
    }

    // naive mapping: index of max mel bin -> midi note in 36..96 range
    private func binToMidi(_ bin: Int) -> Int {
        let lo = 36, hi = 96
        return lo + (bin * (hi - lo)) / max(1, melBands - 1)
    }

    public func process(melFrames: [[Float]], startFrameIndex: Int) -> [MIDIEvent] {
        var events: [MIDIEvent] = []
        var frameIdx = startFrameIndex
        for mel in melFrames {
            // winner-take-all with threshold
            var maxVal: Float = 0
            var maxIdx: Int = 0
            for i in 0..<min(melBands, mel.count) {
                if mel[i] > maxVal { maxVal = mel[i]; maxIdx = i }
            }
            let active = maxVal >= energyThreshold
            let note = active ? binToMidi(maxIdx) : nil
            switch (lastNote, note) {
            case (nil, .some(let n)):
                sustain += 1
                if sustain >= minOnFrames {
                    let vel = max(1, min(127, Int((maxVal * 127.0).rounded())))
                    events.append(MIDIEvent(kind: .note_on, note: n, velocity: vel, frameIndex: frameIdx))
                    lastNote = n
                    sustain = 0
                }
            case (.some(let ln), .some(let n)):
                if n == ln {
                    sustain = 0 // keep playing
                } else {
                    // switch note: off -> on
                    events.append(MIDIEvent(kind: .note_off, note: ln, velocity: 0, frameIndex: frameIdx))
                    let vel = max(1, min(127, Int((maxVal * 127.0).rounded())))
                    events.append(MIDIEvent(kind: .note_on, note: n, velocity: vel, frameIndex: frameIdx))
                    lastNote = n
                    sustain = 0
                }
            case (.some(let ln), nil):
                sustain += 1
                if sustain >= minOffFrames {
                    events.append(MIDIEvent(kind: .note_off, note: ln, velocity: 0, frameIndex: frameIdx))
                    lastNote = nil
                    sustain = 0
                }
            case (nil, nil):
                sustain = 0
            }
            frameIdx += 1
        }
        return events
    }
}

