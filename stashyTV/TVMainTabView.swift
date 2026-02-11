//
//  TVMainTabView.swift
//  stashyTV
//
//  Created for stashy tvOS.
//

import SwiftUI

struct TVMainTabView: View {
    @ObservedObject private var appearanceManager = AppearanceManager.shared

    var body: some View {
        TabView {
            NavigationStack {
                TVDashboardView()
            }
            .tabItem {
                Label("Dashboard", systemImage: "chart.bar.fill")
            }

/*
            NavigationStack {
                TVScenesView()
            }
            .tabItem {
                Label("Scenes", systemImage: "film")
            }
*/

            NavigationStack {
                TVPerformersView()
            }
            .tabItem {
                Label("Performers", systemImage: "person.3")
            }

            NavigationStack {
                TVStudiosView()
            }
            .tabItem {
                Label("Studios", systemImage: "building.2")
            }

            NavigationStack {
                TVTagsView()
            }
            .tabItem {
                Label("Tags", systemImage: "tag")
            }

            NavigationStack {
                TVSearchView()
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }

            NavigationStack {
                TVSettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
        .tint(appearanceManager.tintColor)
    }
}
