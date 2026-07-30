import SwiftUI
import AppCore
import Localization
import SoundFontModel

/// One colored segment of a `StorageUsageBar` — either a real soundfont, an "Autres fichiers"
/// fold for whatever didn't get its own color slot, or a trailing "Espace libre" segment.
struct StorageSegment: Identifiable {
    let id: String
    let label: String
    let bytes: Int64
    let color: Color
}

/// A compact segmented bar (each segment's width proportional to its byte count) plus a small
/// legend below it — the in-app equivalent of macOS Storage settings' own disk-usage bar, one
/// segment per soundfont file. Categorical colors, assigned in a FIXED order (never re-cycled
/// per re-render) — see `StorageSegment.palette`.
///
/// When a user-set threshold applies (see `StorageSegment.build`), `thresholdFraction` draws a
/// vertical marker line at that position instead of/in addition to a "free" segment: usage under
/// the threshold shows a genuine gray "free up to my limit" segment (the threshold IS the bar's
/// total width then, so no separate marker is needed — the free segment's own left edge already
/// marks it); usage OVER the threshold has no free segment to show at all, so the marker line is
/// what indicates where the (exceeded) limit falls within the used space.
struct StorageUsageBar: View {
    let segments: [StorageSegment]
    let thresholdFraction: Double?
    let language: AppLanguage

    private var total: Int64 { segments.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        ForEach(segments) { segment in
                            let fraction = total > 0 ? Double(segment.bytes) / Double(total) : 0
                            Rectangle()
                                .fill(segment.color)
                                .frame(width: max(2, geometry.size.width * fraction))
                        }
                    }
                    if let thresholdFraction {
                        Rectangle()
                            .fill(Color.primary)
                            .frame(width: 2)
                            .offset(x: max(0, geometry.size.width * thresholdFraction - 1))
                    }
                }
            }
            .frame(height: 10)
            .background(Color.gray.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 3))

            VStack(alignment: .leading, spacing: 2) {
                ForEach(segments) { segment in
                    HStack(spacing: 4) {
                        Circle().fill(segment.color).frame(width: 6, height: 6)
                        Text(segment.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: segment.bytes, countStyle: .file))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

extension StorageSegment {
    /// Fixed-order categorical palette (dark-surface steps — this app always runs in dark mode,
    /// see `JamShackApp`'s own `.preferredColorScheme(.dark)`), validated for adjacent-pair
    /// colorblind-safety in stacked-bar contexts. Order is the safety mechanism: files are
    /// assigned slots in a stable order (by size, largest first), never re-cycled.
    static let palette: [Color] = [
        Color(hex: "3987E5"), // blue
        Color(hex: "D95926"), // orange
        Color(hex: "199E70"), // aqua
        Color(hex: "C98500"), // yellow
        Color(hex: "D55181"), // magenta
        Color(hex: "008300"), // green
        Color(hex: "9085E9"), // violet
        Color(hex: "E66767"), // red
    ]

    /// Builds segments (up to 7 individually-colored, largest first, the rest folded into one
    /// grey "Autres fichiers" segment) for `entries`, plus whichever of "free" segment /
    /// threshold marker applies:
    /// - `threshold` set, usage under it → a gray "Espace libre" segment sized
    ///   `threshold - usage` (the bar's total width IS the threshold in this case), no marker.
    /// - `threshold` set, usage at/over it → no free segment (nothing free to show), a marker
    ///   fraction at `threshold / usage` instead.
    /// - no `threshold` → falls back to `deviceFreeSpace` if given (local only; iCloud has none
    ///   to show — see `appHintPasDeQuotaICloud`), no marker.
    static func build(
        from entries: [SoundFontEntry], threshold: Int64?, deviceFreeSpace: Int64?, language: AppLanguage
    ) -> (segments: [StorageSegment], thresholdFraction: Double?) {
        let sorted = entries.filter { $0.fileSize > 0 }.sorted { $0.fileSize > $1.fileSize }
        let maxIndividual = 7
        var segments: [StorageSegment] = sorted.prefix(maxIndividual).enumerated().map { index, entry in
            StorageSegment(id: entry.hash, label: entry.displayName, bytes: entry.fileSize, color: palette[index])
        }
        if sorted.count > maxIndividual {
            let othersBytes = sorted[maxIndividual...].reduce(0) { $0 + $1.fileSize }
            segments.append(StorageSegment(
                id: "_other", label: L10n.string(.appLabelAutresFichiers, language), bytes: othersBytes, color: .gray
            ))
        }
        let used = segments.reduce(0) { $0 + $1.bytes }

        if let threshold, threshold > 0 {
            guard used < threshold else { return (segments, Double(threshold) / Double(max(used, 1))) }
            segments.append(StorageSegment(
                id: "_free", label: L10n.string(.appLabelEspaceLibre, language), bytes: threshold - used, color: Color.gray.opacity(0.35)
            ))
            return (segments, nil)
        }

        if let deviceFreeSpace {
            segments.append(StorageSegment(
                id: "_free", label: L10n.string(.appLabelEspaceLibre, language), bytes: deviceFreeSpace, color: Color.gray.opacity(0.35)
            ))
        }
        return (segments, nil)
    }
}
