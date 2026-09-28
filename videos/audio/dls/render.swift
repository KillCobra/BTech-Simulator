// Offline renderer: plays a list of notes through macOS's built-in General MIDI sample bank
// (gs_instruments.dls, via AVAudioUnitSampler) and writes a 44.1 kHz stereo float WAV.
//   render <track.json> <out.wav>
// track.json: {"program": 0-127, "percussion": false, "seconds": 46.0, "events": [[start_s, dur_s, note, velocity], ...]}
import AVFoundation

let args = CommandLine.arguments
guard args.count == 3 else { print("usage: render in.json out.wav"); exit(1) }
struct Track: Decodable { let program: Int; let percussion: Bool; let seconds: Double; let events: [[Double]] }
let track = try JSONDecoder().decode(Track.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))

let bank = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
let sr = 44100.0
let engine = AVAudioEngine()
let sampler = AVAudioUnitSampler()
engine.attach(sampler)
let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
engine.connect(sampler, to: engine.mainMixerNode, format: format)
try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
try sampler.loadSoundBankInstrument(at: bank, program: UInt8(track.program),
                                    bankMSB: UInt8(track.percussion ? kAUSampler_DefaultPercussionBankMSB : kAUSampler_DefaultMelodicBankMSB),
                                    bankLSB: UInt8(kAUSampler_DefaultBankLSB))
try engine.start()

// note on/off messages sorted by sample
var msgs: [(Int, Bool, UInt8, UInt8)] = []
for e in track.events {
  let on = Int((e[0] * sr).rounded()), off = Int(((e[0] + e[1]) * sr).rounded())
  msgs.append((on, true, UInt8(e[2]), UInt8(max(1, min(127, e[3])))))
  msgs.append((off, false, UInt8(e[2]), 0))
}
msgs.sort { $0.0 == $1.0 ? (!$0.1 && $1.1) : $0.0 < $1.0 }

let total = Int(track.seconds * sr)
let chunk: AVAudioFrameCount = 32  // note timing resolution: 0.7 ms
let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: chunk)!
let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total))!
var pos = 0, mi = 0
while pos < total {
  while mi < msgs.count && msgs[mi].0 <= pos {
    let m = msgs[mi]
    if m.1 { sampler.startNote(m.2, withVelocity: m.3, onChannel: 0) } else { sampler.stopNote(m.2, onChannel: 0) }
    mi += 1
  }
  let n = AVAudioFrameCount(min(Int(chunk), total - pos))
  let status = try engine.renderOffline(n, to: buffer)
  guard status == .success else { print("render status \(status)"); exit(2) }
  for ch in 0..<2 {
    let src = buffer.floatChannelData![ch], dst = out.floatChannelData![ch]
    for i in 0..<Int(n) { dst[pos + i] = src[i] }
  }
  pos += Int(n)
}
out.frameLength = AVAudioFrameCount(total)
// Written inside a function so the file is closed (and its header finalized) before exit.
func save() throws {
  let file = try AVAudioFile(forWriting: URL(fileURLWithPath: args[2]),
                             settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sr, AVNumberOfChannelsKey: 2,
                                        AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false])
  try file.write(from: out)
}
try save()
