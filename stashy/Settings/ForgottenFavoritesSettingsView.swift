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
                    Label(tr("forgotten_favorites_requires_stashy_plus"), systemImage: "lock.fill")
                        .foregroundColor(.secondary)
                        .stashyGroupedSettingsRow()
                }
            } else if !engine.isFeatureOn {
                Section {
                    Label(engine.hasStatistics
                          ? tr("hint_forgotten_favorites_is_off_turn")
                          : tr("hint_turn_on_tag_suggestions_or_similar"),
                          systemImage: "info.circle")
                        .foregroundColor(.secondary)
                        .stashyGroupedSettingsRow()
                }
            }

            Section {
                stashyScrollingSectionHeader(tr("forgotten_favorites"), isBeta: true)
                HStack {
                    Label(tr("status"), systemImage: "clock.arrow.circlepath")
                    Spacer()
                    Text(statusText)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                .stashyGroupedSettingsRow()
                stashyScrollingSectionFooter(tr("hint_favorites_you_have_not_played"))
            }

            Section {
                stashyScrollingSectionHeader(tr("not_played_for"))
                Picker(tr("not_played_for"), selection: $engine.days) {
                    ForEach(ForgottenFavoritesEngine.dayChoices, id: \.self) { days in
                        Text(Self.daysTitle(days)).tag(days)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.vertical, 4)
                .stashyGroupedSettingsRow()
            }

            Section {
                stashyScrollingSectionHeader(tr("favorites"))
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("ranked_by"))
                    Picker(tr("ranked_by"), selection: $engine.ranking) {
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
                    Text(tr("top"))
                    Picker(tr("top"), selection: $engine.pool) {
                        ForEach(ForgottenFavoritesEngine.poolChoices, id: \.self) { size in
                            Text("\(size)").tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.vertical, 4)
                .stashyGroupedBlockRow(index: 1, count: 2)

            }

            Section {
                Button(role: .destructive) {
                    engine.resetSettings()
                } label: {
                    Label(tr("action_reset_to_defaults"), systemImage: "arrow.uturn.backward")
                        .foregroundColor(engine.hasCustomSettings ? .red : .secondary)
                }
                .disabled(!engine.hasCustomSettings)
                .stashyGroupedSettingsRow()
            }
        }
        .stashySettingsList()
        .applyAppBackground()
        .stashySettingsDetailChrome(tr("forgotten_favorites"))
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
        case .idle: return tr("not_built_yet")
        case .loading: return tr("looking_menu")
        case .preparing: return tr("waiting_for_statistics")
        case .ready: return "\(engine.items.count) of \(engine.poolCount) favorites"
        }
    }
}

#endif
