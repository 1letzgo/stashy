#if !os(tvOS)
import SwiftUI

struct EditModeSettingsView: View {
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @AppStorage(DeleteActions.key) private var showsDeleteButton = true

    var body: some View {
        List {
            Section {
                Toggle(tr("action_enable_editing"), isOn: $appearanceManager.isEditModeEnabled)
                    .tint(appearanceManager.tintColor)
                    .stashyGroupedSettingsRow()
                stashyScrollingSectionFooter(tr("hint_show_edit_buttons_on_scene"))
            }
            Section {
                Toggle(tr("action_show_delete_button"), isOn: $showsDeleteButton)
                .tint(appearanceManager.tintColor)
                .stashyGroupedSettingsRow()
                stashyScrollingSectionFooter(tr("hint_show_delete_button"))
            }
        }
        .stashySettingsList()
        .applyAppBackground()
        .stashySettingsDetailChrome(tr("editing"))
    }
}
#endif
