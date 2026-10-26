//
//  TVMatchView.swift
//  stashyTV
//
//  Match (Hot or Not) for Apple TV. Same `HotOrNotViewModel` as iOS
//  (`stashy/HotOrNotToolsView.swift`): pairing, Ascension-style rating math and the
//  `rating100` + `hotornot_stats` / `performer_record` custom-field writes are shared, only
//  the screen is TV-specific — two large cards side by side, focus left/right, select picks
//  the winner and the next pair loads in place.
//

import SwiftUI

struct TVMatchView: View {
    @StateObject private var model = HotOrNotViewModel()
    @ObservedObject private var appearance = AppearanceManager.shared
    @Environment(\.tvNavigationPath) private var path
    @Environment(\.tvContentWidth) private var contentWidth
    /// A pop back from a performer page must not draw a new pair.
    @State private var didRunInitialLoad = false
    /// `true` = left card, `false` = right card. Entering the screen lands on the left card.
    @FocusState private var focusedCard: Bool?

    private static let horizontalPadding: CGFloat = 60
    private static let columnSpacing: CGFloat = 60

    private var sectionOptions: [TVPickerOption<HotOrNotViewModel.Section>] {
        HotOrNotViewModel.Section.allCases.map { TVPickerOption($0, $0.rawValue) }
    }

    private var modeOptions: [TVPickerOption<HotOrNotViewModel.DuelMode>] {
        HotOrNotViewModel.DuelMode.allCases.map { TVPickerOption($0, $0.label) }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                header

                if let err = model.errorMessage {
                    Text(err)
                        .font(.headline)
                        .foregroundStyle(.red)
                }

                switch model.section {
                case .battle:
                    battleContent
                case .leaderboard:
                    leaderboardContent
                case .settings:
                    settingsContent
                }
            }
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 60).focusable(false) }
        .defaultFocus($focusedCard, true)
        .background(TVThemeFill())
        .onAppear {
            guard !didRunInitialLoad else { return }
            didRunInitialLoad = true
            Task {
                await model.loadDuelPair()
                await model.refreshLeaderboard()
            }
        }
        .onChange(of: model.selectedGenders) { _, _ in
            Task {
                await model.loadDuelPair()
                await model.refreshLeaderboard()
            }
        }
        .onChange(of: model.duelMode) { _, _ in
            model.resetClimbStatePreservingMode()
            Task { await model.loadDuelPair() }
        }
        .onChange(of: model.section) { _, newSection in
            if newSection == .leaderboard {
                Task { await model.refreshLeaderboard() }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 24) {
            Text("Match")
                .font(.largeTitle)
                .fontWeight(.bold)

            if let status = statusLine {
                Text(status)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if model.section == .battle {
                TVOptionPickerButton(
                    title: "Mode",
                    icon: "flame.fill",
                    options: modeOptions,
                    selection: $model.duelMode
                )
            }
            TVOptionPickerButton(
                title: "Section",
                icon: "square.grid.2x2",
                options: sectionOptions,
                selection: $model.section
            )
        }
        .focusSection()
    }

    /// Pool size and the running ladder, next to the title.
    private var statusLine: String? {
        guard model.section == .battle else {
            if model.section == .leaderboard, model.leaderboardTotalCount > 0 {
                return "\(model.leaderboardTotalCount) performers"
            }
            return nil
        }
        var parts: [String] = [model.duelMode.label]
        if model.poolCount > 0 { parts.append("\(model.poolCount) in pool") }
        if model.duelMode != .headToHead, model.climbChampion != nil || model.climbFalling {
            parts.append(model.climbFalling ? "falling" : "\(model.climbWins) wins")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Game

    private var columnWidth: CGFloat {
        let available = contentWidth - 2 * Self.horizontalPadding - Self.columnSpacing
        return max(600, available / 2)
    }

    @ViewBuilder
    private var battleContent: some View {
        if let victor = model.climbVictory {
            victoryCard(victor)
        } else if model.needsPlacementStarterSelection {
            placementStarters
        } else if model.isLoadingPair && model.left == nil {
            loadingBox("Loading pair…")
        } else if let l = model.left, let r = model.right {
            VStack(alignment: .leading, spacing: 32) {
                HStack(alignment: .top, spacing: Self.columnSpacing) {
                    battleColumn(l, rank: model.rankLeft, feedback: model.duelFeedback?.left, leftWins: true)
                    battleColumn(r, rank: model.rankRight, feedback: model.duelFeedback?.right, leftWins: false)
                }
                .focusSection()

                duelActions
                    .focusSection()
            }
        }
    }

    private func battleColumn(
        _ performer: HotOrNotPerformerData,
        rank: Int?,
        feedback: HotOrNotDuelVoteFeedback.Side?,
        leftWins: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Never `.disabled` while a vote is submitting: a disabled button drops focus, and
            // the remote would jump to the chrome between pairs.
            Button {
                guard !model.isSubmitting, !model.isLoadingPair else { return }
                Task { await model.choose(leftWins: leftWins) }
            } label: {
                TVMatchBattleCard(
                    performer: performer,
                    imageURL: model.thumbnailURL(for: performer),
                    rank: rank,
                    feedback: feedback,
                    width: columnWidth
                )
            }
            .buttonStyle(.card)
            .focused($focusedCard, equals: leftWins)
            .accessibilityLabel("Choose \(performer.displayName)")

            Button {
                path?.wrappedValue.append(TVPerformerLink(id: performer.id, name: performer.name))
            } label: {
                TVMatchActionLabel(icon: "person.crop.rectangle", title: "Profile")
            }
            .buttonStyle(.card)
        }
        .frame(width: columnWidth, alignment: .leading)
    }

    /// Draw / New pair / Stop — same set per mode as iOS.
    private var duelActions: some View {
        HStack(spacing: 24) {
            if model.duelMode == .champion {
                actionButton("Stop", icon: "stop.circle") {
                    model.startNewClimbRun()
                }
            } else {
                actionButton("Draw", icon: "equal.circle") {
                    Task { await model.skipDraw() }
                }
            }

            if model.duelMode == .placement {
                actionButton("Stop", icon: "stop.circle") {
                    model.startNewClimbRun()
                }
            } else {
                actionButton("New pair", icon: "arrow.triangle.2.circlepath") {
                    guard !model.isLoadingPair else { return }
                    Task { await model.loadDuelPair() }
                }
            }
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            guard !model.isSubmitting else { return }
            action()
        } label: {
            TVMatchActionLabel(icon: icon, title: title)
        }
        .buttonStyle(.card)
    }

    private func victoryCard(_ victor: HotOrNotPerformerData) -> some View {
        HStack(alignment: .center, spacing: 48) {
            TVMatchPhoto(url: model.thumbnailURL(for: victor), rank: nil)
                .frame(width: 300, height: 400)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 20) {
                Text("Legend!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text(victor.displayName)
                    .font(.title2)
                Text("\(model.climbWins) wins · cleared the ladder")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Button {
                    model.startNewClimbRun()
                } label: {
                    TVMatchActionLabel(icon: "arrow.clockwise", title: "New run")
                }
                .buttonStyle(.card)
                .padding(.top, 12)
            }
        }
        .focusSection()
    }

    @ViewBuilder
    private var placementStarters: some View {
        if model.isLoadingPlacementStarters && model.placementStarters.isEmpty {
            loadingBox("Loading starters…")
        } else if model.placementStarters.isEmpty {
            ContentUnavailableView(
                "No starters",
                systemImage: "person.2.slash",
                description: Text(model.errorMessage ?? "")
            )
        } else {
            VStack(alignment: .leading, spacing: 24) {
                Text("Pick a performer to start the Rise run")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 32) {
                    ForEach(Array(model.placementStarters.prefix(6)), id: \.id) { p in
                        Button {
                            guard !model.isSubmitting else { return }
                            model.pickPlacementStarter(p)
                        } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                TVMatchPhoto(url: model.thumbnailURL(for: p), rank: nil)
                                    .frame(width: 240, height: 320)
                                    .clipped()
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(p.displayName)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text("Rating \(p.rating100 ?? 50)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                .padding(16)
                                .frame(width: 240, alignment: .leading)
                            }
                            .background(TVThemeFill(role: .secondary))
                        }
                        .buttonStyle(.card)
                        .accessibilityLabel("Pick \(p.displayName) as Rise starter")
                    }
                }
                .focusSection()
            }
        }
    }

    // MARK: - Charts

    @ViewBuilder
    private var leaderboardContent: some View {
        if model.isLoadingBoard && model.leaderboard.isEmpty {
            loadingBox("Loading charts…")
        } else if model.leaderboard.isEmpty {
            ContentUnavailableView("No performers", systemImage: "list.number")
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 520), spacing: 40)],
                alignment: .leading,
                spacing: 40
            ) {
                ForEach(Array(model.leaderboard.enumerated()), id: \.element.id) { index, p in
                    Button {
                        path?.wrappedValue.append(TVPerformerLink(id: p.id, name: p.name))
                    } label: {
                        TVMatchLeaderboardRow(
                            performer: p,
                            imageURL: model.thumbnailURL(for: p),
                            place: index + 1
                        )
                    }
                    .buttonStyle(.card)
                    .onAppear {
                        if index >= model.leaderboard.count - 4 {
                            Task { await model.loadMoreLeaderboard() }
                        }
                    }
                }
            }
            .focusSection()

            if model.isLoadingMoreLeaderboard {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Settings

    private static let genderRows: [(code: String, label: String)] = [
        ("FEMALE", "Female"),
        ("MALE", "Male"),
        ("TRANSGENDER_FEMALE", "Transgender (female)"),
        ("TRANSGENDER_MALE", "Transgender (male)"),
        ("NON_BINARY", "Non-binary"),
        ("INTERSEX", "Intersex")
    ]

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Genders in pool")
                .font(.title3)
                .fontWeight(.semibold)
            ForEach(Self.genderRows, id: \.code) { row in
                let isOn = model.selectedGenders.contains(row.code)
                Button {
                    model.toggleGender(row.code)
                } label: {
                    HStack {
                        Text(row.label)
                            .font(.headline)
                        Spacer()
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isOn ? appearance.tintColor : .secondary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.card)
            }
            Text("At least one gender stays selected. Performers without an image are left out.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 900, alignment: .leading)
        .focusSection()
    }

    private func loadingBox(_ message: String) -> some View {
        VStack(spacing: 20) {
            ProgressView()
            Text(message)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }
}

// MARK: - Cards

/// Photo plus the same fixed 3×2 facts as the iOS battle card, side by side.
private struct TVMatchBattleCard: View {
    let performer: HotOrNotPerformerData
    let imageURL: URL?
    let rank: Int?
    let feedback: HotOrNotDuelVoteFeedback.Side?
    let width: CGFloat

    private static let height: CGFloat = 520

    private var photoWidth: CGFloat { Self.height * 3 / 4 }

    var body: some View {
        ZStack {
            HStack(alignment: .top, spacing: 0) {
                TVMatchPhoto(url: imageURL, rank: rank)
                    .frame(width: photoWidth, height: Self.height)
                    .clipped()

                VStack(alignment: .leading, spacing: 24) {
                    Text(performer.displayName)
                        .font(.title3)
                        .fontWeight(.bold)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)

                    LazyVGrid(
                        columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                        alignment: .leading,
                        spacing: 20
                    ) {
                        ForEach(Array(hotOrNotBattleFixedInfoRows(performer).enumerated()), id: \.offset) { _, row in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(row.value)
                                    .font(.headline)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            if let feedback {
                Rectangle()
                    .fill(tint(for: feedback.delta100))
                VStack(spacing: 8) {
                    Text(feedback.delta100 > 0 ? "+\(feedback.delta100)" : "\(feedback.delta100)")
                        .font(.system(size: 96, weight: .heavy))
                        .monospacedDigit()
                    Text("SCORE")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .opacity(0.9)
                    Text("\(feedback.rating100After)")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .monospacedDigit()
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                .transition(.opacity)
            }
        }
        .frame(width: width, height: Self.height)
        .background(TVThemeFill(role: .secondary))
    }

    private func tint(for delta100: Int) -> Color {
        if delta100 > 0 { return Color.green.opacity(0.45) }
        if delta100 < 0 { return Color.red.opacity(0.45) }
        return Color.gray.opacity(0.4)
    }
}

private struct TVMatchPhoto: View {
    let url: URL?
    let rank: Int?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.gray.opacity(0.2)
            if let url {
                CustomAsyncImage(url: url) { loader in
                    if let image = loader.image {
                        image.resizable().scaledToFill()
                    } else if loader.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
            if let rank {
                Text("#\(rank)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(16)
            }
        }
    }

    private var placeholder: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 80))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TVMatchLeaderboardRow: View {
    let performer: HotOrNotPerformerData
    let imageURL: URL?
    let place: Int

    private var s: HotOrNotStats { performer.stats }

    private var streakLine: String? {
        let parts: [String] = [
            s.current_streak != 0 ? "Current \(s.current_streak > 0 ? "+" : "")\(s.current_streak)" : nil,
            s.best_streak > 0 ? "Best +\(s.best_streak)" : nil,
            s.worst_streak < 0 ? "Worst \(s.worst_streak)" : nil
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            TVMatchPhoto(url: imageURL, rank: place)
                .frame(width: 150, height: 200)
                .clipped()

            VStack(alignment: .leading, spacing: 12) {
                Text(performer.displayName)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 16) {
                    stat("Rating", "\(performer.rating100 ?? 50)")
                    stat("Duels", "\(s.total_matches)")
                    stat("W", "\(s.wins)")
                    stat("L", "\(s.losses)")
                    stat("D", "\(s.draws)")
                }
                if let streakLine {
                    Text(streakLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 200)
        .background(TVThemeFill(role: .secondary))
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(minWidth: 56)
    }
}

/// Wide label for the card-styled action buttons on the Match and RateMe screens.
struct TVMatchActionLabel: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .padding(.horizontal, 32)
        .frame(minWidth: 220, minHeight: 72)
    }
}
