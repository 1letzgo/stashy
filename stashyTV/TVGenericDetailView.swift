import SwiftUI

struct TVGenericDetailView<Item: TVDetailItem, Info: View, Content: View>: View {
    let item: Item?
    let isLoading: Bool
    let heroAspectRatio: CGFloat
    let placeholderSystemImage: String
    let heroImageOverride: AnyView?
    
    // Scenes related
    let scenes: [Scene]
    let isLoadingScenes: Bool
    let totalScenes: Int
    let hasMoreScenes: Bool
    let loadMoreScenes: () -> Void
    
    @ViewBuilder let infoGrid: (Item) -> Info
    @ViewBuilder let additionalContent: () -> Content

    private let sceneColumns = [
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40),
        GridItem(.fixed(410), spacing: 40)
    ]

    init(
        item: Item?,
        isLoading: Bool,
        heroAspectRatio: CGFloat,
        placeholderSystemImage: String,
        heroImageOverride: AnyView? = nil,
        scenes: [Scene],
        isLoadingScenes: Bool,
        totalScenes: Int,
        hasMoreScenes: Bool,
        loadMoreScenes: @escaping () -> Void,
        @ViewBuilder infoGrid: @escaping (Item) -> Info,
        @ViewBuilder additionalContent: @escaping () -> Content
    ) {
        self.item = item
        self.isLoading = isLoading
        self.heroAspectRatio = heroAspectRatio
        self.placeholderSystemImage = placeholderSystemImage
        self.heroImageOverride = heroImageOverride
        self.scenes = scenes
        self.isLoadingScenes = isLoadingScenes
        self.totalScenes = totalScenes
        self.hasMoreScenes = hasMoreScenes
        self.loadMoreScenes = loadMoreScenes
        self.infoGrid = infoGrid
        self.additionalContent = additionalContent
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                // Header (Hero Section)
                HStack(alignment: .top, spacing: 50) {
                    // Thumbnail / Profile Image
                    heroImage
                    
                    // Info Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text(item?.name ?? "")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        if isLoading {
                            ProgressView().scaleEffect(1.2)
                        } else if let item = item {
                            VStack(alignment: .leading, spacing: 14) {
                                if let details = item.details, !details.isEmpty {
                                    Text(details)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(6)
                                }

                                Divider()
                                    .background(Color.secondary)

                                infoGrid(item)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 60)
                .padding(.top, 40)

                // Additional Content (e.g. more metadata or specific views)
                additionalContent()

                // Scenes Section
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        Image(systemName: "film.fill")
                            .font(.title3)
                            .foregroundColor(AppearanceManager.shared.tintColor)
                        Text("Scenes")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        if totalScenes > 0 {
                            Text("\(totalScenes)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 60)

                    if isLoadingScenes && scenes.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView().scaleEffect(1.5)
                            Spacer()
                        }
                        .padding(.vertical, 60)
                    } else if scenes.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 16) {
                                Image(systemName: "film")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                                Text("No scenes found")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 60)
                    } else {
                        LazyVGrid(columns: sceneColumns, spacing: 40) {
                            ForEach(scenes) { scene in
                                VStack(alignment: .leading, spacing: 10) {
                                    TVNavButton(value: TVSceneLink(sceneId: scene.id)) {
                                        TVSceneCardView(scene: scene)
                                    }
                                    
                                    TVSceneCardTitleView(scene: scene)
                                }
                                .frame(width: 410)
                                .onAppear {
                                    if scene.id == scenes.last?.id && hasMoreScenes {
                                        loadMoreScenes()
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 60)
                    }
                }
                .padding(.bottom, 80)
            }
        }
        .background(Color.appBackground)
    }

    @ViewBuilder
    private var heroImage: some View {
        // Reine Anzeige — früher ein leerer `Button { } .buttonStyle(.card)`,
        // der auf tvOS Parallax/Card-Scale erzeugte und Selektierbarkeit
        // suggerierte, ohne dass beim Select etwas passierte. Jetzt nicht mehr
        // fokusierbar.
        Group {
            if let heroImageOverride {
                heroImageOverride
            } else
            if let thumbnailURL = item?.thumbnailURL {
                CustomAsyncImage(url: thumbnailURL) { loader in
                    if let image = loader.image {
                        image.resizable().scaledToFill()
                    } else if loader.isLoading {
                        Rectangle()
                            .fill(Color.gray.opacity(0.08))
                            .overlay(ProgressView())
                    } else {
                        placeholderView
                    }
                }
            } else {
                placeholderView
            }
        }
        .focusable(false)
        .frame(width: 400 * heroAspectRatio, height: 400)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.08))
            .overlay(
                Image(systemName: placeholderSystemImage)
                    .font(.system(size: 56))
                    .foregroundColor(.secondary)
            )
    }
}
