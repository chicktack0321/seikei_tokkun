import Foundation
import AVFoundation

/// 波形をその場で合成するための最小限の道具立て。
///
/// 参考にした元のタイピングゲームは Web Audio のオシレータで音を作っており、
/// 音声ファイルを1つも持っていなかった。このアプリも「音声ファイルを同梱しない」方針なので、
/// 同じくサンプルを計算で埋める。効果音もBGMも数百KBのメモリで済み、アプリ本体は増えない。
enum ToneSynth {
    static let sampleRate: Double = 44_100

    enum Waveform {
        case sine
        case triangle
    }

    /// 指定長の無音バッファを作る
    static func makeBuffer(seconds: Double) -> AVAudioPCMBuffer? {
        makeBuffer(frames: Int((seconds * sampleRate).rounded()))
    }

    /// サンプル数を指定して無音バッファを作る。
    /// ループ素材は長さが1サンプルでもずれると継ぎ目でリズムが崩れるため、
    /// 秒ではなくサンプル数で長さを決められるようにしている。
    static func makeBuffer(frames: Int) -> AVAudioPCMBuffer? {
        guard frames > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))
        else { return nil }
        buffer.frameLength = buffer.frameCapacity
        if let channel = buffer.floatChannelData?[0] {
            channel.update(repeating: 0, count: Int(buffer.frameLength))
        }
        return buffer
    }

    /// 1音を加算する。
    /// エンベロープは 5ms で立ち上げてから指数的に減衰させる（元実装の gain ramp と同じ形）。
    /// - Parameter wrapsAround: バッファ末尾を超えた分を先頭へ回り込ませる。
    ///   ループ素材で、末尾で鳴り始めた音の減衰を次の周回の頭へ繋げるために使う
    ///   （切り捨てると継ぎ目でプツッと途切れる）。
    static func addTone(
        to buffer: AVAudioPCMBuffer,
        frequency: Double,
        endFrequency: Double? = nil,
        waveform: Waveform = .sine,
        start: Double,
        duration: Double,
        volume: Double,
        wrapsAround: Bool = false
    ) {
        guard let channel = buffer.floatChannelData?[0], duration > 0 else { return }

        let total = Int(buffer.frameLength)
        let startIndex = max(0, Int((start * sampleRate).rounded()))
        let frameCount = Int((duration * sampleRate).rounded())
        let attack = 0.005

        var phase = 0.0
        for offset in 0..<frameCount {
            let position = startIndex + offset
            guard let index = wrappedIndex(position, total: total, wrapsAround: wrapsAround) else { break }

            let t = Double(offset) / sampleRate
            // 周波数スイープ（キックのように音程が落ちる音に使う）
            let freq: Double
            if let endFrequency {
                let ratio = min(t / duration, 1)
                freq = frequency * pow(endFrequency / frequency, ratio)
            } else {
                freq = frequency
            }

            let amplitude: Double
            if t < attack {
                amplitude = volume * (t / attack)
            } else {
                // duration の終わりでほぼ 0 になるよう指数減衰させる
                let decayProgress = (t - attack) / max(duration - attack, 0.0001)
                amplitude = volume * pow(0.0001 / max(volume, 0.0001), decayProgress)
            }

            channel[index] += Float(amplitude * sample(phase: phase, waveform: waveform))
            phase += 2 * .pi * freq / sampleRate
            if phase > 2 * .pi { phase -= 2 * .pi }
        }
    }

    /// ハイハット。白色ノイズを一次のハイパスに通して短く切る。
    static func addHiHat(
        to buffer: AVAudioPCMBuffer,
        start: Double,
        volume: Double,
        duration: Double = 0.05,
        wrapsAround: Bool = false
    ) {
        guard let channel = buffer.floatChannelData?[0] else { return }

        let total = Int(buffer.frameLength)
        let startIndex = max(0, Int((start * sampleRate).rounded()))
        let frameCount = Int((duration * sampleRate).rounded())

        var previousInput: Double = 0
        var previousOutput: Double = 0
        // 一次ハイパスの係数。7〜8kHz あたりから上を通す程度に効かせる
        let coefficient = 0.82

        for offset in 0..<frameCount {
            let position = startIndex + offset
            guard let index = wrappedIndex(position, total: total, wrapsAround: wrapsAround) else { break }

            let noise = Double.random(in: -1...1)
            let filtered = coefficient * (previousOutput + noise - previousInput)
            previousInput = noise
            previousOutput = filtered

            let t = Double(offset) / sampleRate
            let envelope = exp(-t / (duration * 0.25))
            channel[index] += Float(filtered * envelope * volume)
        }
    }

    /// 書き込み先の位置を返す。バッファ外に出たとき、回り込みが有効なら先頭からの位置に、
    /// 無効なら nil を返して打ち切らせる。
    private static func wrappedIndex(_ position: Int, total: Int, wrapsAround: Bool) -> Int? {
        guard total > 0 else { return nil }
        if position < total { return position }
        return wrapsAround ? position % total : nil
    }

    private static func sample(phase: Double, waveform: Waveform) -> Double {
        switch waveform {
        case .sine:
            return sin(phase)
        case .triangle:
            // -1〜1 の三角波
            let normalized = phase / (2 * .pi)
            return 4 * abs(normalized - 0.5) - 1
        }
    }

    /// 全体が -1〜1 に収まるよう正規化する。音を重ねると簡単に振り切れて歪むため。
    static func normalize(_ buffer: AVAudioPCMBuffer, peak: Float = 0.9) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)

        var maxValue: Float = 0
        for index in 0..<count {
            maxValue = max(maxValue, abs(channel[index]))
        }
        guard maxValue > peak else { return }

        let scale = peak / maxValue
        for index in 0..<count {
            channel[index] *= scale
        }
    }
}
