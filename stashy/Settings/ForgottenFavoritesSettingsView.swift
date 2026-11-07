//
//  ForgottenFavoritesSettingsView.swift
//  stashy
//
//  stashy+ — tuning for the Forgotten Favorites row on Home (`ForgottenFavoritesEngine`).
//

#if !os(tvOS)

import SwiftUI

struct ForgottenFavoritesSettingsView: View {
    @ObservedObject private var engine = ForgottenFavoritesEngine.shared
    @ObservedObject private var stashyPlus = StashyPlusManager.shared

    var body: some View {
        List {
            if !stashyPlus.isUnlocked {
                Section {
                    Label("Forgotten Favorites requires stashy+", systemImage: "lock.fill")
                        .foregroundColor(.secondary)
                        .stashyGroupedSettingsRow()
                }
            } else if !engine.isFeatureOn {
                Section {
                    Label(engine.hasStatistics
                          ? "Forgotten Favorites is off. Turn it on in Recommendations to show it on Home."
                          : "Turn on Tag suggestions or Similar scenes to show Forgotten Favorites on Home.",
                          systemImage: "info.circle")
                        .foregroundColor(.secondary)
                        .stashyGroupedSettingsRow()
                }
            }

            Section {
                stashyScrollingSectionHeader("Forgotten Favorites", isBeta: true)
                HStack {
                    Label("Status", systemImage: "clock.arrow.circlepath")
                    Spacer()
                    Text(statusText)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                .stashyGroupedSettingsRow()
                stashyScrollingSectionFooter("Scenes among your favorites that you have not played for a while. Everything is worked out on this device. Move or hide the row in Settings › Home.")
            }

            Section {
                stashyScrollingSectionHeader("Not played for")
                Picker("Not played for", selection: $engine.days) {
                    ForEach(ForgottenFavoritesEngine.dayChoices, id: \.self) { days in
                        Text(Self.daysTitle(days)).tag(days)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.vertical, 4)
                .stashyGroupedSettingsRow()
                stashyScrollingSectionFooter("A favorite shows up once you have not played it for this long.")
            }

            Section {
                stashyScrollingSectionHeader("Favorites")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ranked by")
                    Picker("Ranked by", selection: $engine.ranking) {
                        ForEach(ForgottenFavoritesRanking.allCases) { ranking in
                            Text(ranking.title).tag(ranking)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.vertical, 4)
                .stashyGroupedBlockRow(index: 0, count: 2)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Top")
                    Picker("Top", selection: $engine.pool) {
                        ForEach(ForgottenFavoritesEngine.poolChoices, id: \.self) { size in
                            Text("\(size)").tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.vertical, 4)
                .stashyGroupedBlockRow(index: 1, count: 2)

                stashyScrollingSectionFooter("\(engine.ranking.detail) Only the top \(engine.pool) of each count.")
            }

            Section {
                Button(role: .destructive) {
                    engine.resetSettings()
                } label: {
                    Label("Reset to defaults", systemImage: "arrow.uturn.backward")
                        .foregroundColor(engine.hasCustomSettings ? .red : .secondary)
                }
                .disabled(!engine.hasCustomSettings)
                .stashyGroupedSettingsRow()
            }
        }
        .stashySettingsList()
        .applyAppBackground()
        .stashySettingsDetailChrome("Forgotten Favorites")
        .disabled(!stashyPlus.isUnlocked)
        .onAppear { engine.refreshIfNeeded() }
    }

    private static func daysTitle(_ days: Int) -> String {
        switch days {
        case 365: return "1 year"
        case 180: return "6 mo"
        default: return "\(days) d"
        }
    }

    private var statusText: String {
        switch engine.state {
        case .idle: return "Not built yet"
        case .loading: return "Looking…"
        case .preparing: return "Waiting for statistics"
        case .ready: return "\(engine.items.count) of \(engine.poolCount) favorites"
        }
    }
}

#endif
