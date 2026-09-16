//
//  DownloadSyncJobs.swift
//  stashy
//
//  Saved download jobs: a server filter plus how many of its newest items to fetch.
//  Same shape as the merge templates — a row of pills with a "run all" button in front.
//

#if !os(tvOS)
import SwiftUI

/// One saved job. `filterId` is a server saved filter; the kind decides whether the job
/// downloads scenes or images.
struct DownloadSyncJob: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case scenes
        case images

        var icon: String { self == .scenes ? "film" : "photo" }
        var label: String { self == .scenes ? "scenes" : "images" }
    }

    let id: String
    var filterId: String
    var filterName: String
    var kind: Kind
    /// How many of the newest matching items one run fetches.
    var amount: Int

    init(id: String = UUID().uuidString, filterId: String, filterName: String, kind: Kind, amount: Int) {
        self.id = id
        self.filterId = filterId
        self.filterName = filterName
        self.kind = kind
        self.amount = amount
    }
}

/// Jobs are per server — a saved filter id means nothing on another one.
@MainActor
final class DownloadSyncJobStore: ObservableObject {
    static let shared = DownloadSyncJobStore()

    @Published private(set) var jobs: [DownloadSyncJob] = []

    private var storageKey: String {
        let serverId = ServerConfigManager.shared.activeConfig?.id.uuidString ?? "none"
        return "download_sync_jobs_\(serverId)"
    }

    private init() {
        load()
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ServerConfigChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.load() }
        }
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([DownloadSyncJob].self, from: data) else {
            jobs = []
            return
        }
        jobs = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(jobs) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    func add(_ job: DownloadSyncJob) {
        jobs.append(job)
        save()
    }

    func update(_ job: DownloadSyncJob) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        jobs[index] = job
        save()
    }

    func remove(_ job: DownloadSyncJob) {
        jobs.removeAll { $0.id == job.id }
        save()
    }
}

/// Runs jobs against the download manager.
@MainActor
enum DownloadSyncJobRunner {
    static func run(_ job: DownloadSyncJob, filters: [String: StashDBViewModel.SavedFilter], viewModel: StashDBViewModel) {
        guard let filter = filters[job.filterId] else {
            ToastManager.shared.show("Filter for \(job.filterName) is gone", icon: "exclamationmark.triangle", style: .error)
            return
        }
        let criteria = viewModel.sanitizeFilter(filter.filterDict ?? [:])
        switch job.kind {
        case .scenes:
            DownloadManager.shared.downloadScenes(
                for: .savedFilter(sceneFilter: criteria),
                limit: job.amount,
                scopeName: job.filterName
            )
        case .images:
            DownloadManager.shared.downloadFilterImages(
                filterId: job.filterId,
                filterName: job.filterName,
                imageFilter: criteria,
                limit: job.amount
            )
        }
    }

    static func runAll(_ jobs: [DownloadSyncJob], filters: [String: StashDBViewModel.SavedFilter], viewModel: StashDBViewModel) {
        for job in jobs {
            run(job, filters: filters, viewModel: viewModel)
        }
    }
}
#endif
