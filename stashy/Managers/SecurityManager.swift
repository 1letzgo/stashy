import Foundation
import LocalAuthentication
import Combine

class SecurityManager: ObservableObject {
    static let shared = SecurityManager()
    
    @Published var isBiometricsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isBiometricsEnabled, forKey: kBiometricsEnabled)
        }
    }
    
    @Published var autoLockOnBackground: Bool {
        didSet {
            UserDefaults.standard.set(autoLockOnBackground, forKey: kAutoLockOnBackground)
        }
    }
    
    @Published var isAppLocked: Bool = false
    @Published var isPasscodeSet: Bool = false
    @Published var isPiPActive: Bool = false
    /// Seconds remaining in lockout after failed attempts; 0 when unlocked for entry.
    @Published private(set) var lockoutRemainingSeconds: Int = 0
    
    private let kBiometricsEnabled = "kBiometricsEnabled"
    private let kAutoLockOnBackground = "kAutoLockOnBackground"
    private let kFailedAttempts = "kPasscodeFailedAttempts"
    private let kLockoutUntil = "kPasscodeLockoutUntil"
    
    private var lockoutTimer: Timer?
    
    private init() {
        Self.clearOrphanedPasscodeAfterReinstallIfNeeded()
        self.isBiometricsEnabled = UserDefaults.standard.bool(forKey: kBiometricsEnabled)
        self.autoLockOnBackground = UserDefaults.standard.bool(forKey: kAutoLockOnBackground)
        // Triggers legacy plaintext → hash migration if needed.
        self.isPasscodeSet = KeychainManager.shared.hasAppPasscode()
        
        refreshLockoutState()
        
        // Lock initially if passcode is set
        if isPasscodeSet {
            self.isAppLocked = true
        }
    }
    
    /// UserDefaults die with the app; the Keychain PIN does not. After delete+reinstall
    /// the lock screen came back without Face ID (`kBiometricsEnabled` was gone) and
    /// no way to recover a forgotten 4-digit code. Treat "no app data + leftover PIN"
    /// as a fresh install and drop the orphaned hash.
    private static func clearOrphanedPasscodeAfterReinstallIfNeeded() {
        let defaults = UserDefaults.standard
        let hasAppData =
            defaults.object(forKey: "stashy_server_config") != nil
            || defaults.object(forKey: "stashy_saved_servers") != nil
            || defaults.object(forKey: "kBiometricsEnabled") != nil
            || defaults.object(forKey: "kAutoLockOnBackground") != nil
        guard !hasAppData, KeychainManager.shared.hasAppPasscode() else { return }
        KeychainManager.shared.deleteAppPasscode()
        AppLog.debug("🔓 Cleared Keychain passcode left over after reinstall")
    }

    func checkPasscodeStatus() {
        self.isPasscodeSet = KeychainManager.shared.hasAppPasscode()
    }
    
    func lock() {
        if isPasscodeSet {
            isAppLocked = true
        }
    }
    
    func unlock() {
        isAppLocked = false
        resetFailedAttempts()
    }
    
    func setPasscode(_ passcode: String) {
        guard passcode.count == 4, passcode.allSatisfy(\.isNumber) else { return }
        let salt = UUID().uuidString
        let hash = KeychainManager.sha256Hex(passcode + ":" + salt)
        if KeychainManager.shared.saveAppPasscodeHash(salt: salt, hash: hash) {
            isPasscodeSet = true
            resetFailedAttempts()
        }
    }
    
    func removePasscode() {
        if KeychainManager.shared.deleteAppPasscode() {
            isPasscodeSet = false
            isAppLocked = false
            isBiometricsEnabled = false
            resetFailedAttempts()
        }
    }
    
    /// Verifies PIN against salted hash. Enforces progressive lockout after failures.
    func verifyPasscode(_ input: String) -> Bool {
        refreshLockoutState()
        guard lockoutRemainingSeconds == 0 else { return false }
        guard input.count == 4 else { return false }
        guard let record = KeychainManager.shared.loadAppPasscodeRecord() else { return false }
        
        let candidate = KeychainManager.sha256Hex(input + ":" + record.salt)
        if candidate == record.hash {
            resetFailedAttempts()
            return true
        }
        
        registerFailedAttempt()
        return false
    }
    
    var isLockedOut: Bool {
        refreshLockoutState()
        return lockoutRemainingSeconds > 0
    }
    
    private func registerFailedAttempt() {
        let attempts = UserDefaults.standard.integer(forKey: kFailedAttempts) + 1
        UserDefaults.standard.set(attempts, forKey: kFailedAttempts)
        
        // Lock after every 5 failures: 30s, 1m, 2m, 5m, then 15m capped.
        guard attempts % 5 == 0 else { return }
        let tier = attempts / 5
        let delays: [TimeInterval] = [30, 60, 120, 300, 900]
        let delay = delays[min(tier, delays.count) - 1]
        let until = Date().addingTimeInterval(delay)
        UserDefaults.standard.set(until.timeIntervalSince1970, forKey: kLockoutUntil)
        refreshLockoutState()
        startLockoutTimerIfNeeded()
    }
    
    private func resetFailedAttempts() {
        UserDefaults.standard.removeObject(forKey: kFailedAttempts)
        UserDefaults.standard.removeObject(forKey: kLockoutUntil)
        lockoutRemainingSeconds = 0
        lockoutTimer?.invalidate()
        lockoutTimer = nil
    }
    
    private func refreshLockoutState() {
        let untilTs = UserDefaults.standard.double(forKey: kLockoutUntil)
        guard untilTs > 0 else {
            lockoutRemainingSeconds = 0
            return
        }
        let remaining = Int(ceil(untilTs - Date().timeIntervalSince1970))
        if remaining <= 0 {
            UserDefaults.standard.removeObject(forKey: kLockoutUntil)
            lockoutRemainingSeconds = 0
            lockoutTimer?.invalidate()
            lockoutTimer = nil
        } else {
            lockoutRemainingSeconds = remaining
        }
    }
    
    func startLockoutTimerIfNeeded() {
        refreshLockoutState()
        guard lockoutRemainingSeconds > 0 else { return }
        lockoutTimer?.invalidate()
        lockoutTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshLockoutState()
        }
    }
    
    func authenticateWithBiometrics(completion: @escaping (Bool) -> Void) {
        guard isBiometricsEnabled else {
            completion(false)
            return
        }
        
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            let reason = "Unlock Stashy library"
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authenticationError in
                DispatchQueue.main.async {
                    if success {
                        self.unlock()
                    }
                    completion(success)
                }
            }
        } else {
            completion(false)
        }
    }
    
    var biometryType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }
}
