//
//  OCountHeatmapCard.swift
//  stashy
//
//  Month-calendar heatmap of Stash scene + image O-Count, matching Abstand's listening calendar.
//

#if !os(tvOS)
import SwiftUI
import UIKit

struct OCountHeatmapToolsView: View {
    @ObservedObject private var configManager = ServerConfigManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView {
                    Task { await OCountHeatmapLoader.shared.reload() }
                }
            } else {
                ScrollView {
                    OCountHeatmapCard()
                        .toolsHorizontalPadding(horizontalSizeClass)
                        .padding(.top, DesignTokens.Tools.menuTopPadding)
                        .padding(.bottom, DesignTokens.Tools.menuBottomPadding)
                        .frame(maxWidth: DesignTokens.Tools.regularMaxContentWidth)
                        .frame(maxWidth: .infinity)
                }
                .refreshable {
                    await OCountHeatmapLoader.shared.reload()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .applyAppBackground()
    }
}

private enum OCountHeatmapMetrics {
    static let cardPaddingH: CGFloat = 12
    static let cardPaddingV: CGFloat = 12
    static let navRowHeight: CGFloat = 36
    static let weekdayHeaderHeight: CGFloat = 16
    static let legendHeight: CGFloat = 14
    static let legendTopPadding: CGFloat = 8
    static let minColumnGap: CGFloat = 4
    static let rowGap: CGFloat = 4
    static let dayCellScale: CGFloat = 0.84
    static let bodySpacing: CGFloat = 8
}

struct OCountHeatmapCard: View {
    @ObservedObject private var loader = OCountHeatmapLoader.shared
    @ObservedObject private var appearance = AppearanceManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let locale = Locale(identifier: "en_US")
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.locale = locale
        return calendar
    }

    @State private var monthsBack = 0
    @State private var cardWidth: CGFloat = 0
    @State private var selectedDayKey: String?
    @State private var didAutoJump = false

    private var isRegularWidth: Bool { horizontalSizeClass == .regular }
    private var accent: Color { appearance.tintColor }

    private var currentMonthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
    }

    private var visibleMonthStart: Date {
        calendar.date(byAdding: .month, value: -monthsBack, to: currentMonthStart) ?? currentMonthStart
    }

    private var maxMonthsBack: Int {
        guard let earliest = loader.earliestMonthStart() else { return 0 }
        return max(0, calendar.dateComponents([.month], from: earliest, to: currentMonthStart).month ?? 0)
    }

    private var canGoBack: Bool { monthsBack < maxMonthsBack }
    private var canGoForward: Bool { monthsBack > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isRegularWidth {
                HStack(alignment: .top, spacing: 12) {
                    calendarCard
                        .frame(maxWidth: isRegularWidth ? 520 : .infinity, alignment: .leading)
                    summaryCard
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                calendarCard
                summaryCard
            }

            if selectedDayKey != nil {
                dayItemsList
            }
        }
        .task {
            await loader.loadIfNeeded()
            autoJumpToLatestMonthIfNeeded()
        }
        .onChange(of: monthsBack) { _, _ in
            syncSelectedDay(for: loader.monthHeatmap(forMonthContaining: visibleMonthStart))
        }
        .onChange(of: loader.countsByDay) { _, _ in
            autoJumpToLatestMonthIfNeeded()
            if monthsBack > maxMonthsBack { monthsBack = maxMonthsBack }
            syncSelectedDay(for: loader.monthHeatmap(forMonthContaining: visibleMonthStart))
        }
    }

    private var calendarCard: some View {
        let heatmap = loader.monthHeatmap(forMonthContaining: visibleMonthStart)
        return VStack(alignment: .leading, spacing: 8) {
            OCountMonthTitleView(
                title: heatmap.monthTitle,
                canGoBack: canGoBack,
                canGoForward: canGoForward,
                showsJumpToCurrent: monthsBack > 0,
                onBack: { monthsBack += 1 },
                onForward: { monthsBack -= 1 },
                onJumpToCurrent: {
                    monthsBack = 0
                    selectedDayKey = nil
                }
            )

            Group {
                if loader.isLoading && loader.countsByDay.isEmpty {
                    StandardLoadingView(message: "Loading O-Count...")
                        .frame(maxWidth: .infinity)
                        .frame(height: OCountMonthHeatmapLayout.estimatedCalendarCardHeight(containerWidth: 320, rowCount: 6))
                } else if cardWidth > 1 {
                    calendarContent(cardWidth: cardWidth)
                } else {
                    Color.clear
                        .frame(height: OCountMonthHeatmapLayout.estimatedCalendarCardHeight(containerWidth: 320, rowCount: 6))
                }
            }
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: OCountHeatmapWidthKey.self, value: geo.size.width)
            }
        )
        .background(Color.secondaryAppBackground(for: appearance.currentTheme))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .cardShadow()
        .onPreferenceChange(OCountHeatmapWidthKey.self) { cardWidth = $0 }
    }

    private var summaryCard: some View {
        let heatmap = loader.monthHeatmap(forMonthContaining: visibleMonthStart)
        let summary = summaryContent(heatmap: heatmap)
        return VStack(alignment: .leading, spacing: 4) {
            Text(summary.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(2)
            Text(summary.value)
                .font(.title2.monospacedDigit().weight(.bold))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondaryAppBackground(for: appearance.currentTheme))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .cardShadow()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summary.accessibility)
        .animation(.easeInOut(duration: 0.15), value: selectedDayKey)
    }

    @ViewBuilder
    private var dayItemsList: some View {
        let items = selectedDayKey.map { loader.items(onDayKey: $0) } ?? []
        let scenes = items.filter { $0.kind == .scene }
        let images = items.filter { $0.kind == .image }

        if items.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if !scenes.isEmpty {
                    dayItemsSection(title: "Scenes", items: scenes)
                }
                if !images.isEmpty {
                    dayItemsSection(title: "Images", items: images)
                }
            }
        }
    }

    private func dayItemsSection(title: String, items: [OCountHeatmapItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            LazyVGrid(columns: DesignTokens.Tools.rankedColumns(for: horizontalSizeClass), spacing: 8) {
                ForEach(items) { item in
                    NavigationLink {
                        OCountMediaDestination(item: item)
                    } label: {
                        OCountDayItemRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func calendarContent(cardWidth: CGFloat) -> some View {
        let heatmap = loader.monthHeatmap(forMonthContaining: visibleMonthStart)
        let layout = OCountMonthHeatmapLayout.make(
            heatmap: heatmap,
            containerWidth: cardWidth,
            locale: locale,
            calendar: calendar
        )

        VStack(alignment: .center, spacing: OCountHeatmapMetrics.bodySpacing) {
            weekdayHeaderRow(layout: layout)
            monthGrid(layout: layout, heatmap: heatmap)
                .frame(maxWidth: .infinity, alignment: .center)
            legend(blockSize: layout.blockSize)
        }
        .padding(.horizontal, OCountHeatmapMetrics.cardPaddingH)
        .padding(.bottom, OCountHeatmapMetrics.cardPaddingV)
        .frame(maxWidth: .infinity)
        .frame(height: layout.calendarCardHeight, alignment: .top)
    }

    private func weekdayHeaderRow(layout: OCountMonthHeatmapLayout) -> some View {
        HStack(spacing: layout.columnGap) {
            ForEach(0..<7, id: \.self) { col in
                Text(layout.weekdayLabel(column: col))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: layout.blockSize, height: OCountHeatmapMetrics.weekdayHeaderHeight)
            }
        }
        .frame(width: layout.gridWidth, alignment: .center)
    }

    private func monthGrid(layout: OCountMonthHeatmapLayout, heatmap: OCountMonthHeatmap) -> some View {
        VStack(spacing: layout.rowGap) {
            ForEach(0..<heatmap.rowCount, id: \.self) { row in
                HStack(spacing: layout.columnGap) {
                    ForEach(0..<7, id: \.self) { col in
                        dayCell(
                            heatmap.cell(column: col, row: row),
                            blockSize: layout.blockSize,
                            isSelected: heatmap.cell(column: col, row: row)?.id == selectedDayKey
                        )
                    }
                }
            }
        }
        .frame(width: layout.gridWidth, alignment: .center)
    }

    private func dayCell(_ cell: OCountMonthHeatmap.Cell?, blockSize: CGFloat, isSelected: Bool) -> some View {
        let level = cell?.colorLevel ?? 0
        let inMonth = cell?.isInDisplayedMonth ?? false
        let day = cell?.day ?? 0
        let dayFont = max(8, blockSize * 0.38)

        let dayContent = ZStack {
            Circle()
                .fill(fillColor(level: inMonth ? level : 0))
                .overlay {
                    Circle()
                        .strokeBorder(outlineColor(level: inMonth ? level : 0), lineWidth: 0.5)
                }
            if isSelected {
                Circle().strokeBorder(accent, lineWidth: 2)
            }
            if day > 0 {
                Text("\(day)")
                    .font(.system(size: dayFont, weight: isSelected ? .semibold : .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(dayNumberColor(level: level, inMonth: inMonth, isSelected: isSelected))
            }
        }
        .frame(width: blockSize, height: blockSize)
        .opacity(inMonth ? 1 : 0.35)

        return Group {
            if inMonth, let cell {
                Button {
                    selectedDayKey = selectedDayKey == cell.id ? nil : cell.id
                } label: {
                    dayContent
                }
                .buttonStyle(.plain)
                .accessibilityLabel(cell.accessibilityLabel)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            } else {
                dayContent
                    .accessibilityLabel(cell?.accessibilityLabel ?? "No data")
            }
        }
    }

    private func legend(blockSize: CGFloat) -> some View {
        let dot = min(9, max(5, blockSize * 0.45))
        return HStack(spacing: 3) {
            Text("Less")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(0..<5, id: \.self) { level in
                Circle()
                    .fill(fillColor(level: level))
                    .overlay {
                        Circle().strokeBorder(outlineColor(level: level), lineWidth: 0.5)
                    }
                    .frame(width: dot, height: dot)
            }
            Text("More")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.top, OCountHeatmapMetrics.legendTopPadding)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func summaryContent(heatmap: OCountMonthHeatmap) -> (title: String, value: String, accessibility: String) {
        if let key = selectedDayKey,
           let cell = heatmap.cells.first(where: { $0.id == key && $0.isInDisplayedMonth }) {
            return (
                selectedDayTitle(key),
                countLabel(cell.count),
                "\(selectedDayTitle(key)), \(countLabel(cell.count))"
            )
        }
        return (
            "O-Count",
            countLabel(heatmap.totalInMonth),
            "\(heatmap.monthTitle), \(heatmap.daysWithOCount) days, \(countLabel(heatmap.totalInMonth))"
        )
    }

    private func selectedDayTitle(_ key: String) -> String {
        guard let date = OCountHeatmapLoader.parseDayKey(key, calendar: calendar) else { return key }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    private func countLabel(_ count: Int) -> String {
        count > 0 ? "\(count)" : "No O-Count"
    }

    private func autoJumpToLatestMonthIfNeeded() {
        guard !didAutoJump else { return }
        didAutoJump = true
        let current = loader.monthHeatmap(forMonthContaining: currentMonthStart)
        guard current.totalInMonth == 0, let latest = loader.latestMonthStart() else { return }
        let months = calendar.dateComponents([.month], from: latest, to: currentMonthStart).month ?? 0
        monthsBack = max(0, months)
    }

    private func syncSelectedDay(for heatmap: OCountMonthHeatmap) {
        if let key = selectedDayKey,
           heatmap.cells.contains(where: { $0.id == key && $0.isInDisplayedMonth }) {
            return
        }
        selectedDayKey = nil
    }

    private func fillColor(level: Int) -> Color {
        let dark = colorScheme == .dark
        let uiAccent = UIColor(accent)
        switch level {
        case 1: return Color(uiAccent.withAlphaComponent(dark ? 0.38 : 0.32))
        case 2: return Color(uiAccent.withAlphaComponent(dark ? 0.56 : 0.50))
        case 3: return Color(uiAccent.withAlphaComponent(dark ? 0.78 : 0.72))
        case 4: return accent
        default: return Color.primary.opacity(dark ? 0.08 : 0.06)
        }
    }

    private func outlineColor(level: Int) -> Color {
        if level == 0 { return Color.primary.opacity(0.12) }
        return accent.opacity(colorScheme == .dark ? 0.35 : 0.5)
    }

    private func dayNumberColor(level: Int, inMonth: Bool, isSelected: Bool) -> Color {
        guard inMonth else { return Color.secondary.opacity(0.5) }
        if level >= 3 {
            return contrastingOnAccent
        }
        return isSelected ? Color.primary : Color.secondary
    }

    private var contrastingOnAccent: Color {
        #if canImport(UIKit)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(accent).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.62 ? Color.black : Color.white
        #else
        return .white
        #endif
    }
}

private struct OCountMonthTitleView: View {
    let title: String
    let canGoBack: Bool
    let canGoForward: Bool
    let showsJumpToCurrent: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let onJumpToCurrent: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(canGoBack ? Color.primary : Color.secondary.opacity(0.35))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!canGoBack)
            .accessibilityLabel("Previous month")

            titleLabel
                .frame(maxWidth: .infinity)

            Button(action: onForward) {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(canGoForward ? Color.primary : Color.secondary.opacity(0.35))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!canGoForward)
            .accessibilityLabel("Next month")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var titleLabel: some View {
        let label = Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

        if showsJumpToCurrent {
            Button(action: onJumpToCurrent) {
                label
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityHint("Shows the current month.")
        } else {
            label.accessibilityAddTraits(.isHeader)
        }
    }
}

private struct OCountHeatmapWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

private struct OCountMonthHeatmapLayout {
    let blockSize: CGFloat
    let columnGap: CGFloat
    let rowGap: CGFloat
    let gridWidth: CGFloat
    let weekdayLabels: [String]
    let calendarCardHeight: CGFloat

    static func make(
        heatmap: OCountMonthHeatmap,
        containerWidth: CGFloat,
        locale: Locale,
        calendar: Calendar
    ) -> OCountMonthHeatmapLayout {
        var cal = calendar
        cal.locale = locale
        let contentWidth = max(0, containerWidth - 2 * OCountHeatmapMetrics.cardPaddingH)
        let n = CGFloat(heatmap.columnCount)
        let minGap = OCountHeatmapMetrics.minColumnGap
        let rawBlock = max(24, (contentWidth - (n - 1) * minGap) / n)
        let block = floor(rawBlock * OCountHeatmapMetrics.dayCellScale)
        let used = n * block
        let columnGap = n > 1 ? max(minGap, (contentWidth - used) / (n - 1)) : 0
        let rowGap = OCountHeatmapMetrics.rowGap
        let gridWidth = n * block + max(0, n - 1) * columnGap

        let allSymbols = cal.shortWeekdaySymbols.count == 7
            ? cal.shortWeekdaySymbols
            : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let firstIdx = cal.firstWeekday - 1
        let weekdays = (0..<7).map { allSymbols[(firstIdx + $0) % 7] }

        return OCountMonthHeatmapLayout(
            blockSize: block,
            columnGap: columnGap,
            rowGap: rowGap,
            gridWidth: gridWidth,
            weekdayLabels: weekdays,
            calendarCardHeight: estimatedCalendarCardHeight(
                block: block,
                rowCount: max(heatmap.rowCount, 1),
                rowGap: rowGap
            )
        )
    }

    static func estimatedCalendarCardHeight(containerWidth: CGFloat, rowCount: Int) -> CGFloat {
        let contentWidth = max(0, containerWidth - 2 * OCountHeatmapMetrics.cardPaddingH)
        let rawBlock = max(24, (contentWidth - 6 * OCountHeatmapMetrics.minColumnGap) / 7)
        let block = floor(rawBlock * OCountHeatmapMetrics.dayCellScale)
        return estimatedCalendarCardHeight(block: block, rowCount: rowCount, rowGap: OCountHeatmapMetrics.rowGap)
    }

    private static func estimatedCalendarCardHeight(block: CGFloat, rowCount: Int, rowGap: CGFloat) -> CGFloat {
        let rows = CGFloat(rowCount)
        let gridH = rows * block + max(0, rows - 1) * rowGap
        return OCountHeatmapMetrics.cardPaddingV
            + OCountHeatmapMetrics.weekdayHeaderHeight
            + OCountHeatmapMetrics.bodySpacing
            + gridH
            + OCountHeatmapMetrics.bodySpacing
            + OCountHeatmapMetrics.legendTopPadding
            + OCountHeatmapMetrics.legendHeight
    }

    func weekdayLabel(column: Int) -> String {
        guard column >= 0, column < weekdayLabels.count else { return "" }
        return String(weekdayLabels[column].prefix(2))
    }
}

private struct OCountDayItemRow: View {
    let item: OCountHeatmapItem
    @ObservedObject private var appearance = AppearanceManager.shared

    private var thumbHeight: CGFloat { 56 }
    private var thumbWidth: CGFloat {
        item.kind == .scene ? thumbHeight * 16 / 9 : thumbHeight
    }

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: thumbWidth, height: thumbHeight)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: DesignTokens.CornerRadius.card,
                        bottomLeadingRadius: DesignTokens.CornerRadius.card,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if item.kind == .image, !item.performers.isEmpty {
                    performerLine
                } else {
                    Text(item.rowSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(item.countOnDay)")
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(.primary)
        }
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondaryAppBackground(for: appearance.currentTheme))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .cardShadow()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.kindTitle), \(item.displayTitle)\(item.rowSubtitle == item.kindTitle ? "" : ", \(item.rowSubtitle)")\(item.performerNamesLine.isEmpty ? "" : ", \(item.performerNamesLine)"), \(item.countOnDay)")
        .accessibilityHint("Opens this \(item.kindTitle.lowercased()).")
    }

    private var thumbnail: some View {
        ZStack {
            Color.gray.opacity(DesignTokens.Opacity.placeholder)
            if let url = item.thumbnailURL {
                CustomAsyncImage(url: url) { loader in
                    if loader.isLoading {
                        InlineSpinner(scale: .medium)
                    } else if let image = loader.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: thumbWidth, height: thumbHeight)
        .clipped()
    }

    private var performerLine: some View {
        Text(item.title == "Untitled" ? item.kindTitle : item.performerNamesLine)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var placeholder: some View {
        Image(systemName: item.placeholderSystemImage)
            .font(.title3)
            .foregroundStyle(Color.appAccent.opacity(0.45))
    }
}

struct OCountMediaDestination: View {
    let item: OCountHeatmapItem

    var body: some View {
        switch item.kind {
        case .scene:
            SceneDetailView(scene: item.asScene)
        case .image:
            OCountImageDestination(item: item)
        }
    }
}

struct OCountImageDestination: View {
    let imageId: String
    private let stub: StashImage
    @State private var images: [StashImage]
    @State private var isReady: Bool

    init(item: OCountHeatmapItem) {
        let stub = item.asImage
        self.imageId = stub.id
        self.stub = stub
        _images = State(initialValue: [stub])
        _isReady = State(initialValue: Self.isPlayable(stub))
    }

    var body: some View {
        Group {
            if isReady {
                FullScreenImageView(images: $images, selectedImageId: imageId)
            } else {
                ZStack {
                    Color.black.ignoresSafeArea()
                    StandardLoadingView(message: "Loading...")
                }
            }
        }
        .task { await hydrate() }
    }

    private static func isPlayable(_ image: StashImage) -> Bool {
        image.visual_files != nil || image.paths?.image != nil || image.isVideo
    }

    @MainActor
    private func hydrate() async {
        let query = """
        query FindImageById($id: ID!) {
          findImage(id: $id) {
            ...ImageFields
          }
        }
        """ + "\n" + GraphQLQueries.loadQuery(named: "fragment_ImageFields")
        do {
            let response: OCountFindImageResponse = try await GraphQLClient.shared.execute(
                query: query,
                variables: ["id": imageId]
            )
            guard var full = response.data?.findImage else {
                isReady = true
                return
            }
            guard let idx = images.firstIndex(where: { $0.id == full.id }) else {
                images = [full]
                isReady = true
                return
            }
            let current = images[idx]
            if current.rating100 != stub.rating100 {
                full = full.withRating(current.rating100)
            }
            if current.o_counter != stub.o_counter {
                full = full.withOCounter(current.o_counter)
            }
            images[idx] = full
            isReady = true
        } catch {
            print("❌ O-Count image hydrate: \(error)")
            isReady = true
        }
    }
}

private struct OCountFindImageResponse: Decodable {
    let data: Payload?
    struct Payload: Decodable {
        let findImage: StashImage?
    }
}

#endif
