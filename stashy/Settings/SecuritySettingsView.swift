import SwiftUI

struct SecuritySettingsView: View {
    @ObservedObject var securityManager = SecurityManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    @State private var showingSetPasscode = false
    @State private var tempPasscode: String = ""
    @State private var setPasscodeStep: SetPasscodeStep = .initial
    
    enum SetPasscodeStep {
        case initial, confirm
    }
    
    var body: some View {
        Form {
            Section(header: Text("App Lock")) {
                if securityManager.isPasscodeSet {
                    Button("Change Passcode") {
                        resetSetPasscode()
                        showingSetPasscode = true
                    }
                    
                    Button("Remove Passcode", role: .destructive) {
                        securityManager.removePasscode()
                    }
                    
                    Toggle("Use \(securityManager.biometryType == .faceID ? "FaceID" : "Biometrics")", isOn: $securityManager.isBiometricsEnabled)
                        .tint(appearanceManager.tintColor)
                        .disabled(!securityManager.isPasscodeSet)
                } else {
                    Button("Enable Passcode Lock") {
                        resetSetPasscode()
                        showingSetPasscode = true
                    }
                }
            }
            .listRowBackground(Color.secondaryAppBackground)
            
            if securityManager.isPasscodeSet {
                Section(header: Text("Options"), footer: Text("The app will automatically lock whenever it is moved to the background.")) {
                    Toggle("Auto-lock on Background", isOn: $securityManager.autoLockOnBackground)
                        .tint(appearanceManager.tintColor)
                }
                .listRowBackground(Color.secondaryAppBackground)
            }
        }
        .navigationTitle("Security")
        .applyAppBackground()
        .sheet(isPresented: $showingSetPasscode) {
            PasscodeSetupView(isPresented: $showingSetPasscode)
        }
    }
    
    private func resetSetPasscode() {
        tempPasscode = ""
        setPasscodeStep = .initial
    }
}

struct PasscodeSetupView: View {
    @Binding var isPresented: Bool
    @ObservedObject var securityManager = SecurityManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    @State private var passcode: String = ""
    @State private var confirmPasscode: String = ""
    @State private var step: Int = 1 // 1: initial, 2: confirm
    @State private var errorMessage: String?
    @State private var shakeTrigger: Bool = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                VStack(spacing: 12) {
                    Text(step == 1 ? "Set a Passcode" : "Confirm Passcode")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                HStack(spacing: 20) {
                    ForEach(0..<4) { index in
                        Circle()
                            .fill(index < (step == 1 ? passcode.count : confirmPasscode.count) ? appearanceManager.tintColor : Color.secondary.opacity(0.3))
                            .frame(width: 15, height: 15)
                    }
                }
                .offset(x: shakeTrigger ? 10 : 0)
                .animation(.default, value: shakeTrigger)
                
                VStack(spacing: 20) {
                    ForEach(0..<3) { row in
                        HStack(spacing: 40) {
                            ForEach(1..<4) { col in
                                let number = row * 3 + col
                                keypadButton(for: "\(number)")
                            }
                        }
                    }
                    HStack(spacing: 40) {
                        Spacer().frame(width: 70, height: 70)
                        keypadButton(for: "0")
                        Button(action: {
                            if step == 1 {
                                if !passcode.isEmpty { passcode.removeLast() }
                            } else {
                                if !confirmPasscode.isEmpty { confirmPasscode.removeLast() }
                            }
                        }) {
                            Image(systemName: "delete.left")
                                .font(.title)
                                .frame(width: 70, height: 70)
                        }
                    }
                }
                .foregroundColor(.primary)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Passcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
            .onChange(of: passcode) { _, newValue in
                if step == 1 && newValue.count == 4 {
                    step = 2
                }
            }
            .onChange(of: confirmPasscode) { _, newValue in
                if step == 2 && newValue.count == 4 {
                    if passcode == confirmPasscode {
                        securityManager.setPasscode(passcode)
                        isPresented = false
                    } else {
                        errorMessage = "Passcodes do not match"
                        shakeTrigger.toggle()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            confirmPasscode = ""
                            passcode = ""
                            step = 1
                            errorMessage = nil
                        }
                    }
                }
            }
        }
    }
    
    private func keypadButton(for number: String) -> some View {
        Button(action: {
            if step == 1 {
                if passcode.count < 4 { passcode.append(number) }
            } else {
                if confirmPasscode.count < 4 { confirmPasscode.append(number) }
            }
        }) {
            Text(number)
                .font(.title)
                .frame(width: 70, height: 70)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Circle())
        }
    }
}
