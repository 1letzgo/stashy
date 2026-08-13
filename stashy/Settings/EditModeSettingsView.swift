#if !os(tvOS)
import SwiftUI

struct EditModeSettingsView: View {
    @ObservedObject var appearanceManager = AppearanceManager.shared

    var body: some View {
        List {
            Section {
                Toggle("Enable Editing", isOn: $appearanceManager.isEditModeEnabled)
                    .tint(appearanceManager.tintColor)
                    .stashyGroupedSettingsRow()
                stashyScrollingSectionFooter("Show edit buttons on scene detail cards (performers, studio, groups, tags, title, description) and on performer / studio / tag / group / gallery detail.")
            }
        }
        .stashySettingsList()
        .applyAppBackground()
        .stashySettingsDetailChrome("Editing")
    }
}
#endif
