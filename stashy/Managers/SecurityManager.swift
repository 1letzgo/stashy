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
    
    private let kBiometricsEnabled = "kBiometricsEnabled"
    private let kAutoLockOnBackground = "kAutoLockOnBackground"
    
    private init() {
        self.isBiometricsEnabled = UserDefaults.standard.bool(forKey: kBiometricsEnabled)
        self.autoLockOnBackground = UserDefaults.standard.bool(forKey: kAutoLockOnBackground)
        self.isPasscodeSet = KeychainManager.shared.loadAppPasscode() != nil
        
        // Lock initially if passcode is set
        if isPasscodeSet {
            self.isAppLocked = true
        }
    }
    
    func checkPasscodeStatus() {
        self.isPasscodeSet = KeychainManager.shared.loadAppPasscode() != nil
    }
    
    func lock() {
        if isPasscodeSet {
            isAppLocked = true
        }
    }
    
    func unlock() {
        isAppLocked = false
    }
    
    func setPasscode(_ passcode: String) {
        if KeychainManager.shared.saveAppPasscode(passcode) {
            isPasscodeSet = true
        }
    }
    
    func removePasscode() {
        if KeychainManager.shared.deleteAppPasscode() {
            isPasscodeSet = false
            isAppLocked = false
            isBiometricsEnabled = false
        }
    }
    
    func verifyPasscode(_ input: String) -> Bool {
        guard let saved = KeychainManager.shared.loadAppPasscode() else { return false }
        return saved == input
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
