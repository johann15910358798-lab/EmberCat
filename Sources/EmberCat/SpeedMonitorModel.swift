import AgentSpeedCore
import Combine
import Foundation

@MainActor
final class SpeedMonitorModel: ObservableObject {
    @Published private(set) var snapshot: SpeedSnapshot = .empty
    @Published private(set) var speed: Double = 0
    @Published private(set) var tier: SpeedTier = .idle
    @Published private(set) var peak: Double = 0
    @Published private(set) var todayOutput: Int = 0
    @Published private(set) var generatingCount: Int = 0
    @Published private(set) var toolsCount: Int = 0
    @Published private(set) var sourceCount: Int = 0
    @Published private(set) var modelName: String = "等待 Agent 输出"
    @Published private(set) var statusLine: String = "正在扫描本地会话"
    @Published private(set) var estimatedShare: Double = 0
    @Published private(set) var isDemo: Bool

    let store = SpeedStore()
    var onSnapshotChange: ((SpeedSnapshot) -> Void)?

    private var monitor: LiveMonitor?
    private var liveToken: UUID?
    private var demoTimer: Timer?
    private var demoStep = 0
    private let demoValues: [Double] = [0, 5.8, 13.4, 24.6, 39.2, 56.8, 76.4, 108.7, 72.1, 31.5, 7.2, 0]

    init() {
        isDemo = ProcessInfo.processInfo.environment["EMBERCAT_DEMO"] == "1"
    }

    func start() {
        guard liveToken == nil else { return }
        liveToken = store.addLiveListener { [weak self] snapshot in
            self?.apply(snapshot)
        }
        if isDemo {
            startDemo()
            return
        }
        let configuration = MonitorConfiguration(enabledSources: Set(SourceKind.allCases))
        let monitor = LiveMonitor(store: store, configuration: configuration)
        self.monitor = monitor
        monitor.start()
    }

    func shutdown() {
        demoTimer?.invalidate()
        demoTimer = nil
        monitor?.stop()
        monitor = nil
        if let liveToken {
            store.removeLiveListener(liveToken)
            self.liveToken = nil
        }
    }

    private func apply(_ snapshot: SpeedSnapshot) {
        let measured = max(0, snapshot.live.output)
        speed = measured
        tier = .forSpeed(measured)
        peak = max(snapshot.peakToday.output, snapshot.subsetPeaks.values.max() ?? 0)
        todayOutput = snapshot.today.output
        generatingCount = snapshot.generatingCount
        toolsCount = snapshot.toolsCount
        sourceCount = snapshot.sources.filter(\.available).count
        estimatedShare = snapshot.liveEstimatedShare

        let currentAgent = snapshot.agents
            .sorted { $0.lastActivity > $1.lastActivity }
            .first
        modelName = currentAgent?.model?.split(separator: "/").last.map(String.init)
            ?? currentAgent?.project
            ?? "等待 Agent 输出"

        switch snapshot.state {
        case .starting(let progress):
            let percent = Int((progress * 100).rounded())
            statusLine = "正在扫描本地会话 · \(percent)%"
        case .noSources:
            statusLine = "没有发现 Agent 会话"
        case .running:
            if measured > 0.5 {
                statusLine = generatingCount > 0 ? "\(modelName) · 正在生成" : "正在生成"
            } else if snapshot.toolsCount > 0 {
                statusLine = "工具执行中 · 速度暂时归零"
            } else {
                statusLine = "待机 · 随时准备起跑"
            }
        }

        // Publish the source breakdown and its total together, after applying this tick.
        self.snapshot = snapshot
        onSnapshotChange?(snapshot)
    }

    private func startDemo() {
        timerTick()
        let timer = Timer(timeInterval: 1.35, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.timerTick() }
        }
        timer.tolerance = 0.08
        RunLoop.main.add(timer, forMode: .common)
        demoTimer = timer
    }

    private func timerTick() {
        let value = demoValues[demoStep % demoValues.count]
        demoStep += 1
        var snapshot = SpeedSnapshot.empty
        snapshot.timestamp = Date()
        snapshot.state = .running
        snapshot.live = Rate(output: value, total: value * 1.18)
        snapshot.liveEstimatedShare = value > 0 ? 0.18 : 0
        snapshot.peakToday = Rate(output: 112.4, total: 138.2)
        snapshot.peakTodayAt = Date()
        snapshot.averageToday = 48.6
        snapshot.today = TokenTotals(requests: 18, input: 38_420, output: 21_936)
        snapshot.generatingCount = value > 0 ? 1 : 0
        snapshot.toolsCount = value == 0 ? 1 : 0
        if !store.isPreviewing { store.beginPreview() }
        store.publishPreview(snapshot)
    }
}
