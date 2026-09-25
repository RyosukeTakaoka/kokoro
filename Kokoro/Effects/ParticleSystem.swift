import SwiftUI

/// 紙吹雪・メダル・火花・集まってくる光の粒をまとめて動かして描く。
/// SwiftUI の状態にはせず、TimelineView が毎フレーム `update` → `draw` を呼ぶ。
final class ParticleSystem {
    enum Kind {
        /// ひらひら舞う紙吹雪
        case confetti
        /// 下から噴き上がって落ちるメダル
        case coin
        /// 中心から弾ける火花
        case spark
        /// 画面の端から中心へ吸い込まれる光(タメ中)
        case ember
    }

    private struct Particle {
        var kind: Kind
        var x: Double
        var y: Double
        var vx: Double
        var vy: Double
        var age: Double = 0
        var life: Double
        var size: Double
        var hue: Double
        var rotation: Double
        var spin: Double
        var seed: Double
    }

    private struct Request {
        var kind: Kind
        var count: Int
        var origin: UnitPoint
        var power: Double
        var hue: Double?
    }

    private var particles: [Particle] = []
    private var requests: [Request] = []
    private var lastUpdate: Date?
    private let maxParticles = 1200

    var isEmpty: Bool { particles.isEmpty && requests.isEmpty }

    /// `origin` は画面に対する割合(0〜1)。`hue` を渡すとその色だけ、nil なら虹色。
    func burst(_ kind: Kind, count: Int, at origin: UnitPoint = .center, power: Double = 1, hue: Double? = nil) {
        requests.append(Request(kind: kind, count: count, origin: origin, power: power, hue: hue))
    }

    func clear() {
        particles.removeAll()
        requests.removeAll()
    }

    // MARK: 動かす

    func update(now: Date, size: CGSize) {
        let dt = min(1.0 / 30, max(0, now.timeIntervalSince(lastUpdate ?? now)))
        lastUpdate = now

        for r in requests { spawn(r, size: size) }
        requests.removeAll()

        let w = Double(size.width), h = Double(size.height)
        for i in particles.indices {
            var p = particles[i]
            p.age += dt
            switch p.kind {
            case .confetti:
                p.vy += 700 * dt
                p.vx *= exp(-1.6 * dt)
                p.vy *= exp(-1.2 * dt)
                p.x += (p.vx + sin(p.age * 7 + p.seed * 10) * 60) * dt
                p.y += p.vy * dt
            case .coin:
                p.vy += 1500 * dt
                p.x += p.vx * dt
                p.y += p.vy * dt
            case .spark:
                p.vx *= exp(-3.2 * dt)
                p.vy *= exp(-3.2 * dt)
                p.vy += 120 * dt
                p.x += p.vx * dt
                p.y += p.vy * dt
            case .ember:
                // 目標(生まれたときの origin を vx/vy に入れてある)へ加速しながら吸い込まれる
                let tx = p.vx, ty = p.vy
                let k = min(1, dt * (2 + 10 * p.age / p.life))
                p.x += (tx - p.x) * k
                p.y += (ty - p.y) * k
            }
            p.rotation += p.spin * dt
            particles[i] = p
        }
        particles.removeAll { $0.age >= $0.life || $0.y > h + 80 || $0.x < -120 || $0.x > w + 120 }
    }

    private func spawn(_ r: Request, size: CGSize) {
        let w = Double(size.width), h = Double(size.height)
        let ox = Double(r.origin.x) * w, oy = Double(r.origin.y) * h
        let room = max(0, maxParticles - particles.count)
        for _ in 0..<min(r.count, room) {
            let hue = r.hue ?? Double.random(in: 0..<1)
            switch r.kind {
            case .confetti:
                let a = Double.random(in: -Double.pi * 0.95 ... -Double.pi * 0.05)
                let speed = Double.random(in: 350...1050) * r.power
                particles.append(Particle(kind: .confetti, x: ox, y: oy, vx: cos(a) * speed, vy: sin(a) * speed,
                                          life: Double.random(in: 2.4...3.8), size: Double.random(in: 7...13),
                                          hue: hue, rotation: Double.random(in: 0...6), spin: Double.random(in: -9...9),
                                          seed: Double.random(in: 0...1)))
            case .coin:
                let x = ox + Double.random(in: -w * 0.35...w * 0.35)
                particles.append(Particle(kind: .coin, x: x, y: oy, vx: Double.random(in: -160...160),
                                          vy: -Double.random(in: 700...1250) * r.power,
                                          life: 2.2, size: Double.random(in: 16...24), hue: 0.13,
                                          rotation: Double.random(in: 0...6), spin: Double.random(in: 8...16),
                                          seed: Double.random(in: 0...1)))
            case .spark:
                let a = Double.random(in: 0..<(2 * Double.pi))
                let speed = Double.random(in: 250...1100) * r.power
                particles.append(Particle(kind: .spark, x: ox, y: oy, vx: cos(a) * speed, vy: sin(a) * speed,
                                          life: Double.random(in: 0.45...1.0), size: Double.random(in: 2...4.5),
                                          hue: hue, rotation: 0, spin: 0, seed: 0))
            case .ember:
                // 画面の外周のどこかから
                let a = Double.random(in: 0..<(2 * Double.pi))
                let radius = max(w, h) * Double.random(in: 0.55...0.8)
                particles.append(Particle(kind: .ember, x: ox + cos(a) * radius, y: oy + sin(a) * radius,
                                          vx: ox, vy: oy, life: Double.random(in: 0.6...1.0),
                                          size: Double.random(in: 2.5...5), hue: hue, rotation: 0, spin: 0,
                                          seed: 0))
            }
        }
    }

    // MARK: 描く

    func draw(in context: GraphicsContext) {
        for p in particles {
            let fadeIn = min(1, p.age / 0.05)
            let fadeOut = min(1, (p.life - p.age) / 0.4)
            let alpha = max(0, min(fadeIn, fadeOut))
            var c = context
            c.opacity = alpha
            switch p.kind {
            case .confetti:
                c.translateBy(x: p.x, y: p.y)
                c.rotate(by: .radians(p.rotation))
                // 裏返るように縦幅を揺らす
                let flip = max(0.15, abs(cos(p.rotation * 1.3 + p.seed * 6)))
                let rect = CGRect(x: -p.size / 2, y: -p.size * 0.3 * flip, width: p.size, height: p.size * 0.6 * flip)
                c.fill(Path(rect), with: .color(Color(hue: p.hue, saturation: 0.85, brightness: 1)))
            case .coin:
                c.translateBy(x: p.x, y: p.y)
                let squash = max(0.12, abs(cos(p.rotation)))
                let rect = CGRect(x: -p.size / 2 * squash, y: -p.size / 2, width: p.size * squash, height: p.size)
                c.fill(Path(ellipseIn: rect), with: .linearGradient(
                    Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.6), Color(red: 1, green: 0.72, blue: 0.1),
                                      Color(red: 0.7, green: 0.45, blue: 0.05)]),
                    startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
                c.stroke(Path(ellipseIn: rect.insetBy(dx: p.size * 0.12 * squash, dy: p.size * 0.12)),
                         with: .color(Color(red: 1, green: 0.9, blue: 0.4).opacity(0.9)), lineWidth: 1.2)
            case .spark:
                c.blendMode = .plusLighter
                let len = 0.035
                var path = Path()
                path.move(to: CGPoint(x: p.x, y: p.y))
                path.addLine(to: CGPoint(x: p.x - p.vx * len, y: p.y - p.vy * len))
                c.stroke(path, with: .color(Color(hue: p.hue, saturation: 0.6, brightness: 1)),
                         style: StrokeStyle(lineWidth: p.size, lineCap: .round))
            case .ember:
                c.blendMode = .plusLighter
                let r = p.size * (1 + p.age / p.life)
                c.fill(Path(ellipseIn: CGRect(x: p.x - r * 2, y: p.y - r * 2, width: r * 4, height: r * 4)),
                       with: .color(Color(hue: p.hue, saturation: 0.8, brightness: 1).opacity(0.25)))
                c.fill(Path(ellipseIn: CGRect(x: p.x - r / 2, y: p.y - r / 2, width: r, height: r)),
                       with: .color(.white))
            }
        }
    }
}
