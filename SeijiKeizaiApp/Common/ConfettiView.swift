import SwiftUI

/// 正解や自己ベスト更新を祝う紙吹雪。
///
/// 画像素材は持たず、小さな矩形と円を散らして描くだけにしている
/// （音声と同じく、アプリ容量を増やさない方針のため）。
/// `trigger` の値が変わるたびに一度だけ弾ける。
///
/// クラッカーのように**発生源から短く弾ける**。画面全体に降らせると、
/// 次の操作に移りたいテンポを邪魔するうえ、どこで何が起きたのかも伝わらない。
struct ConfettiView: View {
    /// これが変わると新しく紙吹雪が発生する
    var trigger: Int
    /// 弾ける位置（このビューの中の相対座標）。既定は中央上
    var origin: UnitPoint = UnitPoint(x: 0.5, y: 0.1)
    var pieceCount: Int = 24
    /// 短く出す。長引くと次の問題へ進む動作にかぶる
    var duration: Double = 0.7

    @State private var pieces: [Piece] = []
    @State private var isAnimating = false

    struct Piece: Identifiable {
        /// 添字をそのまま id にする。毎回 UUID を振ると弾けるたびに
        /// ForEach が全ての紙片を破棄して作り直すことになり、正解の瞬間に引っかかる。
        let id: Int
        let dx: CGFloat
        let dy: CGFloat
        let size: CGFloat
        let color: Color
        let isCircle: Bool
        let rotation: Double
        let delay: Double
    }

    private static let palette: [Color] = [.pink, .orange, .yellow, .green, .blue, .purple]

    var body: some View {
        GeometryReader { proxy in
            let baseX = proxy.size.width * origin.x
            let baseY = proxy.size.height * origin.y

            ZStack(alignment: .topLeading) {
                ForEach(pieces) { piece in
                    shape(for: piece)
                        .fill(piece.color)
                        .frame(width: piece.size, height: piece.isCircle ? piece.size : piece.size * 0.5)
                        .rotationEffect(.degrees(isAnimating ? piece.rotation : 0))
                        .offset(
                            x: baseX + (isAnimating ? piece.dx : 0),
                            y: baseY + (isAnimating ? piece.dy : 0)
                        )
                        .opacity(isAnimating ? 0 : 1)
                        .animation(
                            .easeOut(duration: duration).delay(piece.delay),
                            value: isAnimating
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in burst() }
    }

    private func shape(for piece: Piece) -> some Shape {
        piece.isCircle
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: 1))
    }

    private func burst() {
        pieces = (0..<pieceCount).map { index in
            // 上向きの扇形に飛ばし、最後に落ちる分を足す。クラッカーらしい軌跡になる
            let angle = Double.random(in: (-165 * .pi / 180)...(-15 * .pi / 180))
            let distance = CGFloat.random(in: 70...150)
            return Piece(
                id: index,
                dx: cos(angle) * distance,
                dy: sin(angle) * distance + .random(in: 40...90),
                size: .random(in: 5...10),
                color: Self.palette.randomElement() ?? .pink,
                isCircle: Bool.random(),
                rotation: .random(in: 180...540),
                delay: .random(in: 0...0.06)
            )
        }
        // 位置を初期状態に戻してから弾けさせる
        isAnimating = false
        DispatchQueue.main.async {
            isAnimating = true
        }
    }
}

/// 正解時など、一瞬だけ紙吹雪を重ねたい画面に付ける
extension View {
    func confetti(trigger: Int, origin: UnitPoint = UnitPoint(x: 0.5, y: 0.1)) -> some View {
        overlay(ConfettiView(trigger: trigger, origin: origin))
    }
}
