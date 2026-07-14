import Foundation

enum IntradayState: Equatable {
    case attacking
    case pullingBack
    case recovering
    case relativelyStrong
    case sideways
    case relativelyWeak
    case fallingBack
    case declining
    case rebounding
    case opening
    case preOpen
    case lunchBreak
    case closed
    case marketClosed
    case insufficientData

    var displayName: String {
        switch self {
        case .attacking: return "上攻"
        case .pullingBack: return "回踩"
        case .recovering: return "回升"
        case .relativelyStrong: return "偏强"
        case .sideways: return "震荡"
        case .relativelyWeak: return "偏弱"
        case .fallingBack: return "回落"
        case .declining: return "下行"
        case .rebounding: return "反抽"
        case .opening: return "开盘"
        case .preOpen: return "待开"
        case .lunchBreak: return "午休"
        case .closed: return "收盘"
        case .marketClosed: return "休市"
        case .insufficientData: return "数据"
        }
    }

    var requiresConfirmation: Bool {
        switch self {
        case .attacking, .pullingBack, .recovering, .relativelyStrong, .sideways,
             .relativelyWeak, .fallingBack, .declining, .rebounding:
            return true
        case .opening, .preOpen, .lunchBreak, .closed, .marketClosed, .insufficientData:
            return false
        }
    }
}

enum IntradayAction: Equatable {
    case hold
    case observe
    case watch
    case waitForStability
    case stayOut
    case cautious
    case riskControl
    case avoid
    case doNotChase
    case review
    case wait

    var displayName: String {
        switch self {
        case .hold: return "持有"
        case .observe: return "观察"
        case .watch: return "关注"
        case .waitForStability: return "等稳"
        case .stayOut: return "观望"
        case .cautious: return "谨慎"
        case .riskControl: return "风控"
        case .avoid: return "回避"
        case .doNotChase: return "勿追"
        case .review: return "复盘"
        case .wait: return "等待"
        }
    }
}

enum IntradaySignalColorRole: Equatable {
    case up
    case down
    case warning
    case neutral
}

struct IntradaySignalMetrics: Equatable {
    let averageDeviation: Double
    let dayPosition: Double
    let return5: Double?
    let return15: Double?
    let return30: Double?
    let volumeRatio: Double?
    let mainNetInflow: Double?
    let sectorChangePercent: Double?
    let score: Double?
}

struct IntradaySignal: Equatable {
    let state: IntradayState
    let action: IntradayAction
    let colorRole: IntradaySignalColorRole
    let metrics: IntradaySignalMetrics?
    let updatedAt: Date

    var displayText: String {
        "\(state.displayName)/\(action.displayName)"
    }

    var helpText: String {
        var lines = [
            "盘面：\(state.displayName)",
            "操作倾向：\(action.displayName)",
        ]

        if let metrics {
            lines.append("均价偏离 \(Self.signedPercent(metrics.averageDeviation))")
            lines.append(String(format: "日内位置 %.0f%%", metrics.dayPosition * 100))

            let momentum = [
                metrics.return5.map { "5分 \(Self.signedPercent($0))" },
                metrics.return15.map { "15分 \(Self.signedPercent($0))" },
                metrics.return30.map { "30分 \(Self.signedPercent($0))" },
            ].compactMap { $0 }
            if !momentum.isEmpty {
                lines.append(momentum.joined(separator: "  "))
            }

            if let ratio = metrics.volumeRatio {
                lines.append(String(format: "量比 %.2fx", ratio))
            }
            if let amount = metrics.mainNetInflow {
                let direction = amount > 0 ? "净流入" : amount < 0 ? "净流出" : "持平"
                lines.append("资金方向：\(direction)")
            }
            if let sector = metrics.sectorChangePercent {
                lines.append("板块方向：\(Self.signedPercent(sector / 100))")
            }
        }

        lines.append("更新：\(Self.timeFormatter.string(from: updatedAt))")
        lines.append("操作仅供盘面参考")
        return lines.joined(separator: "\n")
    }

    private static func signedPercent(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return String(format: "\(sign)%.2f%%", value * 100)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

struct IntradaySignalInput {
    let points: [MinutePoint]
    let currentPrice: Double?
    let quoteIsToday: Bool
    let preClose: Double
    let volumeRatio: Double?
    let mainNetInflow: Double?
    let sectorChangePercent: Double?
    let isHolding: Bool
    let now: Date
    let intradayLoadedAt: Date?
    let fundFlowLoadedAt: Date?
    let fundFlowMaxAge: TimeInterval
}

struct IntradaySignalStabilizer {
    private(set) var confirmedSignal: IntradaySignal?
    private var pendingState: IntradayState?
    private var pendingCount = 0

    mutating func reset() {
        confirmedSignal = nil
        pendingState = nil
        pendingCount = 0
    }

    mutating func update(_ next: IntradaySignal) -> IntradaySignal {
        guard let confirmedSignal else {
            self.confirmedSignal = next
            return next
        }

        guard next.state.requiresConfirmation, confirmedSignal.state.requiresConfirmation else {
            self.confirmedSignal = next
            pendingState = nil
            pendingCount = 0
            return next
        }

        if confirmedSignal.state == next.state {
            self.confirmedSignal = next
            pendingState = nil
            pendingCount = 0
            return next
        }

        if pendingState == next.state {
            pendingCount += 1
        } else {
            pendingState = next.state
            pendingCount = 1
        }

        if pendingCount >= 2 {
            self.confirmedSignal = next
            pendingState = nil
            pendingCount = 0
            return next
        }

        return confirmedSignal
    }
}

enum IntradaySignalService {
    private enum SessionPhase {
        case preOpen
        case trading
        case lunchBreak
        case closed
        case marketClosed
    }

    static func evaluate(_ input: IntradaySignalInput) -> IntradaySignal {
        let phase = sessionPhase(at: input.now, quoteIsToday: input.quoteIsToday)
        switch phase {
        case .preOpen:
            return statusSignal(state: .preOpen, isHolding: input.isHolding, now: input.now)
        case .lunchBreak:
            return statusSignal(state: .lunchBreak, isHolding: input.isHolding, now: input.now)
        case .closed:
            return statusSignal(state: .closed, isHolding: input.isHolding, now: input.now)
        case .marketClosed:
            return statusSignal(state: .marketClosed, isHolding: input.isHolding, now: input.now)
        case .trading:
            break
        }

        guard input.quoteIsToday else {
            return statusSignal(state: .marketClosed, isHolding: input.isHolding, now: input.now)
        }
        guard let loadedAt = input.intradayLoadedAt,
              input.now.timeIntervalSince(loadedAt) <= 180 else {
            return statusSignal(state: .insufficientData, isHolding: input.isHolding, now: input.now)
        }

        var validPoints = input.points
            .filter { $0.price.isFinite && $0.price > 0 }
            .sorted { $0.id < $1.id }
        guard !validPoints.isEmpty, input.preClose.isFinite, input.preClose > 0 else {
            return statusSignal(state: .insufficientData, isHolding: input.isHolding, now: input.now)
        }

        if let currentPrice = input.currentPrice,
           input.quoteIsToday,
           currentPrice.isFinite,
           currentPrice > 0,
           let last = validPoints.last {
            validPoints[validPoints.count - 1] = MinutePoint(
                id: last.id,
                time: last.time,
                price: currentPrice
            )
        }

        let fundFlowIsFresh = input.fundFlowLoadedAt.map {
            input.now.timeIntervalSince($0) <= input.fundFlowMaxAge
        } ?? false
        let volumeRatio = fundFlowIsFresh ? input.volumeRatio.flatMap(validNonnegative) : nil
        let mainNetInflow = fundFlowIsFresh ? input.mainNetInflow.flatMap(validFinite) : nil
        let sectorChangePercent = fundFlowIsFresh
            ? input.sectorChangePercent.flatMap(validFinite)
            : nil

        guard validPoints.count >= 16 else {
            return statusSignal(state: .opening, isHolding: input.isHolding, now: input.now)
        }

        let current = validPoints[validPoints.count - 1].price
        let average = validPoints.map(\.price).reduce(0, +) / Double(validPoints.count)
        let high = max(validPoints.map(\.price).max() ?? current, current)
        let low = min(validPoints.map(\.price).min() ?? current, current)
        let range = high - low
        let position = range > 0 ? clamp((current - low) / range, lower: 0, upper: 1) : 0.5
        let averageDeviation = (current - average) / average
        let dayReturn = (current - input.preClose) / input.preClose
        let return5 = returnOver(minutes: 5, points: validPoints, current: current)
        let return15 = returnOver(minutes: 15, points: validPoints, current: current)
        let return30 = returnOver(minutes: 30, points: validPoints, current: current)

        guard let return5, let return15 else {
            return statusSignal(state: .opening, isHolding: input.isHolding, now: input.now)
        }

        let peakGain = (high - input.preClose) / input.preClose
        let drawdownFromHigh = (high - current) / high
        let troughLoss = (low - input.preClose) / input.preClose
        let reboundFromLow = (current - low) / low
        let upConfirmed = volumeRatio.map { $0 >= 1.0 } ?? mainNetInflow.map { $0 > 0 } ?? false
        let downConfirmed = volumeRatio.map { $0 >= 1.0 } ?? mainNetInflow.map { $0 < 0 } ?? false

        let state: IntradayState
        var score: Double?
        if peakGain >= 0.008,
           drawdownFromHigh >= 0.006,
           position <= 0.45,
           averageDeviation <= -0.001,
           return5 <= -0.0015 {
            state = .fallingBack
        } else if troughLoss <= -0.005,
                  reboundFromLow >= 0.008,
                  averageDeviation >= 0.001,
                  return5 >= 0.0015,
                  return15 > 0 {
            state = .recovering
        } else if averageDeviation >= 0.0015,
                  position >= 0.70,
                  return5 >= 0,
                  return15 >= 0.002,
                  upConfirmed {
            state = .attacking
        } else if averageDeviation <= -0.0015,
                  position <= 0.30,
                  return5 <= 0,
                  return15 <= -0.002,
                  downConfirmed {
            state = .declining
        } else if dayReturn > 0,
                  averageDeviation >= 0,
                  position >= 0.50,
                  return30.map({ $0 >= 0.003 }) == true,
                  return5 <= -0.001,
                  return15 >= -0.002 {
            state = .pullingBack
        } else if dayReturn < 0,
                  averageDeviation < 0,
                  position <= 0.60,
                  return30.map({ $0 <= -0.003 }) == true,
                  return5 >= 0.001 {
            state = .rebounding
        } else {
            let averageStrength = clamp(averageDeviation / 0.01, lower: -1, upper: 1)
            let positionStrength = 2 * position - 1
            let momentumStrength = clamp(return15 / 0.01, lower: -1, upper: 1)
            let dayStrength = clamp(dayReturn / 0.03, lower: -1, upper: 1)
            let volumeMultiplier: Double
            if let volumeRatio, volumeRatio < 0.8 {
                volumeMultiplier = 0.9
            } else if let volumeRatio, volumeRatio > 1.5 {
                volumeMultiplier = 1.1
            } else {
                volumeMultiplier = 1
            }
            let rawScore = 100 * (
                0.35 * averageStrength
                + 0.30 * positionStrength
                + 0.20 * momentumStrength
                + 0.15 * dayStrength
            ) * volumeMultiplier
            score = clamp(rawScore, lower: -100, upper: 100)
            if rawScore >= 25 {
                state = .relativelyStrong
            } else if rawScore <= -25 {
                state = .relativelyWeak
            } else {
                state = .sideways
            }
        }

        let metrics = IntradaySignalMetrics(
            averageDeviation: averageDeviation,
            dayPosition: position,
            return5: return5,
            return15: return15,
            return30: return30,
            volumeRatio: volumeRatio,
            mainNetInflow: mainNetInflow,
            sectorChangePercent: sectorChangePercent,
            score: score
        )
        return IntradaySignal(
            state: state,
            action: action(for: state, isHolding: input.isHolding),
            colorRole: colorRole(for: state),
            metrics: metrics,
            updatedAt: input.now
        )
    }

    private static func statusSignal(
        state: IntradayState,
        isHolding: Bool,
        now: Date
    ) -> IntradaySignal {
        IntradaySignal(
            state: state,
            action: action(for: state, isHolding: isHolding),
            colorRole: colorRole(for: state),
            metrics: nil,
            updatedAt: now
        )
    }

    private static func action(for state: IntradayState, isHolding: Bool) -> IntradayAction {
        switch state {
        case .attacking: return isHolding ? .hold : .doNotChase
        case .pullingBack: return isHolding ? .observe : .waitForStability
        case .recovering: return isHolding ? .observe : .watch
        case .relativelyStrong: return isHolding ? .hold : .observe
        case .sideways: return .stayOut
        case .relativelyWeak: return isHolding ? .cautious : .avoid
        case .fallingBack: return isHolding ? .cautious : .avoid
        case .declining: return isHolding ? .riskControl : .avoid
        case .rebounding: return isHolding ? .cautious : .doNotChase
        case .opening, .preOpen, .lunchBreak: return .observe
        case .closed, .marketClosed: return .review
        case .insufficientData: return .wait
        }
    }

    private static func colorRole(for state: IntradayState) -> IntradaySignalColorRole {
        switch state {
        case .attacking, .recovering, .relativelyStrong:
            return .up
        case .fallingBack, .declining, .relativelyWeak:
            return .down
        case .pullingBack, .rebounding:
            return .warning
        case .sideways, .opening, .preOpen, .lunchBreak, .closed, .marketClosed, .insufficientData:
            return .neutral
        }
    }

    private static func returnOver(
        minutes: Int,
        points: [MinutePoint],
        current: Double
    ) -> Double? {
        guard let currentId = points.last?.id else { return nil }
        let targetId = currentId - minutes
        guard let base = points.last(where: { $0.id <= targetId }), base.price > 0 else { return nil }
        return (current - base.price) / base.price
    }

    private static func sessionPhase(at date: Date, quoteIsToday: Bool) -> SessionPhase {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let weekday = calendar.component(.weekday, from: date)
        guard weekday != 1, weekday != 7 else { return .marketClosed }

        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let minuteOfDay = hour * 60 + minute

        switch minuteOfDay {
        case ..<(9 * 60 + 30):
            return .preOpen
        case (9 * 60 + 30)..<(11 * 60 + 30), (13 * 60)..<(15 * 60):
            return quoteIsToday ? .trading : .marketClosed
        case (11 * 60 + 30)..<(13 * 60):
            return quoteIsToday ? .lunchBreak : .marketClosed
        default:
            return quoteIsToday ? .closed : .marketClosed
        }
    }

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    private static func validFinite(_ value: Double) -> Double? {
        value.isFinite ? value : nil
    }

    private static func validNonnegative(_ value: Double) -> Double? {
        value.isFinite && value >= 0 ? value : nil
    }
}
