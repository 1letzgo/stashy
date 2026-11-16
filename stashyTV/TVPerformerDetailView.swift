//
//  TVPerformerDetailView.swift
//  stashyTV
//
//  Performer detail for tvOS — Netflix/Prime style
//

import SwiftUI

struct TVPerformerDetailView: View {
    let performerId: String
    let performerName: String

    @StateObject private var viewModel = StashDBViewModel()
    @State private var performer: Performer?
    @State private var isLoadingPerformer = true
    // Nur beim ersten Erscheinen laden — ein Pop zurück darf die nachgeladenen
    // Seiten (und damit Scroll-Position/Fokus) nicht auf Seite 1 zurücksetzen.
    @State private var didLoad = false
    @State private var isUpdatingFavorite = false
    @State private var showingRatingPicker = false
    /// Match rank "rank/total" in the Match pool (same line as iOS), nil when not ranked.
    @State private var battleLine: String?
    /// The performer's own tags (`findPerformerTags`), a row like on the TV scene page.
    @State private var performerTags: [Tag] = []
    /// Description and links for the Details sheet; not in `PerformerFields`, so they come
    /// with their own small query (`PerformerProfileExtras`).
    @State private var profileExtras = PerformerProfileExtras()

    var body: some View {
        TVGenericDetailView(
            item: performer,
            isLoading: isLoadingPerformer,
            backdrop: .image(performer.flatMap(Self.backdropURL)),
            channel: .performer(id: performerId, name: performer?.name ?? performerName),
            headerActions: headerActions,
            facts: performer.map { Self.headerFacts(for: $0) } ?? [],
            sheetFacts: performer.map { Self.sheetFacts(for: $0, matchRank: battleLine, links: profileExtras.links) } ?? [],
            sheetDetails: profileExtras.details,
            scenes: viewModel.performerScenes,
            isLoadingScenes: viewModel.isLoadingPerformerScenes,
            totalScenes: viewModel.totalPerformerScenes,
            hasMoreScenes: viewModel.hasMorePerformerScenes,
            loadMoreScenes: { viewModel.loadMorePerformerScenes(performerId: performerId) },
            headerAccessory: { TVPerformerTagChips(tags: performerTags) }
        )
        .tvRatingDialog(isPresented: $showingRatingPicker, current: performer?.rating100) { value in
            setRating(value)
        }
        .task(id: performerId) {
            battleLine = await HotOrNotBattleDisplay.fetchRankSlashTotal(performerId: performerId)
        }
        .task(id: performerId) {
            performerTags = (try? await PerformerRepository().fetchPerformerTags(performerId: performerId)) ?? []
        }
        .task(id: performerId) {
            profileExtras = await PerformerProfileExtras.load(performerId: performerId)
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            loadPerformerData()
        }
    }

    // MARK: - Facts

    /// The performer's own image; none for Stash's generic silhouette (`…default=true`).
    static func backdropURL(_ performer: Performer) -> URL? {
        if performer.imagePath?.contains("default=true") == true { return nil }
        return performer.thumbnailURL
    }

    /// The header line, most telling first; what does not fit in the line goes to the
    /// Details sheet. Only facts with a value.
    static func headerFacts(for performer: Performer) -> [TVDetailFact] {
        var facts: [TVDetailFact] = []
        if let gender = performer.gender, !gender.isEmpty {
            facts.append(TVDetailFact(id: "gender", label: tr("gender"), value: gender.capitalized))
        }
        if let birthdate = performer.birthdate, !birthdate.isEmpty {
            facts.append(TVDetailFact(id: "born", label: tr("born"), value: birthdate))
            if let age = age(fromBirthdate: birthdate) {
                facts.append(TVDetailFact(id: "age", label: tr("age"), value: "\(age)"))
            }
        }
        if let country = performer.country, !country.isEmpty {
            facts.append(TVDetailFact(id: "country", label: tr("country"), value: country))
        }
        if let ethnicity = performer.ethnicity, !ethnicity.isEmpty {
            facts.append(TVDetailFact(id: "ethnicity", label: tr("ethnicity"), value: ethnicity.capitalized))
        }
        if let height = performer.height, height > 0 {
            facts.append(TVDetailFact(id: "height", label: tr("height"), value: "\(height) cm"))
        }
        if let measurements = performer.measurements, !measurements.isEmpty {
            facts.append(TVDetailFact(id: "measurements", label: tr("measurements"), value: measurements))
        }
        // Summed over the performer's scenes by Stash — read-only, the
        // counter itself lives on the scenes.
        if let oCounter = performer.oCounter, oCounter > 0 {
            facts.append(TVDetailFact(id: "o_count", label: tr("o_count"), value: "\(oCounter)",
                                      icon: "heart.circle", iconColor: AppearanceManager.shared.tintColor))
        }
        // Last: the longest value. Cut with an ellipsis when the line is nearly full,
        // behind Details when it is full. No rating fact: the Rating button shows it.
        let aliases = (performer.aliasList ?? []).filter { !$0.isEmpty }
        if !aliases.isEmpty {
            facts.append(TVDetailFact(id: "aliases", label: tr("aliases"), value: aliases.joined(separator: ", ")))
        }
        return facts
    }

    /// Facts only the Details sheet lists. `matchRank` is the performer's place in the Match
    /// tool's leaderboard ("rank/total" of its pool, `HotOrNotBattleDisplay`), nil when the
    /// performer is not in that pool; it means nothing without the tool, so it stays here.
    static func sheetFacts(for performer: Performer, matchRank: String?, links: [String] = []) -> [TVDetailFact] {
        var facts: [TVDetailFact] = []
        // The header's Rating button shows it too; the sheet lists everything.
        if let rating = performer.rating100 {
            facts.append(TVDetailFact(id: "rating", label: tr("rating"), value: String(format: "%.1f", Double(rating) / 20.0),
                                      icon: "star.fill", iconColor: .yellow))
        }
        if let matchRank {
            facts.append(TVDetailFact(id: "match_rank", label: tr("match_rank"), value: matchRank))
        }
        if let disambiguation = performer.disambiguation, !disambiguation.isEmpty {
            facts.append(TVDetailFact(id: "disambiguation", label: tr("disambiguation"), value: disambiguation))
        }
        facts.append(TVDetailFact(id: "scenes", label: tr("scenes"), value: "\(performer.sceneCount)"))
        if let weight = performer.weight, weight > 0 {
            facts.append(TVDetailFact(id: "weight", label: tr("weight"), value: "\(weight) kg"))
        }
        if let fakeTits = performer.fakeTits, !fakeTits.isEmpty {
            facts.append(TVDetailFact(id: "fake_tits", label: tr("fake_tits"), value: fakeTits))
        }
        if let penisLength = performer.penis_length, penisLength > 0 {
            facts.append(TVDetailFact(id: "penis_length", label: tr("penis_length_cm"),
                                      value: String(format: "%g", penisLength)))
        }
        if let career = performer.careerLength, !career.isEmpty {
            facts.append(TVDetailFact(id: "career", label: tr("career_length"), value: career))
        }
        if let tattoos = performer.tattoos, !tattoos.isEmpty {
            facts.append(TVDetailFact(id: "tattoos", label: tr("tattoos"), value: tattoos))
        }
        if let piercings = performer.piercings, !piercings.isEmpty {
            facts.append(TVDetailFact(id: "piercings", label: tr("piercings"), value: piercings))
        }
        if performer.favorite == true {
            facts.append(TVDetailFact(id: "favorite", label: tr("favourite"), value: "",
                                      icon: "heart.fill", iconColor: .red))
        }
        if !links.isEmpty {
            facts.append(TVDetailFact(id: "links", label: tr("links"), value: links.joined(separator: "\n")))
        }
        return facts
    }

    /// Whole years from a Stash date (`yyyy-MM-dd`, sometimes only `yyyy`); nil when unparsable.
    static func age(fromBirthdate birthdate: String, now: Date = Date()) -> Int? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: String(birthdate.prefix(10))) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let years = calendar.dateComponents([.year], from: date, to: now).year,
              years >= 0, years < 130 else { return nil }
        return years
    }

    // MARK: - Actions

    /// Favorite and rating, like the iOS detail page. Present from the first frame (they
    /// no-op until the performer is loaded): the first one is the header's focus anchor, and
    /// swapping the anchor out mid-load let tvOS move focus into the scene grid.
    private var headerActions: [TVDetailHeaderAction] {
        let isFavorite = performer?.favorite == true
        return [
            TVDetailHeaderAction(
                id: "favorite",
                icon: isFavorite ? "heart.fill" : "heart",
                title: isFavorite ? tr("favourite") : tr("action_add_favorite"),
                perform: toggleFavorite
            ),
            TVDetailHeaderAction(
                id: "rating",
                icon: "star.fill",
                title: TVEntityRating.buttonTitle(performer?.rating100),
                perform: { if performer != nil { showingRatingPicker = true } }
            )
        ]
    }

    /// Optimistic like iOS: flip first, roll back if the server refuses.
    private func toggleFavorite() {
        guard let current = performer, !isUpdatingFavorite else { return }
        isUpdatingFavorite = true
        let newState = !(current.favorite == true)
        performer = current.withFavorite(newState)
        viewModel.togglePerformerFavorite(performerId: current.id, favorite: newState) { success in
            DispatchQueue.main.async {
                if !success, let latest = performer {
                    performer = latest.withFavorite(!newState)
                }
                isUpdatingFavorite = false
            }
        }
    }

    private func setRating(_ value: Int?) {
        guard let current = performer else { return }
        let previous = current.rating100
        var updated = current
        updated.rating100 = value
        performer = updated
        Task {
            let ok = await TVEntityRating.setPerformerRating(id: current.id, rating100: value)
            if !ok, var latest = performer {
                latest.rating100 = previous
                performer = latest
            }
        }
    }

    // MARK: - Data Loading

    private func loadPerformerData() {
        viewModel.fetchPerformer(performerId: performerId) { fetchedPerformer in
            self.performer = fetchedPerformer
            self.isLoadingPerformer = false
        }
        viewModel.fetchPerformerScenes(performerId: performerId, isInitialLoad: true)
    }
}

private extension Performer {
    /// `favorite` is a `let`, so a toggle needs a full copy.
    func withFavorite(_ newValue: Bool) -> Performer {
        Performer(
            id: id, name: name, disambiguation: disambiguation, birthdate: birthdate,
            country: country, imagePath: imagePath, sceneCount: sceneCount,
            imageCount: imageCount, galleryCount: galleryCount, gender: gender,
            ethnicity: ethnicity, height: height, weight: weight, measurements: measurements,
            fakeTits: fakeTits, penis_length: penis_length, careerLength: careerLength,
            tattoos: tattoos, piercings: piercings, aliasList: aliasList,
            favorite: newValue, rating100: rating100, createdAt: createdAt,
            updatedAt: updatedAt, oCounter: oCounter
        )
    }
}

// MARK: - Profile extras

/// A performer's description and links, which the shared `PerformerFields` fragment does not
/// carry. Same small query as the iOS performer page (`loadProfileLinks`): `urls`, falling
/// back to the singular `url` on servers without it.
struct PerformerProfileExtras: Equatable {
    var details: String?
    var links: [String] = []

    static func load(performerId: String) async -> PerformerProfileExtras {
        func fetch(_ linkField: String) async -> PerformerProfileExtras? {
            let query = "query PerformerProfileExtras($id: ID!) { findPerformer(id: $id) { details \(linkField) } }"
            guard let data = try? await GraphQLClient.shared.executeRaw(query: query, variables: ["id": performerId]),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataDict = root["data"] as? [String: Any],
                  let node = dataDict["findPerformer"] as? [String: Any] else { return nil }
            var raw: [String] = []
            if let list = node["urls"] as? [String] { raw = list }
            else if let single = node["url"] as? String { raw = [single] }
            var seen = Set<String>()
            let links = raw
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && seen.insert($0).inserted }
            return PerformerProfileExtras(details: node["details"] as? String, links: links)
        }
        if let extras = await fetch("urls") { return extras }
        return await fetch("url") ?? PerformerProfileExtras()
    }
}

// MARK: - Tag chips

/// The performer's own tags (`findPerformerTags`) as one scrolling chip row in the header;
/// left out while there are none. One line, no section title: the scenes stay on the first
/// screen. Same control as the header's buttons (`TVChromeButtonLabel` in
/// `TVChromeButtonStyle`), so both rows have one size.
struct TVPerformerTagChips: View {
    let tags: [Tag]
    @Environment(\.tvNavigationPath) private var path

    var body: some View {
        if !tags.isEmpty {
            // Scrolls back to the first chip when focus leaves the row.
            TVDetailScrollingRow {
                ForEach(tags) { tag in
                    Button {
                        path?.wrappedValue.append(TVTagLink(id: tag.id, name: tag.name))
                    } label: {
                        TVChromeButtonLabel(text: tag.name)
                    }
                }
            }
        }
    }
}

#Preview("Performer header") {
    let performer = Performer(
        id: "1", name: "Example Performer", disambiguation: "EU", birthdate: "1994-03-12",
        country: "Germany", imagePath: nil, sceneCount: 128, imageCount: 40, galleryCount: 6,
        gender: "FEMALE", ethnicity: "caucasian", height: 168, weight: 54, measurements: "34B-24-35",
        fakeTits: "No", penis_length: nil, careerLength: "2015 -", tattoos: "Left shoulder",
        piercings: "Navel", aliasList: ["Example Alias", "Another Name"], favorite: true,
        rating100: 80, createdAt: nil, updatedAt: nil, oCounter: 12
    )
    let sceneJSON = (1...8).map {
        #"{"id":"\#($0)","title":"Sample scene \#($0)","date":"2024-0\#(($0 % 9) + 1)-14","performers":[]}"#
    }.joined(separator: ",")
    let scenes = (try? JSONDecoder().decode([Scene].self, from: Data("[\(sceneJSON)]".utf8))) ?? []
    let tags = (try? JSONDecoder().decode([Tag].self, from: Data(#"[{"id":"1","name":"Blonde"},{"id":"2","name":"Outdoor"},{"id":"3","name":"Interview"}]"#.utf8))) ?? []
    return NavigationStack {
        TVGenericDetailView(
            item: performer,
            isLoading: false,
            channel: .performer(id: performer.id, name: performer.name),
            headerActions: [
                TVDetailHeaderAction(id: "favorite", icon: "heart.fill", title: tr("favourite"), perform: {}),
                TVDetailHeaderAction(id: "rating", icon: "star.fill", title: TVEntityRating.buttonTitle(80), perform: {})
            ],
            facts: TVPerformerDetailView.headerFacts(for: performer),
            sheetFacts: TVPerformerDetailView.sheetFacts(for: performer, matchRank: "3/120",
                                                         links: ["https://example.com/performer"]),
            sheetDetails: "A short sample description for the Details sheet.",
            scenes: scenes,
            isLoadingScenes: false,
            totalScenes: performer.sceneCount,
            hasMoreScenes: false,
            loadMoreScenes: {},
            headerAccessory: { TVPerformerTagChips(tags: tags) }
        )
    }
}

#Preview("Performer (server)") {
    NavigationStack {
        TVPerformerDetailView(performerId: "1", performerName: tr("example_performer"))
    }
}
