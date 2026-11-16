import SwiftUI

/// A button in the detail header next to "Play as Channel" (favorite, rating, …).
struct TVDetailHeaderAction: Identifiable {
    let id: String
    let icon: String
    let title: String
    let perform: () -> Void
}

/// One fact of a detail page: a small label over its value ("Born" / "1990-04-02").
/// The header shows as many as fit in one line, the Details sheet shows all of them.
struct TVDetailFact: Identifiable {
    let id: String
    let label: String
    let value: String
    var icon: String? = nil
    var iconColor: Color = .secondary
}

/// The large image on the trailing side of the header. A studio logo is no backdrop
/// (it sits in the title line, `titleLogo`).
enum TVDetailBackdrop {
    case none
    case image(URL?)
}

/// Shared layout of the performer, studio, tag and group pages: the compact
/// `TVDetailHeader` (title with the scene count, one row of buttons, the facts in one line, an optional accessory such as the performer's tags, the image as backdrop) and the
/// scene grid right below — on 1920×1080 the first card row and the top of the second are
/// visible without scrolling. This view keeps the opening focus logic; the gallery page uses
/// the same header over its image grid.
struct TVGenericDetailView<Item: TVDetailItem, Accessory: View>: View {
    let item: Item?
    let isLoading: Bool
    let backdrop: TVDetailBackdrop
    /// Small image in the title line (a studio's logo).
    let titleLogo: AnyView?
    /// When set, the header offers continuous playback of everything in this scope.
    let channel: TVChannel?
    /// Header buttons present from the first frame (performer/studio: favorite and rating).
    /// Without the channel button the first one is the page's opening focus.
    let headerActions: [TVDetailHeaderAction]
    /// Buttons that may appear once the item has loaded (a group's cover switch). They
    /// come after `headerActions` and are never the focus anchor.
    let trailingActions: [TVDetailHeaderAction]
    /// Facts in the header line, in order of importance; what does not fit in the line
    /// moves to the Details sheet.
    let facts: [TVDetailFact]
    /// Facts only the Details sheet shows.
    let sheetFacts: [TVDetailFact]

    @State private var playingChannel: TVChannel?
    @ObservedObject private var stashyPlus = StashyPlusManager.shared
    @FocusState private var emptyFocus: Bool
    /// Start focus in the header. Without it tvOS put the first scene card in focus and
    /// scrolled the page down on open, cutting off the name and image.
    @FocusState private var headerFocus: Bool
    /// The invisible header anchor for pages without a channel button. Its own state: with
    /// the button and the container bound to one `@FocusState`, tvOS could neither claim
    /// the header programmatically nor move focus back up from the scene grid.
    @FocusState private var headerAnchorFocus: Bool
    /// Set once focus has left the header; from then on loading never pulls focus back.
    @State private var headerFocusReleased = false
    @Environment(\.tvContentWidth) private var contentWidth

    private var sceneSpec: TVGridSpec { .scenes }
    @Environment(\.dismiss) private var dismiss

    /// Der Kanal-Button ist im Leer-Zustand oft das einzige fokussierbare
    /// Element — fehlt er, muss der Zurück-Button den Fokus übernehmen.
    private var showsChannelButton: Bool { channel != nil && stashyPlus.isUnlocked }

    // Scenes related
    let scenes: [Scene]
    let isLoadingScenes: Bool
    let totalScenes: Int
    let hasMoreScenes: Bool
    let loadMoreScenes: () -> Void

    @ViewBuilder let headerAccessory: () -> Accessory

    init(
        item: Item?,
        isLoading: Bool,
        backdrop: TVDetailBackdrop = .none,
        titleLogo: AnyView? = nil,
        channel: TVChannel? = nil,
        headerActions: [TVDetailHeaderAction] = [],
        trailingActions: [TVDetailHeaderAction] = [],
        facts: [TVDetailFact],
        sheetFacts: [TVDetailFact] = [],
        scenes: [Scene],
        isLoadingScenes: Bool,
        totalScenes: Int,
        hasMoreScenes: Bool,
        loadMoreScenes: @escaping () -> Void,
        @ViewBuilder headerAccessory: @escaping () -> Accessory
    ) {
        self.item = item
        self.isLoading = isLoading
        self.backdrop = backdrop
        self.titleLogo = titleLogo
        self.channel = channel
        self.headerActions = headerActions
        self.trailingActions = trailingActions
        self.facts = facts
        self.sheetFacts = sheetFacts
        self.scenes = scenes
        self.isLoadingScenes = isLoadingScenes
        self.totalScenes = totalScenes
        self.hasMoreScenes = hasMoreScenes
        self.loadMoreScenes = loadMoreScenes
        self.headerAccessory = headerAccessory
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TVDetailMetrics.sectionGap) {
                TVDetailHeader(
                    title: item?.name ?? "",
                    titleLogo: titleLogo,
                    count: totalScenes > 0 ? TVDetailCount(value: totalScenes, icon: "film") : nil,
                    backdrop: backdrop,
                    isLoading: isLoading,
                    details: item?.details,
                    facts: facts,
                    sheetFacts: sheetFacts,
                    accessory: headerAccessory,
                    actions: { actionButtons }
                )

                // Scenes Section
                VStack(alignment: .leading, spacing: TVDetailMetrics.sectionTitleGap) {
                    TVDetailSectionTitle(text: tr("scenes"))

                    if isLoadingScenes && scenes.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView().scaleEffect(1.5)
                            Spacer()
                        }
                        .padding(.vertical, 60)
                        // Not focusable: the header (channel button or anchor) already gives
                        // the Menu key a target while loading. A focusable spinner took the
                        // opening focus, and when the grid replaced it tvOS moved focus to the
                        // first scene card and scrolled the page down.
                    } else if scenes.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 16) {
                                Image(systemName: "film")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                                Text(tr("empty_scenes_found"))
                                    .font(.title3)
                                    .foregroundStyle(.secondary)

                                // Fokus-Anker. Ohne ihn hat die Detailseite einer
                                // leeren Group/Tag/Studio gar kein fokussierbares
                                // Element, die Menu-Taste erreicht
                                // `tvExitDismissable` nicht und man kommt nicht
                                // mehr heraus. Gleiches Muster wie in
                                // `TVGalleryDetailView`.
                                Button(tr("back")) { dismiss() }
                                    .font(.title3)
                                    .focused($emptyFocus)
                                    .padding(.top, 8)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 60)
                        .onAppear {
                            guard !showsChannelButton else { return }
                            emptyFocus = true
                        }
                    } else {
                        LazyVGrid(columns: sceneSpec.columns(for: contentWidth), spacing: sceneSpec.spacing) {
                            ForEach(scenes) { scene in
                                VStack(alignment: .leading, spacing: 10) {
                                    TVNavButton(value: TVSceneLink(sceneId: scene.id)) {
                                        TVSceneCardView(scene: scene)
                                    }

                                    TVSceneCardTitleView(scene: scene)
                                }
                                .frame(width: sceneSpec.columnWidth)
                                .onAppear {
                                    if scene.id == scenes.last?.id && hasMoreScenes {
                                        loadMoreScenes()
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, sceneSpec.horizontalPadding)
                    }
                }
                .padding(.bottom, 80)
            }
        }
        .background(TVThemeFill().ignoresSafeArea())
        .defaultFocus($headerFocus, true)
        // `defaultFocus` only applies to the first layout. When the item or its scenes
        // arrive later, tvOS re-picks focus and lands on the first scene card, scrolling
        // the page down — so re-claim the header until the user has moved away from it.
        .onChange(of: headerFocus) { wasFocused, isFocused in
            if wasFocused && !isFocused { headerFocusReleased = true }
        }
        .onChange(of: headerAnchorFocus) { wasFocused, isFocused in
            if wasFocused && !isFocused { headerFocusReleased = true }
        }
        .onAppear { claimHeaderFocusIfUntouched() }
        .onChange(of: showsChannelButton) { _, _ in claimHeaderFocusIfUntouched() }
        .onChange(of: isLoading) { _, _ in claimHeaderFocusIfUntouched() }
        .onChange(of: scenes.isEmpty) { _, _ in claimHeaderFocusIfUntouched() }
        // A channel opens Feeds (Scenes of this performer / studio / tag / group), as on iOS.
        .tvChannelFeedCover($playingChannel)
    }

    // MARK: - Header buttons

    /// The page's buttons; `TVDetailHeader` lays them out in its row and adds Details.
    @ViewBuilder
    private var actionButtons: some View {
        if showsChannelButton {
            Button {
                playingChannel = channel
            } label: {
                TVChromeButtonLabel(icon: "play.tv.fill", text: tr("action_play_as_channel"))
            }
            .focused($headerFocus)
        } else if headerActions.isEmpty {
            // Without the channel button and without actions the header has nothing
            // focusable from the first frame; this invisible anchor keeps the opening
            // focus (and scroll) at the top. It is its own view on purpose:
            // `.focusable(false)` on the header container disabled focus for the whole
            // subtree, so Up from the scene grid could never land on the channel button.
            Color.clear
                .frame(width: 1, height: 1)
                .focusable()
                .focusEffectDisabled()
                .focused($headerAnchorFocus)
                .accessibilityHidden(true)
        }
        ForEach(Array(headerActions.enumerated()), id: \.element.id) { index, action in
            // Without the channel button the first action is the header's
            // focus anchor, so the page opens on something visible.
            if index == 0 && !showsChannelButton {
                headerActionButton(action)
                    .focused($headerAnchorFocus)
            } else {
                headerActionButton(action)
            }
        }
        ForEach(trailingActions) { action in
            headerActionButton(action)
        }
    }

    private func headerActionButton(_ action: TVDetailHeaderAction) -> some View {
        Button(action: action.perform) {
            TVChromeButtonLabel(icon: action.icon, text: action.title)
        }
    }

    private func claimHeaderFocusIfUntouched() {
        guard !headerFocusReleased else { return }
        DispatchQueue.main.async {
            if showsChannelButton { headerFocus = true } else { headerAnchorFocus = true }
        }
    }
}

// MARK: - Header

/// One spacing scale for every detail page with `TVDetailHeader` (performer, studio, tag,
/// group, gallery), in pt, taken from what the rest of the tvOS app already uses:
///
/// - top inset 30 below the safe area (60): the title sits where the catalog pages put
///   their control row (`STVHeaderView`, vertical padding 30)
/// - 24 between every header row: title, accessory, buttons, facts, description
///   (`DesignTokens.Spacing.xl`, the catalog header's spacing between its controls)
/// - 50 from the header to the first section (`TVDashboardView`, spacing between rows)
/// - 18 from a section title to its cards (Home row title to cards)
/// - 40 between two facts (`TVGridSpec.scenes.spacing`), 4 between a fact's label and
///   value (`DesignTokens.Spacing.xxs`)
/// - buttons and tag chips: one size, `TVChromeButtonLabel` (headline, 24 × 8 padding) in
///   `TVChromeButtonStyle` scaled from the leading edge, so the row starts on the text edge
///   (80) focused or not
/// - leading and trailing edge: the safe area (80), the same as every grid
enum TVDetailMetrics {
    static let topInset: CGFloat = 30
    static let rowGap: CGFloat = DesignTokens.Spacing.xl
    static let sectionGap: CGFloat = 50
    static let sectionTitleGap: CGFloat = 18
    static let factGap: CGFloat = 40
    static let factLabelGap: CGFloat = DesignTokens.Spacing.xxs
    /// Room around a scrolling chip row for the focus lift and shadow; taken back with a
    /// negative padding so the row stays on the scale above.
    static let focusBleed: CGFloat = 24
}

/// A section title on a detail page, the same as a Home row title: no icon (an SF symbol's
/// side bearing put it 5 pt off the card edge), headline, secondary white.
struct TVDetailSectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundColor(.white.opacity(0.6))
    }
}

/// The count beside the title: scenes on performer / studio / tag / group pages,
/// images on a gallery.
struct TVDetailCount {
    let value: Int
    let icon: String
}

/// The compact header of every tvOS detail page of this shape (performer, studio, tag,
/// group, gallery): title line with logo and count, an optional accessory row (a performer's
/// tag chips), one row of buttons with "Details" at its end, the facts as one line of
/// label/value pairs plus a two-line description, and the image as a backdrop on the
/// trailing side. About 40 % of a 1920×1080 screen, so the content grid starts on the first
/// screen. Spacing: `TVDetailMetrics`.
///
/// The buttons are the last focusable row (facts and description are text only): Down from
/// them reaches the grid directly, and Up from any grid column lands on them through the
/// header's focus section. The accessory sits above them for that reason. Focus anchors
/// stay with the page, which passes its buttons in `actions`.
struct TVDetailHeader<Accessory: View, Actions: View>: View {
    let title: String
    let titleLogo: AnyView?
    let count: TVDetailCount?
    let backdrop: TVDetailBackdrop
    let isLoading: Bool
    let details: String?
    let facts: [TVDetailFact]
    /// Facts only the Details sheet shows.
    let sheetFacts: [TVDetailFact]
    let accessory: () -> Accessory
    let actions: () -> Actions

    @Environment(\.tvContentWidth) private var contentWidth
    @State private var showingDetails = false
    /// Measured widths of the facts (each at its natural size) and of the line they go
    /// into; the header packs them into at most `maxFactLines` lines from these.
    @State private var factWidths: [String: CGFloat] = [:]
    @State private var factsLineWidth: CGFloat = 0

    /// Explicit: the private state above would make the memberwise init file-private.
    init(
        title: String,
        titleLogo: AnyView? = nil,
        count: TVDetailCount? = nil,
        backdrop: TVDetailBackdrop = .none,
        isLoading: Bool = false,
        details: String? = nil,
        facts: [TVDetailFact] = [],
        sheetFacts: [TVDetailFact] = [],
        @ViewBuilder accessory: @escaping () -> Accessory,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.title = title
        self.titleLogo = titleLogo
        self.count = count
        self.backdrop = backdrop
        self.isLoading = isLoading
        self.details = details
        self.facts = facts
        self.sheetFacts = sheetFacts
        self.accessory = accessory
        self.actions = actions
    }

    // MARK: Metrics

    private static var maxFactLines: Int { 1 }
    private static var factSpacing: CGFloat { TVDetailMetrics.factGap }
    /// A single fact never grows wider than this (long alias lists are cut, the sheet has them).
    private static var factMaxWidth: CGFloat { 420 }
    /// Overscan safe area of tvOS; the backdrop bleeds into it to the screen's top and
    /// trailing edge so it never shows as a framed box.
    private static var safeTop: CGFloat { 60 }
    private static var safeTrailing: CGFloat { 80 }

    private var hasBackdrop: Bool {
        if case .image(let url) = backdrop, url != nil { return true }
        return false
    }

    /// Visible width of the backdrop inside the content area (it bleeds `safeTrailing` further).
    private var backdropWidth: CGFloat { min(860, contentWidth * 0.45) }
    private var backdropHeight: CGFloat { 560 }

    /// With a backdrop the text column ends where the image is still below ~15 % (the first
    /// tenth of its fade), so no text, long names and long facts included, ever sits on the
    /// bright part. The button row may run further: its controls bring their own fill.
    private var textColumnMaxWidth: CGFloat {
        guard hasBackdrop else { return .infinity }
        let imageStart = contentWidth - 2 * Self.safeTrailing - backdropWidth
        return max(700, imageStart + 0.1 * (backdropWidth + Self.safeTrailing))
    }

    private var trimmedDetails: String? {
        guard let text = details?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: TVDetailMetrics.rowGap) {
            titleLine

            accessory()

            HStack(spacing: DesignTokens.Spacing.xl) {
                actions()
                if showsDetailsButton {
                    Button {
                        showingDetails = true
                    } label: {
                        TVChromeButtonLabel(icon: "info.circle", text: tr("details"))
                    }
                }
            }
            // The catalog's control style for every button, growing from its leading edge:
            // the first one stays on the text edge when focused.
            .buttonStyle(TVChromeButtonStyle(scaleAnchor: .leading))
            // Never squeezed by the text column; the buttons bring their own fill.
            .fixedSize(horizontal: true, vertical: false)
            // Own section across the full width: Up from the grid and Down from the
            // accessory row reach it from any column.
            .tvFocusRow()

            if isLoading {
                ProgressView()
            } else {
                factsBlock
                if let trimmedDetails {
                    Text(trimmedDetails)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: textColumnMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, TVDetailMetrics.topInset)
        // Background, not a sibling: the image never changes the header's height, so the
        // grid starts at the same place with and without it, and it scrolls away with it.
        .background(alignment: .topTrailing) { backdropView }
        // One focus region: Up from any grid column lands on the button row even where the
        // buttons and the column do not overlap horizontally.
        .focusSection()
        .sheet(isPresented: $showingDetails) {
            TVDetailInfoSheet(title: title, details: trimmedDetails, facts: facts + sheetFacts)
        }
    }

    private var titleLine: some View {
        HStack(alignment: .center, spacing: 24) {
            // Spacing 0: a logo brings its own gap, so a studio without one has none.
            HStack(alignment: .center, spacing: 0) {
                if let titleLogo {
                    titleLogo
                }
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .layoutPriority(1)
            if let count {
                Label {
                    Text(verbatim: "\(count.value)")
                } icon: {
                    Image(systemName: count.icon)
                }
                .font(.headline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            }
        }
    }

    // MARK: Facts

    private var factLayout: TVDetailFactPacking.Result {
        TVDetailFactPacking.pack(
            facts,
            widths: factWidths,
            lineWidth: factsLineWidth,
            spacing: Self.factSpacing,
            maxLines: Self.maxFactLines
        )
    }

    private var showsDetailsButton: Bool {
        !isLoading && (trimmedDetails != nil || !sheetFacts.isEmpty || factLayout.hiddenCount > 0)
    }

    @ViewBuilder
    private var factsBlock: some View {
        if !facts.isEmpty {
            VStack(alignment: .leading, spacing: TVDetailMetrics.rowGap) {
                if factsLineWidth > 0 {
                    let layout = factLayout
                    ForEach(Array(layout.lines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: Self.factSpacing) {
                            ForEach(line) { fact in
                                TVDetailFactView(fact: fact)
                                    .frame(width: layout.widthOverrides[fact.id] ?? factWidths[fact.id],
                                           alignment: .leading)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                if abs(width - factsLineWidth) > 1 { factsLineWidth = width }
            }
            // Every fact once at its natural width, invisible; the packing above reads these.
            .background(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(facts) { fact in
                        TVDetailFactView(fact: fact)
                            .fixedSize()
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                                let capped = min(ceil(width), Self.factMaxWidth)
                                if factWidths[fact.id] != capped { factWidths[fact.id] = capped }
                            }
                    }
                }
                .fixedSize()
                .hidden()
                .accessibilityHidden(true)
            }
        }
    }

    // MARK: Backdrop

    @ViewBuilder
    private var backdropView: some View {
        if case .image(let url) = backdrop, let url {
            CustomAsyncImage(url: url) { loader in
                if let image = loader.image {
                    image.resizable().scaledToFill()
                } else {
                    Color.clear
                }
            }
            // The loader is a `@StateObject` bound to its first URL: a new URL (a group's
            // other cover) needs a new view.
            .id(url)
            // Top-aligned so faces stay in view; fills the width, the overflow below is cut.
            .frame(width: backdropWidth + Self.safeTrailing,
                   height: backdropHeight + Self.safeTop + TVDetailMetrics.topInset,
                   alignment: .top)
            .clipped()
            // Fades in from the text side and out towards the grid, into the theme
            // background — no edge, and the text column never sits on the full image.
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.35), location: 0.25),
                        .init(color: .black, location: 0.55)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.4),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                }
            }
            .opacity(0.9)
            .offset(x: Self.safeTrailing, y: -Self.safeTop - TVDetailMetrics.topInset)
            .allowsHitTesting(false)
            .focusable(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Fact packing

enum TVDetailFactPacking {
    struct Result {
        var lines: [[TVDetailFact]] = []
        /// Facts left out at the end; the Details sheet lists them.
        var hiddenCount: Int = 0
        /// Narrower widths for facts cut with an ellipsis to fill the last line.
        var widthOverrides: [String: CGFloat] = [:]
    }

    /// Fills lines from the left in order (order is importance, nothing jumps ahead). The
    /// fact that no longer fits into the last line is cut to the rest of the line when at
    /// least `minTruncatedWidth` is left; it and every later fact go to the Details sheet
    /// otherwise (the sheet always has the full value).
    static func pack(
        _ facts: [TVDetailFact],
        widths: [String: CGFloat],
        lineWidth: CGFloat,
        spacing: CGFloat,
        maxLines: Int,
        minTruncatedWidth: CGFloat = 240
    ) -> Result {
        guard lineWidth > 0, maxLines > 0 else { return Result() }
        var result = Result()
        var current: [TVDetailFact] = []
        var used: CGFloat = 0
        for (index, fact) in facts.enumerated() {
            let width = widths[fact.id] ?? 0
            let needed = current.isEmpty ? width : used + spacing + width
            if needed <= lineWidth {
                current.append(fact)
                used = needed
                continue
            }
            let isLastLine = result.lines.count == maxLines - 1
            let rest = current.isEmpty ? lineWidth : lineWidth - used - spacing
            if isLastLine || current.isEmpty {
                // Cut this fact to what is left of the line (a single over-wide fact always).
                if rest >= minTruncatedWidth || current.isEmpty {
                    current.append(fact)
                    result.widthOverrides[fact.id] = max(0, rest)
                    used = lineWidth
                    if isLastLine {
                        result.lines.append(current)
                        result.hiddenCount = facts.count - index - 1
                        return result
                    }
                    continue
                }
                result.lines.append(current)
                result.hiddenCount = facts.count - index
                return result
            }
            result.lines.append(current)
            current = [fact]
            used = width
        }
        if !current.isEmpty { result.lines.append(current) }
        return result
    }
}

/// Label small and secondary, the value below it in regular weight.
/// Sized by its parent: the header measures it at its natural width and then gives it
/// exactly that (capped), so a long value is cut with an ellipsis.
struct TVDetailFactView: View {
    let fact: TVDetailFact

    var body: some View {
        VStack(alignment: .leading, spacing: TVDetailMetrics.factLabelGap) {
            Text(fact.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 8) {
                if let icon = fact.icon {
                    Image(systemName: icon)
                        .foregroundColor(fact.iconColor)
                }
                Text(fact.value)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .font(.body)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Details sheet

/// Everything the header leaves out: the full description and every fact, one per row.
/// Rows are focusable so a long list scrolls with the remote.
struct TVDetailInfoSheet: View {
    let title: String
    let details: String?
    let facts: [TVDetailFact]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(2)

                if let details {
                    TVDetailInfoRow {
                        Text(details)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(facts) { fact in
                        TVDetailInfoRow {
                            HStack(alignment: .firstTextBaseline, spacing: 24) {
                                Text(fact.label)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 280, alignment: .leading)
                                HStack(spacing: 8) {
                                    if let icon = fact.icon {
                                        Image(systemName: icon).foregroundColor(fact.iconColor)
                                    }
                                    Text(fact.value)
                                        .foregroundColor(.white)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                Button(tr("action_done")) { dismiss() }
                    .padding(.top, 12)
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 60)
            .frame(maxWidth: 1200, alignment: .leading)
        }
        .background(TVThemeFill().ignoresSafeArea())
    }
}

private struct TVDetailInfoRow<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @FocusState private var isFocused: Bool

    var body: some View {
        content()
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(isFocused ? 0.12 : 0))
            )
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
