#if !os(tvOS)
import SwiftUI

struct DefaultSortView: View {
    @ObservedObject var tabManager = TabManager.shared

    var visibleTabs: [TabConfig] {
        tabManager.tabs
            .filter {
                $0.id != .settings
                    && $0.id != .catalogue
                    && $0.id != .media
                    && $0.id != .downloads
                    && $0.id != .dashboard
                    && $0.id != .reels
                    && $0.id != .stashline
            }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        List {
            Section(header: Text("Default Sort Order")) {
                ForEach(visibleTabs) { tab in
                    sortRow(for: tab.id)
                }
            }
            .listRowBackground(Color.secondaryAppBackground)

            Section(header: Text("Detail Views Sort Order")) {
                ForEach(tabManager.detailViews) { config in
                    detailSortRow(for: config)
                }
            }
            .listRowBackground(Color.secondaryAppBackground)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Default Sorting")
        .applyAppBackground()
        .scrollContentBackground(.hidden)
    }

    // MARK: - Tab Sort Rows

    @ViewBuilder
    private func sortRow(for tab: AppTab) -> some View {
        switch tab {
        case .scenes:   scenesSortRow(tab: tab)
        case .performers: performersSortRow(tab: tab)
        case .studios:  studiosSortRow(tab: tab)
        case .galleries: galleriesSortRow(tab: tab)
        case .tags:     tagsSortRow(tab: tab)
        case .images:   imagesSortRow(tab: tab)
        case .groups:   groupsSortRow(tab: tab)
        case .markers:  markersSortRow(tab: tab)
        default:        EmptyView()
        }
    }

    // MARK: Scenes

    private func scenesSortRow(tab: AppTab) -> some View {
        let binding = Binding<StashDBViewModel.SceneSortOption>(
            get: { StashDBViewModel.SceneSortOption(rawValue: tabManager.getPersistentSortOption(for: tab) ?? "") ?? .dateDesc },
            set: { tabManager.setPersistentSortOption(for: tab, option: $0.rawValue) }
        )
        return HStack {
            Label(tab.title, systemImage: tab.icon)
            Spacer()
            Menu {
                Button(action: { binding.wrappedValue = .random }) {
                    HStack { Text("Random"); if binding.wrappedValue == .random { Image(systemName: "checkmark") } }
                }
                Divider()
                Menu {
                    Button(action: { binding.wrappedValue = .dateDesc }) {
                        HStack { Text("Newest First"); if binding.wrappedValue == .dateDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .dateAsc }) {
                        HStack { Text("Oldest First"); if binding.wrappedValue == .dateAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Date"); if binding.wrappedValue == .dateAsc || binding.wrappedValue == .dateDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .titleAsc }) {
                        HStack { Text("A → Z"); if binding.wrappedValue == .titleAsc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .titleDesc }) {
                        HStack { Text("Z → A"); if binding.wrappedValue == .titleDesc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Title"); if binding.wrappedValue == .titleAsc || binding.wrappedValue == .titleDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .durationDesc }) {
                        HStack { Text("Longest First"); if binding.wrappedValue == .durationDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .durationAsc }) {
                        HStack { Text("Shortest First"); if binding.wrappedValue == .durationAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Duration"); if binding.wrappedValue == .durationAsc || binding.wrappedValue == .durationDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .ratingDesc }) {
                        HStack { Text("High → Low"); if binding.wrappedValue == .ratingDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .ratingAsc }) {
                        HStack { Text("Low → High"); if binding.wrappedValue == .ratingAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Rating"); if binding.wrappedValue == .ratingAsc || binding.wrappedValue == .ratingDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .oCounterDesc }) {
                        HStack { Text("High → Low"); if binding.wrappedValue == .oCounterDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .oCounterAsc }) {
                        HStack { Text("Low → High"); if binding.wrappedValue == .oCounterAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Counter"); if binding.wrappedValue == .oCounterAsc || binding.wrappedValue == .oCounterDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .playCountDesc }) {
                        HStack { Text("Most Viewed"); if binding.wrappedValue == .playCountDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .playCountAsc }) {
                        HStack { Text("Least Viewed"); if binding.wrappedValue == .playCountAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Views"); if binding.wrappedValue == .playCountAsc || binding.wrappedValue == .playCountDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .lastPlayedAtDesc }) {
                        HStack { Text("Recently Played"); if binding.wrappedValue == .lastPlayedAtDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .lastPlayedAtAsc }) {
                        HStack { Text("Least Recently"); if binding.wrappedValue == .lastPlayedAtAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Last Played"); if binding.wrappedValue == .lastPlayedAtAsc || binding.wrappedValue == .lastPlayedAtDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .createdAtDesc }) {
                        HStack { Text("Newest First"); if binding.wrappedValue == .createdAtDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .createdAtAsc }) {
                        HStack { Text("Oldest First"); if binding.wrappedValue == .createdAtAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Created"); if binding.wrappedValue == .createdAtAsc || binding.wrappedValue == .createdAtDesc { Image(systemName: "checkmark") } }
                }
            } label: {
                Text(binding.wrappedValue.displayName).foregroundColor(.secondary)
            }
        }
    }

    // MARK: Performers

    private func performersSortRow(tab: AppTab) -> some View {
        let binding = Binding<StashDBViewModel.PerformerSortOption>(
            get: { StashDBViewModel.PerformerSortOption(rawValue: tabManager.getPersistentSortOption(for: tab) ?? "") ?? .sceneCountDesc },
            set: { tabManager.setPersistentSortOption(for: tab, option: $0.rawValue) }
        )
        return HStack {
            Label(tab.title, systemImage: tab.icon)
            Spacer()
            Menu {
                Button(action: { binding.wrappedValue = .random }) {
                    HStack { Text("Random"); if binding.wrappedValue == .random { Image(systemName: "checkmark") } }
                }
                Divider()
                Menu {
                    Button(action: { binding.wrappedValue = .nameAsc }) {
                        HStack { Text("A → Z"); if binding.wrappedValue == .nameAsc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .nameDesc }) {
                        HStack { Text("Z → A"); if binding.wrappedValue == .nameDesc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Name"); if binding.wrappedValue == .nameAsc || binding.wrappedValue == .nameDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .sceneCountDesc }) {
                        HStack { Text("Most Scenes"); if binding.wrappedValue == .sceneCountDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .sceneCountAsc }) {
                        HStack { Text("Least Scenes"); if binding.wrappedValue == .sceneCountAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Scene Count"); if binding.wrappedValue == .sceneCountAsc || binding.wrappedValue == .sceneCountDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .oCountDesc }) {
                        HStack { Text("High → Low"); if binding.wrappedValue == .oCountDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .oCountAsc }) {
                        HStack { Text("Low → High"); if binding.wrappedValue == .oCountAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Counter"); if binding.wrappedValue == .oCountAsc || binding.wrappedValue == .oCountDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .birthdateDesc }) {
                        HStack { Text("Youngest First"); if binding.wrappedValue == .birthdateDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .birthdateAsc }) {
                        HStack { Text("Oldest First"); if binding.wrappedValue == .birthdateAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Birthdate"); if binding.wrappedValue == .birthdateAsc || binding.wrappedValue == .birthdateDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .updatedAtDesc }) {
                        HStack { Text("Recently Updated"); if binding.wrappedValue == .updatedAtDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .updatedAtAsc }) {
                        HStack { Text("Least Recently"); if binding.wrappedValue == .updatedAtAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Updated"); if binding.wrappedValue == .updatedAtAsc || binding.wrappedValue == .updatedAtDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .createdAtDesc }) {
                        HStack { Text("Newest First"); if binding.wrappedValue == .createdAtDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .createdAtAsc }) {
                        HStack { Text("Oldest First"); if binding.wrappedValue == .createdAtAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Created"); if binding.wrappedValue == .createdAtAsc || binding.wrappedValue == .createdAtDesc { Image(systemName: "checkmark") } }
                }
            } label: {
                Text(binding.wrappedValue.displayName).foregroundColor(.secondary)
            }
        }
    }

    // MARK: Studios

    private func studiosSortRow(tab: AppTab) -> some View {
        let binding = Binding<StashDBViewModel.StudioSortOption>(
            get: { StashDBViewModel.StudioSortOption(rawValue: tabManager.getPersistentSortOption(for: tab) ?? "") ?? .sceneCountDesc },
            set: { tabManager.setPersistentSortOption(for: tab, option: $0.rawValue) }
        )
        return HStack {
            Label(tab.title, systemImage: tab.icon)
            Spacer()
            Menu {
                Button(action: { binding.wrappedValue = .random }) {
                    HStack { Text("Random"); if binding.wrappedValue == .random { Image(systemName: "checkmark") } }
                }
                Divider()
                Menu {
                    Button(action: { binding.wrappedValue = .nameAsc }) {
                        HStack { Text("A → Z"); if binding.wrappedValue == .nameAsc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .nameDesc }) {
                        HStack { Text("Z → A"); if binding.wrappedValue == .nameDesc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Name"); if binding.wrappedValue == .nameAsc || binding.wrappedValue == .nameDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .sceneCountDesc }) {
                        HStack { Text("Most Scenes"); if binding.wrappedValue == .sceneCountDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .sceneCountAsc }) {
                        HStack { Text("Least Scenes"); if binding.wrappedValue == .sceneCountAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Scene Count"); if binding.wrappedValue == .sceneCountAsc || binding.wrappedValue == .sceneCountDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .updatedAtDesc }) {
                        HStack { Text("Recently Updated"); if binding.wrappedValue == .updatedAtDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .updatedAtAsc }) {
                        HStack { Text("Least Recently"); if binding.wrappedValue == .updatedAtAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Updated"); if binding.wrappedValue == .updatedAtAsc || binding.wrappedValue == .updatedAtDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .createdAtDesc }) {
                        HStack { Text("Newest First"); if binding.wrappedValue == .createdAtDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .createdAtAsc }) {
                        HStack { Text("Oldest First"); if binding.wrappedValue == .createdAtAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Created"); if binding.wrappedValue == .createdAtAsc || binding.wrappedValue == .createdAtDesc { Image(systemName: "checkmark") } }
                }
            } label: {
                Text(binding.wrappedValue.displayName).foregroundColor(.secondary)
            }
        }
    }

    // MARK: Galleries

    private func galleriesSortRow(tab: AppTab) -> some View {
        let binding = Binding<StashDBViewModel.GallerySortOption>(
            get: { StashDBViewModel.GallerySortOption(rawValue: tabManager.getPersistentSortOption(for: tab) ?? "") ?? .dateDesc },
            set: { tabManager.setPersistentSortOption(for: tab, option: $0.rawValue) }
        )
        return HStack {
            Label(tab.title, systemImage: tab.icon)
            Spacer()
            Menu {
                Button(action: { binding.wrappedValue = .random }) {
                    HStack { Text("Random"); if binding.wrappedValue == .random { Image(systemName: "checkmark") } }
                }
                Divider()
                Menu {
                    Button(action: { binding.wrappedValue = .titleAsc }) {
                        HStack { Text("A → Z"); if binding.wrappedValue == .titleAsc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .titleDesc }) {
                        HStack { Text("Z → A"); if binding.wrappedValue == .titleDesc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Title"); if binding.wrappedValue == .titleAsc || binding.wrappedValue == .titleDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .dateDesc }) {
                        HStack { Text("Newest First"); if binding.wrappedValue == .dateDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .dateAsc }) {
                        HStack { Text("Oldest First"); if binding.wrappedValue == .dateAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Date"); if binding.wrappedValue == .dateAsc || binding.wrappedValue == .dateDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .ratingDesc }) {
                        HStack { Text("High → Low"); if binding.wrappedValue == .ratingDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .ratingAsc }) {
                        HStack { Text("Low → High"); if binding.wrappedValue == .ratingAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Rating"); if binding.wrappedValue == .ratingAsc || binding.wrappedValue == .ratingDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .createdAtDesc }) {
                        HStack { Text("Newest First"); if binding.wrappedValue == .createdAtDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .createdAtAsc }) {
                        HStack { Text("Oldest First"); if binding.wrappedValue == .createdAtAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Created"); if binding.wrappedValue == .createdAtAsc || binding.wrappedValue == .createdAtDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .updatedAtDesc }) {
                        HStack { Text("Recently Updated"); if binding.wrappedValue == .updatedAtDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .updatedAtAsc }) {
                        HStack { Text("Least Recently"); if binding.wrappedValue == .updatedAtAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Updated"); if binding.wrappedValue == .updatedAtAsc || binding.wrappedValue == .updatedAtDesc { Image(systemName: "checkmark") } }
                }

                Menu {
                    Button(action: { binding.wrappedValue = .imageCountDesc }) {
                        HStack { Text("High → Low"); if binding.wrappedValue == .imageCountDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .imageCountAsc }) {
                        HStack { Text("Low → High"); if binding.wrappedValue == .imageCountAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Image Count"); if binding.wrappedValue == .imageCountAsc || binding.wrappedValue == .imageCountDesc { Image(systemName: "checkmark") } }
                }
            } label: {
                Text(binding.wrappedValue.displayName).foregroundColor(.secondary)
            }
        }
    }

    // MARK: Tags

    private func tagsSortRow(tab: AppTab) -> some View {
        let binding = Binding<StashDBViewModel.TagSortOption>(
            get: { StashDBViewModel.TagSortOption(rawValue: tabManager.getPersistentSortOption(for: tab) ?? "") ?? .sceneCountDesc },
            set: { tabManager.setPersistentSortOption(for: tab, option: $0.rawValue) }
        )
        return HStack {
            Label(tab.title, systemImage: tab.icon)
            Spacer()
            Menu {
                Menu {
                    Button(action: { binding.wrappedValue = .nameAsc }) {
                        HStack { Text("A → Z"); if binding.wrappedValue == .nameAsc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .nameDesc }) {
                        HStack { Text("Z → A"); if binding.wrappedValue == .nameDesc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Name"); if binding.wrappedValue == .nameAsc || binding.wrappedValue == .nameDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .sceneCountDesc }) {
                        HStack { Text("Most Scenes"); if binding.wrappedValue == .sceneCountDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .sceneCountAsc }) {
                        HStack { Text("Least Scenes"); if binding.wrappedValue == .sceneCountAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Scene Count"); if binding.wrappedValue == .sceneCountAsc || binding.wrappedValue == .sceneCountDesc { Image(systemName: "checkmark") } }
                }
            } label: {
                Text(binding.wrappedValue.displayName).foregroundColor(.secondary)
            }
        }
    }

    // MARK: Images

    private func imagesSortRow(tab: AppTab) -> some View {
        let binding = Binding<StashDBViewModel.ImageSortOption>(
            get: { StashDBViewModel.ImageSortOption(rawValue: tabManager.getPersistentSortOption(for: tab) ?? "") ?? .dateDesc },
            set: { tabManager.setPersistentSortOption(for: tab, option: $0.rawValue) }
        )
        return HStack {
            Label(tab.title, systemImage: tab.icon)
            Spacer()
            Menu {
                Button(action: { binding.wrappedValue = .random }) {
                    HStack { Text("Random"); if binding.wrappedValue == .random { Image(systemName: "checkmark") } }
                }
                Divider()
                Menu {
                    Button(action: { binding.wrappedValue = .titleAsc }) {
                        HStack { Text("A → Z"); if binding.wrappedValue == .titleAsc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .titleDesc }) {
                        HStack { Text("Z → A"); if binding.wrappedValue == .titleDesc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Title"); if binding.wrappedValue == .titleAsc || binding.wrappedValue == .titleDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .dateDesc }) {
                        HStack { Text("Newest First"); if binding.wrappedValue == .dateDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .dateAsc }) {
                        HStack { Text("Oldest First"); if binding.wrappedValue == .dateAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Date"); if binding.wrappedValue == .dateAsc || binding.wrappedValue == .dateDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .ratingDesc }) {
                        HStack { Text("High → Low"); if binding.wrappedValue == .ratingDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .ratingAsc }) {
                        HStack { Text("Low → High"); if binding.wrappedValue == .ratingAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Rating"); if binding.wrappedValue == .ratingAsc || binding.wrappedValue == .ratingDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .createdAtDesc }) {
                        HStack { Text("Newest First"); if binding.wrappedValue == .createdAtDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .createdAtAsc }) {
                        HStack { Text("Oldest First"); if binding.wrappedValue == .createdAtAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Created"); if binding.wrappedValue == .createdAtAsc || binding.wrappedValue == .createdAtDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .updatedAtDesc }) {
                        HStack { Text("Recently Updated"); if binding.wrappedValue == .updatedAtDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .updatedAtAsc }) {
                        HStack { Text("Least Recently"); if binding.wrappedValue == .updatedAtAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Updated"); if binding.wrappedValue == .updatedAtAsc || binding.wrappedValue == .updatedAtDesc { Image(systemName: "checkmark") } }
                }
            } label: {
                Text(binding.wrappedValue.displayName).foregroundColor(.secondary)
            }
        }
    }

    // MARK: Groups

    private func groupsSortRow(tab: AppTab) -> some View {
        let binding = Binding<StashDBViewModel.GroupSortOption>(
            get: { StashDBViewModel.GroupSortOption(rawValue: tabManager.getPersistentSortOption(for: tab) ?? "") ?? .nameAsc },
            set: { tabManager.setPersistentSortOption(for: tab, option: $0.rawValue) }
        )
        return HStack {
            Label(tab.title, systemImage: tab.icon)
            Spacer()
            Menu {
                Button(action: { binding.wrappedValue = .random }) {
                    HStack { Text("Random"); if binding.wrappedValue == .random { Image(systemName: "checkmark") } }
                }
                Divider()
                Menu {
                    Button(action: { binding.wrappedValue = .nameAsc }) {
                        HStack { Text("A → Z"); if binding.wrappedValue == .nameAsc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .nameDesc }) {
                        HStack { Text("Z → A"); if binding.wrappedValue == .nameDesc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Name"); if binding.wrappedValue == .nameAsc || binding.wrappedValue == .nameDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .sceneCountDesc }) {
                        HStack { Text("Scenes (High → Low)"); if binding.wrappedValue == .sceneCountDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .sceneCountAsc }) {
                        HStack { Text("Scenes (Low → High)"); if binding.wrappedValue == .sceneCountAsc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .galleryCountDesc }) {
                        HStack { Text("Galleries (High → Low)"); if binding.wrappedValue == .galleryCountDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .galleryCountAsc }) {
                        HStack { Text("Galleries (Low → High)"); if binding.wrappedValue == .galleryCountAsc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .performerCountDesc }) {
                        HStack { Text("Performers (High → Low)"); if binding.wrappedValue == .performerCountDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .performerCountAsc }) {
                        HStack { Text("Performers (Low → High)"); if binding.wrappedValue == .performerCountAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    let countsActive = [StashDBViewModel.GroupSortOption.sceneCountDesc, .sceneCountAsc, .galleryCountDesc, .galleryCountAsc, .performerCountDesc, .performerCountAsc].contains(binding.wrappedValue)
                    HStack { Text("Counts"); if countsActive { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .dateDesc }) {
                        HStack { Text("Newest First"); if binding.wrappedValue == .dateDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .dateAsc }) {
                        HStack { Text("Oldest First"); if binding.wrappedValue == .dateAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Date"); if binding.wrappedValue == .dateAsc || binding.wrappedValue == .dateDesc { Image(systemName: "checkmark") } }
                }
            } label: {
                Text(binding.wrappedValue.displayName).foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: Markers
    
    private func markersSortRow(tab: AppTab) -> some View {
        let binding = Binding<StashDBViewModel.SceneMarkerSortOption>(
            get: { StashDBViewModel.SceneMarkerSortOption(rawValue: tabManager.getPersistentSortOption(for: tab) ?? "") ?? .createdAtDesc },
            set: { tabManager.setPersistentSortOption(for: tab, option: $0.rawValue) }
        )
        return HStack {
            Label(tab.title, systemImage: tab.icon)
            Spacer()
            Menu {
                Button(action: { binding.wrappedValue = .random }) {
                    HStack { Text("Random"); if binding.wrappedValue == .random { Image(systemName: "checkmark") } }
                }
                Divider()
                Menu {
                    Button(action: { binding.wrappedValue = .titleAsc }) {
                        HStack { Text("A → Z"); if binding.wrappedValue == .titleAsc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .titleDesc }) {
                        HStack { Text("Z → A"); if binding.wrappedValue == .titleDesc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Name"); if binding.wrappedValue == .titleAsc || binding.wrappedValue == .titleDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .createdAtDesc }) {
                        HStack { Text("Newest First"); if binding.wrappedValue == .createdAtDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .createdAtAsc }) {
                        HStack { Text("Oldest First"); if binding.wrappedValue == .createdAtAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Created"); if binding.wrappedValue == .createdAtAsc || binding.wrappedValue == .createdAtDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .updatedAtDesc }) {
                        HStack { Text("Recently Updated"); if binding.wrappedValue == .updatedAtDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .updatedAtAsc }) {
                        HStack { Text("Least Recently"); if binding.wrappedValue == .updatedAtAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Updated"); if binding.wrappedValue == .updatedAtAsc || binding.wrappedValue == .updatedAtDesc { Image(systemName: "checkmark") } }
                }
            } label: {
                Text(binding.wrappedValue.displayName).foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Detail View Sort Rows

    @ViewBuilder
    private func detailSortRow(for config: DetailViewConfig) -> some View {
        if config.id == .gallery {
            detailImageSortRow(for: config)
        } else {
            detailSceneSortRow(for: config)
        }
    }

    private func detailSceneSortRow(for config: DetailViewConfig) -> some View {
        let binding = Binding<StashDBViewModel.SceneSortOption>(
            get: { StashDBViewModel.SceneSortOption(rawValue: tabManager.getPersistentDetailSortOption(for: config.id.rawValue) ?? "") ?? .dateDesc },
            set: { tabManager.setPersistentDetailSortOption(for: config.id.rawValue, option: $0.rawValue) }
        )
        return HStack {
            Label(config.id.title, systemImage: config.id.icon)
            Spacer()
            Menu {
                Button(action: { binding.wrappedValue = .random }) {
                    HStack { Text("Random"); if binding.wrappedValue == .random { Image(systemName: "checkmark") } }
                }
                Divider()
                Menu {
                    Button(action: { binding.wrappedValue = .dateDesc }) {
                        HStack { Text("Newest First"); if binding.wrappedValue == .dateDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .dateAsc }) {
                        HStack { Text("Oldest First"); if binding.wrappedValue == .dateAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Date"); if binding.wrappedValue == .dateAsc || binding.wrappedValue == .dateDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .titleAsc }) {
                        HStack { Text("A → Z"); if binding.wrappedValue == .titleAsc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .titleDesc }) {
                        HStack { Text("Z → A"); if binding.wrappedValue == .titleDesc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Title"); if binding.wrappedValue == .titleAsc || binding.wrappedValue == .titleDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .ratingDesc }) {
                        HStack { Text("High → Low"); if binding.wrappedValue == .ratingDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .ratingAsc }) {
                        HStack { Text("Low → High"); if binding.wrappedValue == .ratingAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Rating"); if binding.wrappedValue == .ratingAsc || binding.wrappedValue == .ratingDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .durationDesc }) {
                        HStack { Text("Longest First"); if binding.wrappedValue == .durationDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .durationAsc }) {
                        HStack { Text("Shortest First"); if binding.wrappedValue == .durationAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Duration"); if binding.wrappedValue == .durationAsc || binding.wrappedValue == .durationDesc { Image(systemName: "checkmark") } }
                }
            } label: {
                Text(binding.wrappedValue.displayName).foregroundColor(.secondary)
            }
        }
    }

    private func detailImageSortRow(for config: DetailViewConfig) -> some View {
        let binding = Binding<StashDBViewModel.ImageSortOption>(
            get: { StashDBViewModel.ImageSortOption(rawValue: tabManager.getPersistentDetailSortOption(for: config.id.rawValue) ?? "") ?? .dateDesc },
            set: { tabManager.setPersistentDetailSortOption(for: config.id.rawValue, option: $0.rawValue) }
        )
        return HStack {
            Label(config.id.title, systemImage: config.id.icon)
            Spacer()
            Menu {
                Button(action: { binding.wrappedValue = .random }) {
                    HStack { Text("Random"); if binding.wrappedValue == .random { Image(systemName: "checkmark") } }
                }
                Divider()
                Menu {
                    Button(action: { binding.wrappedValue = .titleAsc }) {
                        HStack { Text("A → Z"); if binding.wrappedValue == .titleAsc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .titleDesc }) {
                        HStack { Text("Z → A"); if binding.wrappedValue == .titleDesc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Title"); if binding.wrappedValue == .titleAsc || binding.wrappedValue == .titleDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .dateDesc }) {
                        HStack { Text("Newest First"); if binding.wrappedValue == .dateDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .dateAsc }) {
                        HStack { Text("Oldest First"); if binding.wrappedValue == .dateAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Date"); if binding.wrappedValue == .dateAsc || binding.wrappedValue == .dateDesc { Image(systemName: "checkmark") } }
                }
                Menu {
                    Button(action: { binding.wrappedValue = .ratingDesc }) {
                        HStack { Text("High → Low"); if binding.wrappedValue == .ratingDesc { Image(systemName: "checkmark") } }
                    }
                    Button(action: { binding.wrappedValue = .ratingAsc }) {
                        HStack { Text("Low → High"); if binding.wrappedValue == .ratingAsc { Image(systemName: "checkmark") } }
                    }
                } label: {
                    HStack { Text("Rating"); if binding.wrappedValue == .ratingAsc || binding.wrappedValue == .ratingDesc { Image(systemName: "checkmark") } }
                }
            } label: {
                Text(binding.wrappedValue.displayName).foregroundColor(.secondary)
            }
        }
    }
}
#endif
