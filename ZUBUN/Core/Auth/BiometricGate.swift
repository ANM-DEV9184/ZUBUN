//
//  BiometricGate.swift
//  ZUBUN
//
//  Face ID / Touch ID (or device passcode) gate used to unlock a *resumed* staff
//  PIN session (spec §7). Uses `.deviceOwnerAuthentication` so it falls back to
//  the passcode when biometrics aren't enrolled.
//
//  ⚠️ Add `NSFaceIDUsageDescription` to the target's Info for the Face ID path.
//

import Foundation
import LocalAuthentication

enum BiometricGate {
    /// True when the device can evaluate biometrics or a passcode.
    static var isAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    static func authenticate() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return true // nothing to authenticate against — don't lock the user out
        }
        let reason = String(localized: "biometric.reason", defaultValue: "Unlock your ZUBUN staff session")
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
