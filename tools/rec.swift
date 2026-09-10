// rec — pishet zvuk so vstroennogo mikrofona v WAV
import Foundation
import AVFoundation

let args = CommandLine.arguments
guard args.count >= 3, let secs = Double(args[2]) else {
    print("usage: rec <out.wav> <seconds>"); exit(1)
}
let outURL = URL(fileURLWithPath: args[1])

let engine = AVAudioEngine()
let input = engine.inputNode
let fmt = input.inputFormat(forBus: 0)
FileHandle.standardError.write("format: \(fmt.sampleRate) Hz, \(fmt.channelCount) ch\n".data(using: .utf8)!)

var settings: [String: Any] = [
    AVFormatIDKey: kAudioFormatLinearPCM,
    AVSampleRateKey: fmt.sampleRate,
    AVNumberOfChannelsKey: 1,
    AVLinearPCMBitDepthKey: 16,
    AVLinearPCMIsFloatKey: false,
    AVLinearPCMIsBigEndianKey: false
]
guard let file = try? AVAudioFile(forWriting: outURL, settings: settings) else {
    print("ne smog sozdat fayl"); exit(1)
}

input.installTap(onBus: 0, bufferSize: 4096, format: fmt) { buf, _ in
    guard let conv = AVAudioConverter(from: fmt, to: file.processingFormat) else { return }
    let cap = AVAudioFrameCount(Double(buf.frameLength) * file.processingFormat.sampleRate / fmt.sampleRate) + 1024
    guard let out = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: cap) else { return }
    var err: NSError?
    var done = false
    conv.convert(to: out, error: &err) { _, status in
        if done { status.pointee = .noDataNow; return nil }
        done = true; status.pointee = .haveData; return buf
    }
    if err == nil, out.frameLength > 0 { try? file.write(from: out) }
}

do { try engine.start() } catch { print("engine: \(error)"); exit(1) }
Thread.sleep(forTimeInterval: secs)
engine.stop()
input.removeTap(onBus: 0)
print("gotovo")
