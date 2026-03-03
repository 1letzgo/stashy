//
//  TVMainTabView.swift
//  stashyTV
//
//  Standard tvOS top-tab navigation using the Tab API (tvOS 18+).
//  Each tab gets its own NavigationStack with all destinations registered
//  at the stack root via withTVDestinations().
//

import SwiftUI

struct TVMainTabView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                NavigationStack {
                    TVDashboardView()
                        .withTVDestinations()
                }
            }

            Tab("Search", systemImage: "magnifyingglass") {
                NavigationStack {
                    TVSearchView()
                        .withTVDestinations()
                }
            }

            Tab("Scenes", systemImage: "film.fill") {
                NavigationStack {
                    TVScenesView(sortBy: .dateDesc)
                        .withTVDestinations()
                }
            }

            Tab("Performers", systemImage: "person.3.fill") {
                NavigationStack {
                    TVPerformersView()
                        .withTVDestinations()
                }
            }

            Tab("Studios", systemImage: "building.2.fill") {
                NavigationStack {
                    TVStudiosView()
                        .withTVDestinations()
                }
            }

            Tab("Tags", systemImage: "tag.fill") {
                NavigationStack {
                    TVTagsView()
                        .withTVDestinations()
                }
            }

            Tab("Groups", systemImage: "rectangle.stack.fill") {
                NavigationStack {
                    TVGroupsView()
                        .withTVDestinations()
                }
            }

            Tab("Settings", systemImage: "gear") {
                NavigationStack {
                    TVSettingsView()
                }
            }
        }
    }
}
