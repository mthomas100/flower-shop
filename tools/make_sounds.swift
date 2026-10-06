import AVFoundation

// Synthesizes the two little UI sounds: a ceramic "tink" and a bell arpeggio.
// Usage: swift tools/make_sounds.swift FlowerShop/Resources/Sounds
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
let sampleRate = 44_100.0

func write(_ name: String, seconds: Double, _ sample: (Double) -> Double) throws {
    let frames = AVAudioFrameCount(seconds * sampleRate)
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    let data = buffer.floatChannelData![0]
    var peak = 0.0
    var values = [Double](repeating: 0, count: Int(frames))
    for i in 0..<Int(frames) {
        values[i] = sample(Double(i) / sampleRate)
        peak = max(peak, abs(values[i]))
    }
    for i in 0..<Int(frames) { data[i] = Float(values[i] / max(peak, 1e-6) * 0.7) }
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate,
                                   AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                                   AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
    let file = try AVAudioFile(forWriting: outDir.appendingPathComponent(name), settings: settings)
    try file.write(from: buffer)
}

func bell(_ t: Double, _ f: Double, decay: Double) -> Double {
    guard t >= 0 else { return 0 }
    let attack = min(t / 0.004, 1)
    let partials = [(1.0, 1.0), (2.76, 0.35), (5.4, 0.18), (8.93, 0.08)]
    return attack * partials.reduce(0) { $0 + $1.1 * sin(2 * .pi * f * $1.0 * t) * exp(-t * decay * (1 + $1.0 * 0.6)) }
}

// Landing: a soft ceramic tink with a tiny body thump.
try write("vase_tink.wav", seconds: 0.6) { t in
    bell(t, 1568, decay: 9) * 0.8 + sin(2 * .pi * 196 * t) * exp(-t * 40) * 0.5
}

// Bouquet complete: C6 E6 G6 C7, gently staggered.
try write("bouquet_chime.wav", seconds: 2.0) { t in
    let notes = [1046.5, 1318.5, 1568.0, 2093.0]
    return notes.enumerated().reduce(0) { sum, note in sum + bell(t - Double(note.offset) * 0.11, note.element, decay: 2.2) }
}
print("ok")
