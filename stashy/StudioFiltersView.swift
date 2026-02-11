//
//  StudioFiltersView.swift
//  stashy
//
//  Filter view for studios
//

#if !os(tvOS)
import SwiftUI

struct StudioFiltersView: View {
    @Binding var filters: StudioFilters
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Scene Count") {
                    HStack {
                        Text("Min")
                        Spacer()
                        TextField("Any", text: Binding(
                            get: {
                                if let count = filters.minSceneCount {
                                    return String(count)
                                }
                                return ""
                            },
                            set: { newValue in
                                if newValue.isEmpty {
                                    filters.minSceneCount = nil
                                } else if let intValue = Int(newValue), intValue > 0 {
                                    filters.minSceneCount = intValue
                                }
                            }
                        ))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                        .frame(width: 100)
                    }
                    
                    HStack {
                        Text("Max")
                        Spacer()
                        TextField("Any", text: Binding(
                            get: {
                                if let count = filters.maxSceneCount {
                                    return String(count)
                                }
                                return ""
                            },
                            set: { newValue in
                                if newValue.isEmpty {
                                    filters.maxSceneCount = nil
                                } else if let intValue = Int(newValue), intValue > 0 {
                                    filters.maxSceneCount = intValue
                                }
                            }
                        ))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                        .frame(width: 100)
                    }
                }
                
                Section("Options") {
                    Toggle("Has Scenes", isOn: $filters.hasScenes)
                }
                
                Section {
                    Button("Reset All Filters") {
                        filters = StudioFilters()
                    }
                    .foregroundColor(.red)
                    .disabled(!filters.isActive)
                }
            }
            .navigationTitle("Studio Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    StudioFiltersView(filters: .constant(StudioFilters()))
}
#endif
