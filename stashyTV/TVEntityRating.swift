//
//  TVEntityRating.swift
//  stashyTV
//
//  Favorite / rating actions for performer and studio detail on tvOS. Favorite goes
//  through the same `StashDBViewModel` mutations as iOS. The rating is written on its
//  own (`{ id rating100 }`, like Match does): the iOS edit sheet's
//  `updatePerformerDetails` resends every field and would clear what the TV models
//  never loaded.
//

import SwiftUI

enum TVEntityRating {

    private static let performerMutation = """
        mutation PerformerRatingUpdate($input: PerformerUpdateInput!) {
            performerUpdate(input: $input) { id }
        }
        """

    private static let studioMutation = """
        mutation StudioRatingUpdate($input: StudioUpdateInput!) {
            studioUpdate(input: $input) { id }
        }
        """

    static func setPerformerRating(id: String, rating100: Int?) async -> Bool {
        let input: [String: Any] = ["id": id, "rating100": rating100 ?? NSNull()]
        do {
            let response: PerformerUpdateResponse = try await GraphQLClient.shared.execute(
                query: performerMutation, variables: ["input": input]
            )
            return response.data?.performerUpdate != nil
        } catch {
            AppLog.error("TV: performer rating update failed: \(error.localizedDescription)")
            return false
        }
    }

    static func setStudioRating(id: String, rating100: Int?) async -> Bool {
        let input: [String: Any] = ["id": id, "rating100": rating100 ?? NSNull()]
        do {
            let response: StudioUpdateResponse = try await GraphQLClient.shared.execute(
                query: studioMutation, variables: ["input": input]
            )
            return response.data?.studioUpdate != nil
        } catch {
            AppLog.error("TV: studio rating update failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Whole stars, the same 0–5 steps as the scene rating dialog.
    static func stars(_ rating100: Int?) -> Int {
        guard let rating100, rating100 > 0 else { return 0 }
        return Int((Double(rating100) / 20.0).rounded())
    }

    static func buttonTitle(_ rating100: Int?) -> String {
        let value = stars(rating100)
        return value == 0 ? "Rate" : "\(value)/5"
    }
}

extension View {
    /// The scene detail's rating picker: No Rating plus 1–5 stars as an action sheet.
    func tvRatingDialog(isPresented: Binding<Bool>,
                        current rating100: Int?,
                        onPick: @escaping (Int?) -> Void) -> some View {
        confirmationDialog("Rating", isPresented: isPresented, titleVisibility: .visible) {
            let current = TVEntityRating.stars(rating100)
            ForEach((0...5).reversed(), id: \.self) { stars in
                let label = stars == 0 ? "No Rating" : String(repeating: "★", count: stars)
                Button(stars == current ? "✓ \(label)" : label) {
                    onPick(stars == 0 ? nil : stars * 20)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
