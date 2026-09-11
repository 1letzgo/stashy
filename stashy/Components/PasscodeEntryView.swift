import SwiftUI

struct PasscodeEntryView: View {
    @ObservedObject var securityManager = SecurityManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    @State private var passcode: String = ""
    @State private var errorMessage: String?
    @State private var shakeTrigger: Bool = false
    /// One Face ID / Touch ID prompt at a time — `onAppear` and the foreground transition
    /// can both fire for the same lock.
    @State private var isAuthenticating = false
    
    private var isLockedOut: Bool {
        securityManager.lockoutRemainingSeconds > 0
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            // Header – oberes Drittel
            VStack(spacing: 12) {
                Spacer().frame(height: 80)
                
                Image(systemName: "lock.fill")
                    .font(.system(size: 40))
                    .foregroundColor(appearanceManager.tintColor)
                
                Text("Enter Passcode")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if isLockedOut {
                    Text("Too many attempts. Try again in \(securityManager.lockoutRemainingSeconds)s")
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                } else if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
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
                .padding(.top, 8)
            }
            
            Spacer()
            
            // Keypad – unterer Bereich
            VStack(spacing: 12) {
                ForEach(0..<3) { row in
                    HStack(spacing: 0) {
                        ForEach(1..<4) { col in
                            let number = row * 3 + col
                            button(for: "\(number)")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                
                HStack(spacing: 0) {
                    Group {
                        if securityManager.isBiometricsEnabled && !isLockedOut {
                            Button(action: {
                                guard !isAuthenticating else { return }
                                isAuthenticating = true
                                securityManager.authenticateWithBiometrics { _ in
                                    isAuthenticating = false
                                }
                            }) {
                                Image(systemName: securityManager.biometryType == .faceID ? "faceid" : "touchid")
                                    .font(.title)
                                    .frame(height: 70)
                                    .frame(maxWidth: .infinity)
                            }
                        } else {
                            Color.clear
                                .frame(height: 70)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    
                    button(for: "0")
                        .frame(maxWidth: .infinity)
                    
                    Button(action: {
                        if !passcode.isEmpty {
                            passcode.removeLast()
                        }
                    }) {
                        Image(systemName: "delete.left")
                            .font(.title)
                            .frame(height: 70)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(isLockedOut)
                }
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(.primary)
            .opacity(isLockedOut ? 0.4 : 1)
            .allowsHitTesting(!isLockedOut)
            .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal)
        .background(Color.appBackground.ignoresSafeArea())
        .onChange(of: passcode) { _, newValue in
            if newValue.count == 4 {
                if securityManager.verifyPasscode(newValue) {
                    securityManager.unlock()
                } else {
                    errorMessage = isLockedOut
                        ? "Too many attempts. Try again in \(securityManager.lockoutRemainingSeconds)s"
                        : "Wrong Passcode"
                    shakeTrigger.toggle()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        passcode = ""
                        if !isLockedOut {
                            errorMessage = nil
                        }
                    }
                }
            }
        }
        .onAppear {
            securityManager.startLockoutTimerIfNeeded()
            // With auto-lock the view appears while the app is still in the background
            // (the lock fires in `sceneDidEnterBackground`); a prompt there is dropped by
            // the system. Only prompt now when the app is already active — otherwise the
            // scene-phase change below does it on the way back to the foreground.
            if UIApplication.shared.applicationState == .active {
                promptBiometricsSoon()
            }
        }
        // UIKit lifecycle (AppDelegate + UIHostingController): `scenePhase` is not reliable
        // here, the notification is. Fires on cold start and on every return from background.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            promptBiometricsSoon()
        }
    }

    /// Asks for biometrics after the lock view has settled; no-op while a prompt is up,
    /// biometrics are off, or the passcode is in lockout.
    private func promptBiometricsSoon() {
        guard securityManager.isBiometricsEnabled, !isLockedOut, !isAuthenticating else { return }
        isAuthenticating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard securityManager.isAppLocked else {
                isAuthenticating = false
                return
            }
            securityManager.authenticateWithBiometrics { _ in
                isAuthenticating = false
            }
        }
    }
    
    private func button(for number: String) -> some View {
        Button(action: {
            guard !isLockedOut else { return }
            if passcode.count < 4 {
                passcode.append(number)
            }
        }) {
            Text(number)
                .font(.title)
                .fontWeight(.medium)
                .frame(height: 70)
                .frame(maxWidth: .infinity)
                .background(
                    Circle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 70, height: 70)
                )
        }
        .disabled(isLockedOut)
    }
}
