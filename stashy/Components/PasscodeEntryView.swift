import SwiftUI

struct PasscodeEntryView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
                
                Text(tr("enter_passcode"))
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if isLockedOut {
                    Text(tr("hint_too_many_attempts_try_again", securityManager.lockoutRemainingSeconds))
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
                .modifier(PasscodeShake(trigger: shakeTrigger))
                .animation(.snappy(duration: 0.15), value: passcode.count)
                .padding(.top, 8)
                .accessibilityElement()
                .accessibilityLabel(tr("hint_arg_of_4_digits_entered", passcode.count))
            }
            
            Spacer()
            
            // Keypad – unterer Bereich
            VStack(spacing: 16) {
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
                                HapticManager.light()
                                isAuthenticating = true
                                securityManager.authenticateWithBiometrics { _ in
                                    isAuthenticating = false
                                }
                            }) {
                                Image(systemName: securityManager.biometryType == .faceID ? "faceid" : "touchid")
                                    .font(.title)
                            }
                            .buttonStyle(PasscodeKeyStyle(filled: false))
                            .accessibilityLabel(securityManager.biometryType == .faceID ? tr("action_unlock_with_face_id") : tr("action_unlock_with_touch_id"))
                            .frame(maxWidth: .infinity)
                        } else {
                            Color.clear
                                .frame(height: PasscodeKeyStyle.size)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    
                    button(for: "0")
                        .frame(maxWidth: .infinity)
                    
                    Button(action: {
                        guard !passcode.isEmpty else { return }
                        HapticManager.selection()
                        passcode.removeLast()
                    }) {
                        Image(systemName: "delete.left")
                            .font(.title2)
                    }
                    .buttonStyle(PasscodeKeyStyle(filled: false))
                    .accessibilityLabel(tr("action_delete"))
                    .frame(maxWidth: .infinity)
                    .opacity(passcode.isEmpty ? 0.35 : 1)
                    .disabled(isLockedOut)
                }
            }
            // iPhone-sized keypad on every device: on iPad the three columns spread across
            // the full width and the keys drifted far apart.
            .frame(maxWidth: 320)
            .frame(maxWidth: .infinity)
            .foregroundColor(.primary)
            .opacity(isLockedOut ? 0.4 : 1)
            .allowsHitTesting(!isLockedOut)
            .padding(.bottom, 30)
        }
        // iPad: header and keypad stay together as one iPhone-sized block, centred. iPhone keeps
        // its full-height layout with the keypad at the bottom.
        .frame(maxWidth: horizontalSizeClass == .regular ? 420 : .infinity,
               maxHeight: horizontalSizeClass == .regular ? 760 : .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal)
        .background(Color.appBackground.ignoresSafeArea())
        .onChange(of: passcode) { _, newValue in
            if newValue.count == 4 {
                if securityManager.verifyPasscode(newValue) {
                    HapticManager.success()
                    securityManager.unlock()
                } else {
                    HapticManager.error()
                    errorMessage = isLockedOut
                        ? tr("hint_too_many_attempts_try_again", securityManager.lockoutRemainingSeconds)
                        : tr("wrong_passcode")
                    shakeTrigger.toggle()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
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
            guard !isLockedOut, passcode.count < 4 else { return }
            HapticManager.light()
            passcode.append(number)
        }) {
            Text(number)
                .font(.system(size: 34, weight: .regular, design: .rounded))
                .monospacedDigit()
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .buttonStyle(PasscodeKeyStyle(filled: true))
        .disabled(isLockedOut)
    }
}

/// A keypad key like the system's: a round key that lights up under the finger and lets go
/// with a short fade, so every tap is felt and seen.
private struct PasscodeKeyStyle: ButtonStyle {
    static let size: CGFloat = 76
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: Self.size, height: Self.size)
            .background(
                Circle().fill(Color.primary.opacity(fillOpacity(pressed: configuration.isPressed)))
            )
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(
                configuration.isPressed ? .easeOut(duration: 0.05) : .easeOut(duration: 0.3),
                value: configuration.isPressed
            )
    }

    private func fillOpacity(pressed: Bool) -> Double {
        if pressed { return 0.28 }
        return filled ? 0.1 : 0
    }
}

/// Wrong code: the dots shake side to side and settle, like the system passcode screen.
private struct PasscodeShake: ViewModifier {
    let trigger: Bool

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGFloat(0), trigger: trigger) { view, offset in
            view.offset(x: offset)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(-14, duration: 0.06)
                LinearKeyframe(12, duration: 0.07)
                LinearKeyframe(-9, duration: 0.07)
                LinearKeyframe(6, duration: 0.07)
                LinearKeyframe(-3, duration: 0.06)
                SpringKeyframe(0, duration: 0.12)
            }
        }
    }
}
