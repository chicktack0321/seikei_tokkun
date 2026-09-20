import UIKit

/// 触覚フィードバック。クイズとタイピングで同じ手応えにするため1か所にまとめる。
///
/// `UIFeedbackGenerator` は使い回して `prepare()` で温めておく必要がある。
/// 発火のたびに生成していたころは Taptic Engine が毎回冷えた状態から起動され、
/// 「タップしたのに一拍遅れて震える」原因になっていた。
@MainActor
final class Haptics {
    static let shared = Haptics()

    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let strongImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let notification = UINotificationFeedbackGenerator()

    private var failureTask: Task<Void, Never>?

    private init() {}

    /// 次の発火に備えて温めておく。問題が表示された時点など、手が空いているときに呼ぶ。
    /// 温めた状態は数秒で切れるので、発火の直前ではなく「そろそろ来る」場面で呼ぶのが効く。
    static func prepare() {
        shared.impact.prepare()
        shared.strongImpact.prepare()
    }

    /// 正解・単語完成。短く1回。
    static func success() {
        shared.impact.impactOccurred()
        // 続けて出ることが多いので、鳴らした直後に次のぶんを温め直す
        shared.impact.prepare()
    }

    /// 不正解。3回続けて震わせ、正解とはっきり区別できるようにする。
    /// 画面を見ずに解いていても間違いに気付けるのが狙い。
    static func failure() {
        let generator = shared.strongImpact
        generator.impactOccurred()

        shared.failureTask?.cancel()
        shared.failureTask = Task { @MainActor in
            for _ in 0..<2 {
                try? await Task.sleep(nanoseconds: 110_000_000)
                guard !Task.isCancelled else { return }
                generator.impactOccurred()
            }
            generator.prepare()
        }
    }

    /// 自己ベスト更新など、通常の正解より大きな達成
    static func celebrate() {
        shared.notification.notificationOccurred(.success)
    }
}
