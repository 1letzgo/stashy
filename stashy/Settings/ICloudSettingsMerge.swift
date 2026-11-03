//
//  ICloudSettingsMerge.swift
//  stashy
//
//  The three-way rule behind the iCloud settings sync: what this device has, what iCloud has
//  and what both last agreed on decide which side moves. No Foundation state, so it stays testable.
//

enum ICloudSettingsMerge {
    enum Action: Equatable {
        /// Both sides already agree, or there is nothing on either side.
        case none
        case applyRemote
        case applyRemoteDeletion
        case pushLocal
        case pushLocalDeletion
    }

    /// - Parameters:
    ///   - local: this device's value, `nil` when it has none
    ///   - remote: iCloud's value, `nil` when iCloud has none; a deletion is `remoteIsDeletion`
    ///   - base: the value both sides last agreed on, `nil` when this device never synced it
    ///
    /// iCloud having *nothing* never deletes anything here: an empty store also means another
    /// account or a wiped store. Only an explicit deletion marker does.
    static func action(local: String?, remote: String?, remoteIsDeletion: Bool, base: String?) -> Action {
        guard let remote else {
            return local == nil ? .none : .pushLocal
        }
        if remoteIsDeletion {
            guard let local else { return .none }
            // Deleted elsewhere: only an untouched copy goes. Never-synced or edited ones survive.
            return local == base ? .applyRemoteDeletion : .pushLocal
        }
        guard let local else {
            return remote == base ? .pushLocalDeletion : .applyRemote
        }
        if local == remote { return .none }
        if remote == base { return .pushLocal }
        // A device joining, or both sides changed: iCloud wins.
        return .applyRemote
    }
}
