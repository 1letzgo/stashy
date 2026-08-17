//
//  SessionTimelineToolsView.swift
//  stashy
//
//  Tools → Timeline: last 24h of Stash plays, then older windows on demand.
//

#if !os(tvOS)
import SwiftUI

struct SessionTimelineToolsView: View {
    @ObservedObject private var loader = SessionTimelineLoader.shared
    @ObservedObject private var configManager = ServerConfigManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView {
                    Task { await loader.reload() }
                }
            } else {
                timelineList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .applyAppBackground()
        .task { await loader.loadIfNeeded() }
    }

    private var timelineList: some View {
        ScrollView {
            LazyVStack(alignment: horizontalSizeClass == .regular ? .center : .leading, spacing: 28) {
                if loader.isLoading && loader.sessions.isEmpty {
                    StandardLoadingView(message: "Loading timeline...")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if loader.didFail && loader.sessions.isEmpty {
                    Text("Could not load play history from this server.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if loader.sessions.isEmpty {
                    Text("No plays in the last 24 hours.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    ForEach(Self.days(from: loader.sessions)) { day in
                        TimelineDayBlock(day: day)
                    }
                }

                if loader.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else if loader.hasMore, !loader.sessions.isEmpty, !loader.isLoading {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            Task { await loader.loadMore() }
                        }
                }
            }
            .toolsHorizontalPadding(horizontalSizeClass)
            .padding(.top, DesignTokens.Tools.menuTopPadding)
            .padding(.bottom, DesignTokens.Tools.menuBottomPadding + 12)
            .frame(maxWidth: DesignTokens.Tools.regularMaxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .refreshable {
            await loader.reload()
        }
    }

    private static func days(from sessions: [TimelineSession]) -> [TimelineDayGroup] {
        let calendar = Calendar.current
        var grouped: [(day: Date, sessions: [TimelineSession])] = []
        for session in sessions {
            let day = calendar.startOfDay(for: session.startedAt)
            if let index = grouped.firstIndex(where: { $0.day == day }) {
                grouped[index].sessions.append(session)
            } else {
                grouped.append((day, [session]))
            }
        }
        return grouped.map { TimelineDayGroup(day: $0.day, sessions: $0.sessions) }
    }
}

private struct TimelineDayGroup: Identifiable {
    let day: Date
    let sessions: [TimelineSession]
    var id: Date { day }
}

private struct TimelineDayBlock: View {
    let day: TimelineDayGroup
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegular: Bool { horizontalSizeClass == .regular }

    var body: some View {
        VStack(alignment: isRegular ? .center : .leading, spacing: 18) {
            Text(Self.dayFormatter.string(from: day.day))
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: isRegular ? .center : .leading)

            ForEach(day.sessions) { session in
                TimelineSessionBlock(session: session)
            }
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "EEEE, d MMM"
        return formatter
    }()
}

private struct TimelineSessionBlock: View {
    let session: TimelineSession
    @ObservedObject private var appearance = AppearanceManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegular: Bool { horizontalSizeClass == .regular }

    var body: some View {
        VStack(alignment: isRegular ? .center : .leading, spacing: 14) {
            header
            TimelineSpine(visits: session.visits)
        }
        .frame(maxWidth: isRegular ? 720 : .infinity)
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        VStack(alignment: isRegular ? .center : .leading, spacing: 6) {
            Text(Self.clockRange(session.startedAt, session.endedAt))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
            statsRow
        }
        .frame(maxWidth: .infinity, alignment: isRegular ? .center : .leading)
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            stat(Self.clock(session.sessionSeconds), label: "session")
            stat(Self.clock(session.watchedSeconds), label: "watched")
            stat("\(session.sceneCount)", label: session.sceneCount == 1 ? "scene" : "scenes")
            if session.oCount > 0 {
                Label {
                    Text("\(session.oCount)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                } icon: {
                    Image(systemName: appearance.oCounterIconFilled)
                        .font(.caption)
                }
                .foregroundStyle(appearance.tintColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: isRegular ? .center : .leading)
    }

    private func stat(_ value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    static func clockTime(_ date: Date) -> String {
        timeFormatter.timeZone = .current
        return timeFormatter.string(from: date)
    }

    static func clockRange(_ start: Date, _ end: Date) -> String {
        "\(clockTime(start)) – \(clockTime(end))"
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func watchedLabel(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60.0).rounded()))
        if minutes < 60 { return "\(minutes)m watched" }
        return "\(minutes / 60)h \(minutes % 60)m watched"
    }

    static func watchedLine(for visit: TimelineVisit) -> String {
        let watched = watchedLabel(visit.watchedSeconds)
        guard let start = visit.sceneStartSeconds, start >= 5 else { return watched }
        return "started at \(clock(start))  ·  \(watched)"
    }
}

private struct TimelineSpine: View {
    let visits: [TimelineVisit]
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ObservedObject private var appearance = AppearanceManager.shared

    private var isRegular: Bool { sizeClass == .regular }

    var body: some View {
        VStack(spacing: 16) {
            ForEach(visits) { visit in
                TimelineVisitRow(visit: visit, largeThumb: isRegular)
            }
        }
        .background(alignment: .leading) {
            if !isRegular {
                Rectangle()
                    .fill(appearance.tintColor.opacity(0.9))
                    .frame(width: 2)
                    .padding(.leading, 9)
            }
        }
    }
}

private struct TimelineVisitRow: View {
    let visit: TimelineVisit
    let largeThumb: Bool

    var body: some View {
        NavigationLink {
            SceneDetailView(scene: visit.scene.asScene)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                timeNode
                TimelineVisitCard(visit: visit, thumbWidth: largeThumb ? 176 : 128)
            }
        }
        .buttonStyle(.plain)
    }

    private var timeNode: some View {
        Text(TimelineSessionBlock.clockTime(visit.startedAt))
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
            .zIndex(1)
    }
}

private struct TimelineVisitCard: View {
    let visit: TimelineVisit
    var thumbWidth: CGFloat = 128
    @ObservedObject private var appearance = AppearanceManager.shared

    private var thumbHeight: CGFloat { thumbWidth * 9 / 16 }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            thumbnail
            textColumn
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: thumbHeight)
        .background(Color.secondaryAppBackground(for: appearance.currentTheme))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .cardShadow()
        .contentShape(Rectangle())
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(visit.scene.displayTitle)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let studio = visit.scene.studio?.name, !studio.isEmpty {
                Text(studio)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(TimelineSessionBlock.watchedLine(for: visit))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if visit.oCount > 0 {
                oCountLine
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var oCountLine: some View {
        HStack(spacing: 6) {
            if let stamp = visit.oCountTimes.last {
                Text(TimelineSessionBlock.clockTime(stamp))
                    .font(.caption2.monospacedDigit())
            }
            Image(systemName: appearance.oCounterIconFilled)
                .font(.caption2)
            if visit.oCount > 1 {
                Text("×\(visit.oCount)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
            }
        }
        .foregroundStyle(appearance.tintColor)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var thumbnail: some View {
        ZStack {
            Color.gray.opacity(DesignTokens.Opacity.placeholder)
            if let url = visit.scene.thumbnailURL {
                CustomAsyncImage(url: url) { loader in
                    if loader.isLoading {
                        InlineSpinner(scale: .medium)
                    } else if let image = loader.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "film")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "film")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: thumbWidth, height: thumbHeight)
        .clipped()
    }
}
#endif
