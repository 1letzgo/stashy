//
//  SessionTimelineToolsView.swift
//  stashy
//
//  Tools → Timeline: server scene plays, O-counts, and markers.
//

#if !os(tvOS)
import SwiftUI

struct SessionTimelineToolsView: View {
    @ObservedObject private var loader = SessionTimelineLoader.shared
    @ObservedObject private var configManager = ServerConfigManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var enabledKinds: Set<TimelineKind> = TimelineKind.savedFilter()

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
        .task { await loader.reload() }
        .onChange(of: enabledKinds) { _, kinds in
            TimelineKind.saveFilter(kinds)
        }
        .onChange(of: configManager.activeConfig?.id) { _, _ in
            loader.reset()
            Task { await loader.reload() }
        }
    }

    private var visibleDays: [TimelineDayGroup] {
        Self.days(from: loader.sessions.compactMap { $0.filtered(to: enabledKinds) })
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
                } else if visibleDays.isEmpty {
                    Text(loader.sessions.isEmpty
                         ? "No plays, O-counts, or markers in the last 24 hours."
                         : "No matching activity for the selected filters.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    ForEach(visibleDays) { day in
                        TimelineDayBlock(day: day)
                    }
                }

                if loader.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else if loader.hasMore, !loader.isLoading, !loader.sessions.isEmpty {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            Task { await loader.loadMore() }
                        }
                }
            }
            .toolsHorizontalPadding(horizontalSizeClass)
            .padding(.bottom, DesignTokens.Tools.menuBottomPadding + 12)
            .frame(maxWidth: DesignTokens.Tools.regularMaxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            TimelineFilterChipRow(enabled: $enabledKinds)
                .toolsHorizontalPadding(horizontalSizeClass)
                .padding(.top, DesignTokens.Tools.menuTopPadding)
                .padding(.bottom, 10)
                .frame(maxWidth: DesignTokens.Tools.regularMaxContentWidth)
                .frame(maxWidth: .infinity)
                .background(TimelineFilterBarBackground())
        }
        .refreshable {
            await loader.reload()
        }
        .scrollBounceBehavior(.always)
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

private struct TimelineFilterBarBackground: View {
    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        Color.appBackground(for: appearance.currentTheme)
    }
}

private struct TimelineFilterChipRow: View {
    @Binding var enabled: Set<TimelineKind>
    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        HStack(spacing: StashyExpandingDock.itemSpacing) {
            ForEach(TimelineKind.allCases) { kind in
                let selected = enabled.contains(kind)
                Button {
                    HapticManager.selection()
                    toggle(kind)
                } label: {
                    Text(kind.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selected ? appearance.tintColor : Color.secondary.opacity(0.15))
                                .shadow(
                                    color: selected ? appearance.tintColor.opacity(0.35) : .clear,
                                    radius: 4,
                                    x: 0,
                                    y: 2
                                )
                        )
                        .clipShape(Capsule(style: .continuous))
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(kind.label)\(selected ? ", selected" : "")")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func toggle(_ kind: TimelineKind) {
        if enabled.contains(kind) {
            guard enabled.count > 1 else { return }
            enabled.remove(kind)
        } else {
            enabled.insert(kind)
        }
    }
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
            if session.sessionSeconds >= 1 {
                stat(Self.clock(session.sessionSeconds), label: "session")
            }
            if session.watchedSeconds >= 15 {
                stat(Self.clock(session.watchedSeconds), label: "watched")
            }
            if session.sceneCount > 0 {
                stat("\(session.sceneCount)", label: session.sceneCount == 1 ? "scene" : "scenes")
            }
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
            if session.markerCount > 0 {
                Label {
                    Text("\(session.markerCount)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                } icon: {
                    Image(systemName: "bookmark.fill")
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

    static func watchedLine(for visit: TimelineVisit) -> String? {
        guard visit.isPlayback else { return nil }
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
    @ObservedObject private var appearance = AppearanceManager.shared

    private var isOCountAction: Bool { !visit.isPlayback }

    var body: some View {
        NavigationLink {
            OCountMediaDestination(item: visit.scene.asHeatmapItem)
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
            .foregroundStyle(isOCountAction ? appearance.tintColor : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                TimelineActionSurface(isOCountAction: isOCountAction)
                    .clipShape(Capsule())
            }
            .overlay(
                Capsule().stroke(
                    isOCountAction ? appearance.tintColor.opacity(0.28) : Color.primary.opacity(0.1),
                    lineWidth: 0.5
                )
            )
            .zIndex(1)
    }
}

private struct TimelineVisitCard: View {
    let visit: TimelineVisit
    var thumbWidth: CGFloat = 128
    @ObservedObject private var appearance = AppearanceManager.shared

    private var isOCountAction: Bool { !visit.isPlayback }
    private var cardHeight: CGFloat { thumbWidth * 9 / 16 }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            thumbnail
            textColumn
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: cardHeight)
        .background {
            TimelineActionSurface(isOCountAction: isOCountAction)
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                .stroke(
                    isOCountAction ? appearance.tintColor.opacity(0.28) : Color.primary.opacity(0.1),
                    lineWidth: 0.5
                )
        )
        .overlay(alignment: .bottomTrailing) {
            if visit.isMarkerAction {
                markerBadge
            } else if visit.isPlayback {
                HStack(spacing: 2) {
                    if visit.oCount > 0 {
                        oCountBadge
                    }
                    playBadge
                }
            } else if visit.oCount > 0 {
                oCountBadge
            }
        }
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

            Spacer(minLength: 0)

            if let line = TimelineSessionBlock.watchedLine(for: visit) {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let subtitle = visit.markerTitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let subtitle = visit.scene.studioName {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
    }

    private var playBadge: some View {
        Image(systemName: "play.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .allowsHitTesting(false)
    }

    private var markerBadge: some View {
        Image(systemName: "bookmark.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(appearance.tintColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .allowsHitTesting(false)
            .accessibilityLabel("Marker created")
    }

    private var oCountBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: appearance.oCounterIconFilled)
                .font(.caption.weight(.semibold))
            if visit.oCount > 1 {
                Text("×\(visit.oCount)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
            }
        }
        .foregroundStyle(appearance.tintColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var thumbnail: some View {
        ZStack(alignment: .leading) {
            if let url = visit.scene.thumbnailURL {
                CustomAsyncImage(url: url) { loader in
                    if loader.isLoading {
                        Color.gray.opacity(DesignTokens.Opacity.placeholder)
                            .overlay { InlineSpinner(scale: .medium) }
                    } else if let image = loader.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: thumbWidth, height: cardHeight)
                            .clipped()
                    } else {
                        placeholderThumb
                    }
                }
            } else {
                placeholderThumb
            }
        }
        .frame(width: thumbWidth, height: cardHeight, alignment: .leading)
        .clipped()
    }

    private var placeholderThumb: some View {
        Color.gray.opacity(DesignTokens.Opacity.placeholder)
            .overlay {
                Image(systemName: "film")
                    .foregroundStyle(.secondary)
            }
    }
}

private struct TimelineActionSurface: View {
    let isOCountAction: Bool
    @ObservedObject private var appearance = AppearanceManager.shared

    var body: some View {
        Color.secondaryAppBackground(for: appearance.currentTheme)
            .overlay(isOCountAction ? appearance.tintColor.opacity(0.14) : Color.clear)
    }
}
#endif
