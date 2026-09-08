import SwiftUI

/// The Today tab: twelve weeks of days, the hours of the day, and today's
/// tokens by model, from Claude Code's own stats cache. Read when shown.
struct TodayView: View {
    @State private var stats: ClaudeStats?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let stats {
                    let cells = stats.heatmap()
                    let modelTokens = stats.tokensToday()
                    Text("Messages per day · last 12 weeks").font(.headline)
                    Heatmap(cells: cells)
                    Text("Messages by hour of day").font(.headline)
                    HourHistogram(counts: stats.hours)
                    Text("Tokens today by model").font(.headline)
                    if modelTokens.isEmpty {
                        Text("Nothing for today yet in ~/.claude/stats-cache.json").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(modelTokens, id: \.model) { m in
                            HStack {
                                Text(m.model).font(.system(size: 11, design: .monospaced))
                                Spacer()
                                Text(formatTokens(m.tokens)).font(.system(size: 11, weight: .semibold))
                            }
                        }
                    }
                } else if loaded {
                    Text("No ~/.claude/stats-cache.json yet. Claude Code writes it as you use it.").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .onAppear {
            stats = ClaudeStats.load()
            loaded = true
        }
    }
}

struct Heatmap: View {
    var cells: [(date: Date, count: Int)]
    private let cell: CGFloat = 12
    private let gap: CGFloat = 3

    var body: some View {
        let peak = max(1, cells.map(\.count).max() ?? 1)
        let weeks = Int((Double(cells.count) / 7).rounded(.up))
        Canvas { ctx, _ in
            let firstWeekday = (7 - cells.count % 7) % 7
            for (i, c) in cells.enumerated() {
                let slot = i + firstWeekday
                let x = CGFloat(slot / 7) * (cell + gap)
                let y = CGFloat(slot % 7) * (cell + gap)
                let rect = CGRect(x: x, y: y, width: cell, height: cell)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(Heatmap.tone(c.count, peak: peak)))
            }
        }
        .frame(width: CGFloat(weeks) * (cell + gap), height: 7 * (cell + gap))
        .help("\(cells.reduce(0) { $0 + $1.count }) messages")
    }

    static func tone(_ count: Int, peak: Int) -> Color {
        guard count > 0 else { return Color.primary.opacity(0.08) }
        let level = min(1, Double(count) / Double(peak))
        return Color(red: 0.19, green: 0.64, blue: 0.42).opacity(0.25 + 0.75 * level)
    }
}

struct HourHistogram: View {
    var counts: [Int]

    var body: some View {
        let peak = max(1, counts.max() ?? 1)
        VStack(spacing: 2) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<24, id: \.self) { h in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(red: 0.36, green: 0.55, blue: 0.94).opacity(counts[h] == 0 ? 0.15 : 0.85))
                        .frame(height: max(2, 60 * CGFloat(counts[h]) / CGFloat(peak)))
                        .help("\(h):00 · \(counts[h])")
                }
            }
            .frame(height: 60, alignment: .bottom)
            HStack {
                Text("0").frame(maxWidth: .infinity, alignment: .leading)
                Text("6").frame(maxWidth: .infinity, alignment: .leading)
                Text("12").frame(maxWidth: .infinity, alignment: .leading)
                Text("18").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }
}
