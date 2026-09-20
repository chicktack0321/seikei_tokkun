import Foundation
import AVFoundation
import Observation
import os

/// 演習で鳴らす効果音とBGM。
///
/// 効果音（正解・不正解・開始・終了・ファンファーレ）と I–V–vi–IV の4小節ループを、
/// 合成した波形で鳴らす。音声ファイルは持たないのでアプリの容量は増えない。
///
/// オーディオエンジンは1つしか持てないので、画面ごとに作らずアプリ全体で共有する。
@Observable
@MainActor
final class GameAudio {
    static let shared = GameAudio()

    enum Effect {
        case correct       // 正解（上昇音）
        case miss          // 不正解（下降音）
        case start         // セット開始
        case setComplete   // セット終了
        case fanfare       // 好成績で終えた
    }

    /// 音を鳴らすかどうか。切っていればエンジンごと止める。
    ///
    /// 鳴らす主体がこのクラス1つなので、設定の保存もここで引き受ける。
    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled { stopAll() }
        }
    }

    private static let enabledKey = "gameSoundEnabled"

    private let logger = Logger(subsystem: "com.eitango.seikei", category: "GameAudio")
    private let engine = AVAudioEngine()
    private let bgmPlayer = AVAudioPlayerNode()
    private let effectPlayer = AVAudioPlayerNode()

    private var effectBuffers: [String: AVAudioPCMBuffer] = [:]
    private var bgmBuffer: AVAudioPCMBuffer?
    private var isEngineReady = false
    private var isPreparing = false
    /// 準備が済む前にBGMを頼まれていたか。済んだ時点で鳴らし始める
    private var wantsBGM = false

    private init() {
        // 初期化中のプロパティ代入では didSet が走らないので、保存し直しは起きない
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    // MARK: - 準備

    /// 波形の合成を裏で先に済ませておく。
    ///
    /// BGMと効果音を合わせて百万サンプル規模の三角関数計算になる。以前はスタートを
    /// 押した流れの中でメインスレッドで合成しており、開始のたびに待たされていた。
    /// スタート画面が出た時点で呼んでおけば、押すころには終わっている。
    func warmUp() {
        guard !isEngineReady, !isPreparing else { return }
        isPreparing = true

        DispatchQueue.global(qos: .userInitiated).async {
            let bgm = Self.makeBGMLoop()
            let effects = Self.makeEffectBuffers()
            DispatchQueue.main.async {
                self.install(bgm: bgm, effects: effects)
            }
        }
    }

    private func install(bgm: AVAudioPCMBuffer?, effects: [String: AVAudioPCMBuffer]) {
        isPreparing = false
        guard !isEngineReady else { return }

        let format = AVAudioFormat(standardFormatWithSampleRate: ToneSynth.sampleRate, channels: 1)
        engine.attach(bgmPlayer)
        engine.attach(effectPlayer)
        engine.connect(bgmPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(effectPlayer, to: engine.mainMixerNode, format: format)

        bgmBuffer = bgm
        effectBuffers = effects

        // BGMは伴奏なので、効果音より控えめにして打鍵音を埋もれさせない
        bgmPlayer.volume = 0.35
        effectPlayer.volume = 0.9

        isEngineReady = true

        // 準備の前にBGMを頼まれていたぶんをここで始める
        if wantsBGM { startBGM() }
    }

    /// - Returns: いま鳴らせるか。準備が済んでいなければ合成を始めて false を返す。
    ///   ここで待って合成すると操作が止まるので、間に合わなかった音は鳴らさない。
    private func startEngineIfNeeded() -> Bool {
        guard isEngineReady else {
            warmUp()
            return false
        }
        guard !engine.isRunning else { return true }
        do {
            try engine.start()
            return true
        } catch {
            logger.error("オーディオエンジンを開始できません: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - 再生

    func play(_ effect: Effect) {
        guard isEnabled, startEngineIfNeeded() else { return }
        guard let buffer = effectBuffers[Self.key(for: effect)] else { return }

        if !effectPlayer.isPlaying { effectPlayer.play() }
        // 連打しても前の音を切らずに重ねる
        effectPlayer.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    func startBGM() {
        guard isEnabled else { return }
        // 合成が終わっていなければ、終わった時点で鳴らし始める
        wantsBGM = true
        guard startEngineIfNeeded(), let bgmBuffer else { return }
        guard !bgmPlayer.isPlaying else { return }
        bgmPlayer.scheduleBuffer(bgmBuffer, at: nil, options: [.loops], completionHandler: nil)
        bgmPlayer.play()
    }

    func stopBGM() {
        wantsBGM = false
        guard bgmPlayer.isPlaying else { return }
        bgmPlayer.stop()
    }

    func stopAll() {
        wantsBGM = false
        // まだエンジンに繋いでいないノードを操作しないようにする（音を一度も鳴らさずに
        // 設定だけ切り替えた場合や、テストからの呼び出しがこの経路を通る）
        guard isEngineReady else { return }
        bgmPlayer.stop()
        effectPlayer.stop()
        if engine.isRunning { engine.pause() }
    }

    // MARK: - 波形

    private static func key(for effect: Effect) -> String {
        switch effect {
        case .correct: return "correct"
        case .miss: return "miss"
        case .start: return "start"
        case .setComplete: return "setComplete"
        case .fanfare: return "fanfare"
        }
    }

    /// バックグラウンドで合成するため、メインアクターから外してある（`ToneSynth` の計算だけで完結する）
    nonisolated private static func makeEffectBuffers() -> [String: AVAudioPCMBuffer] {
        var buffers: [String: AVAudioPCMBuffer] = [:]

        // ドミソの上昇。正解の手応えを出す
        if let correct = ToneSynth.makeBuffer(seconds: 0.4) {
            ToneSynth.addTone(to: correct, frequency: 523, start: 0, duration: 0.15, volume: 0.5)
            ToneSynth.addTone(to: correct, frequency: 659, start: 0.06, duration: 0.15, volume: 0.5)
            ToneSynth.addTone(to: correct, frequency: 1047, start: 0.12, duration: 0.22, volume: 0.6)
            ToneSynth.normalize(correct)
            buffers["correct"] = correct
        }

        // 下降する2音。正解の上昇音と対になるようにする
        if let miss = ToneSynth.makeBuffer(seconds: 0.25) {
            ToneSynth.addTone(to: miss, frequency: 330, start: 0, duration: 0.10, volume: 0.45)
            ToneSynth.addTone(to: miss, frequency: 220, start: 0.07, duration: 0.12, volume: 0.45)
            ToneSynth.normalize(miss)
            buffers["miss"] = miss
        }

        if let start = ToneSynth.makeBuffer(seconds: 0.55) {
            for (index, frequency) in [392.0, 523.0, 659.0, 784.0].enumerated() {
                ToneSynth.addTone(
                    to: start,
                    frequency: frequency,
                    waveform: .triangle,
                    start: Double(index) * 0.08,
                    duration: 0.18,
                    volume: 0.55
                )
            }
            ToneSynth.normalize(start)
            buffers["start"] = start
        }

        if let over = ToneSynth.makeBuffer(seconds: 0.8) {
            for (index, frequency) in [523.0, 440.0, 349.0, 262.0].enumerated() {
                ToneSynth.addTone(
                    to: over,
                    frequency: frequency,
                    waveform: .triangle,
                    start: Double(index) * 0.14,
                    duration: 0.25,
                    volume: 0.5
                )
            }
            ToneSynth.normalize(over)
            buffers["setComplete"] = over
        }

        // 好成績で終えたとき。通常の正解音より派手に、長めに鳴らす
        if let fanfare = ToneSynth.makeBuffer(seconds: 1.2) {
            let melody: [(Double, Double)] = [
                (523, 0.0), (659, 0.1), (784, 0.2), (1047, 0.3), (784, 0.45), (1047, 0.55)
            ]
            for (frequency, start) in melody {
                ToneSynth.addTone(
                    to: fanfare,
                    frequency: frequency,
                    waveform: .triangle,
                    start: start,
                    duration: 0.3,
                    volume: 0.6
                )
            }
            ToneSynth.normalize(fanfare)
            buffers["fanfare"] = fanfare
        }

        return buffers
    }

    /// I–V–vi–IV の4小節ループ。
    /// 元実装は1小節ずつ先読みしてスケジュールしていたが、4小節で必ず繰り返すので
    /// まとめて1本のバッファに焼いてループ再生する（タイマーが要らず、途切れも起きない）。
    ///
    /// ループ素材なので、バッファの長さは4小節ちょうどでなければならない。
    /// 以前は末尾に余白を足していたため、1周ごとに200msの空白が入って
    /// 継ぎ目でリズムが崩れていた。
    /// 長さは秒ではなくサンプル数で決める。8分音符1つ分のサンプル数を先に確定させ、
    /// その32個分をループ長とすることで、拍が割り切れて周回してもテンポがずれない。
    nonisolated static func makeBGMLoop() -> AVAudioPCMBuffer? {
        let bpm = 130.0
        let bars = 4
        let stepsPerBar = 8  // 8分音符
        let totalSteps = bars * stepsPerBar

        let stepFrames = Int((60.0 / bpm / 2 * ToneSynth.sampleRate).rounded())
        let eighth = Double(stepFrames) / ToneSynth.sampleRate
        let beat = eighth * 2

        guard let buffer = ToneSynth.makeBuffer(frames: stepFrames * totalSteps) else { return nil }

        /// 何個目の8分音符か、から時間を求める。位置を秒で積み上げると誤差が溜まるため。
        func time(ofStep step: Int) -> Double {
            Double(step * stepFrames) / ToneSynth.sampleRate
        }

        let chords: [[Double]] = [
            [523.25, 659.25, 783.99],  // C
            [392.00, 493.88, 587.33],  // G
            [440.00, 523.25, 659.25],  // Am
            [349.23, 440.00, 523.25]   // F
        ]
        let bassNotes: [Double] = [261.63, 196.00, 220.00, 174.61]
        // 小節ごとにアルペジオの形を変えて単調さを避ける
        let arpeggioPatterns: [[Int]] = [
            [0, 1, 2, 1, 0, 1, 2, 1],
            [2, 1, 0, 1, 2, 1, 0, 1],
            [0, 2, 1, 2, 0, 1, 2, 1],
            [0, 1, 2, 2, 1, 0, 1, 2]
        ]

        for barIndex in 0..<bars {
            let barStartStep = barIndex * stepsPerBar
            let chord = chords[barIndex]
            let pattern = arpeggioPatterns[barIndex]

            for (step, noteIndex) in pattern.enumerated() {
                ToneSynth.addTone(
                    to: buffer,
                    frequency: chord[noteIndex],
                    waveform: .triangle,
                    start: time(ofStep: barStartStep + step),
                    duration: eighth * 0.7,
                    volume: 0.2,
                    wrapsAround: true
                )
            }

            // 1拍目と3拍目（＝8分音符で0個目と4個目）にベースとキックを置く
            for beatIndex in [0, 2] {
                let start = time(ofStep: barStartStep + beatIndex * 2)
                ToneSynth.addTone(
                    to: buffer,
                    frequency: bassNotes[barIndex],
                    start: start,
                    duration: beat * 0.6,
                    volume: 0.35,
                    wrapsAround: true
                )
                // キック：音程を落としながら短く鳴らす
                ToneSynth.addTone(
                    to: buffer,
                    frequency: 130,
                    endFrequency: 42,
                    start: start,
                    duration: 0.22,
                    volume: 0.42,
                    wrapsAround: true
                )
            }

            for step in 0..<stepsPerBar {
                ToneSynth.addHiHat(
                    to: buffer,
                    start: time(ofStep: barStartStep + step),
                    volume: step.isMultiple(of: 2) ? 0.08 : 0.05,
                    wrapsAround: true
                )
            }
        }

        ToneSynth.normalize(buffer)
        return buffer
    }
}
