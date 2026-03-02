import SwiftUI

struct PasscodeEntryView: View {
    @ObservedObject var securityManager = SecurityManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    @State private var passcode: String = ""
    @State private var errorMessage: String?
    @State private var shakeTrigger: Bool = false
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            VStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 40))
                    .foregroundColor(appearanceManager.tintColor)
                
                Text("Enter Passcode")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            
            // Passcode Indicators
            HStack(spacing: 20) {
                ForEach(0..<4) { index in
                    Circle()
                        .fill(index < passcode.count ? appearanceManager.tintColor : Color.secondary.opacity(0.3))
                        .frame(width: 15, height: 15)
                }
            }
            .offset(x: shakeTrigger ? 10 : 0)
            .animation(.default, value: shakeTrigger)
            
            // Numeric Keypad
            VStack(spacing: 20) {
                ForEach(0..<3) { row in
                    HStack(spacing: 40) {
                        ForEach(1..<4) { col in
                            let number = row * 3 + col
                            button(for: "\(number)")
                        }
                    }
                }
                
                HStack(spacing: 40) {
                    // Biometric Button
                    if securityManager.isBiometricsEnabled {
                        Button(action: {
                            securityManager.authenticateWithBiometrics { _ in }
                        }) {
                            Image(systemName: securityManager.biometryType == .faceID ? "faceid" : "touchid")
                                .font(.title)
                                .frame(width: 70, height: 70)
                        }
                    } else {
                        Spacer().frame(width: 70, height: 70)
                    }
                    
                    button(for: "0")
                    
                    // Backspace
                    Button(action: {
                        if !passcode.isEmpty {
                            passcode.removeLast()
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
        .onChange(of: passcode) { _, newValue in
            if newValue.count == 4 {
                if securityManager.verifyPasscode(newValue) {
                    securityManager.unlock()
                } else {
                    errorMessage = "Wrong Passcode"
                    shakeTrigger.toggle()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        passcode = ""
                        errorMessage = nil
                    }
                }
            }
        }
        .onAppear {
            if securityManager.isBiometricsEnabled {
                // Small delay to allow appearance animation to start smoothly
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    securityManager.authenticateWithBiometrics { _ in }
                }
            }
        }
    }
    
    private func button(for number: String) -> some View {
        Button(action: {
            if passcode.count < 4 {
                passcode.append(number)
            }
        }) {
            Text(number)
                .font(.title)
                .fontWeight(.medium)
                .frame(width: 70, height: 70)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Circle())
        }
    }
}
