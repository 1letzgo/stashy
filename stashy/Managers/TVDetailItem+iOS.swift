
#if !os(tvOS)
import Foundation
import SwiftUI

// MARK: - tvOS Navigation Protocols (iOS stub)
// These are used by shared models in the iOS target; tvOS has its own definitions.
protocol TVGridItem: Identifiable {
    var id: String { get }
    var name: String { get }
    var thumbnailURL: URL? { get }
    var sceneCountDisplay: Int { get }
}

protocol TVDetailItem: TVGridItem {
    var details: String? { get }
    var favorite: Bool? { get }
    var rating100: Int? { get }
}
#endif
re