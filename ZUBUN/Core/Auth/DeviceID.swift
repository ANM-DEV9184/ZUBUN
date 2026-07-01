//
//  DeviceID.swift
//  ZUBUN
//
//  Stable device id for staff session binding. Sent as `X-Device-Id` on
//  login/onboard AND every staff request (spec §9.2). Prefers
//  identifierForVendor; persists a fallback UUID in the Keychain so the
//  binding survives an IDFV reset within the app's lifetime.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum DeviceID {
    private static let key = "zubun.device.id"

    static var current: String {
        #if canImport(UIKit)
        if let idfv = UIDevice.current.identifierForVendor?.uuidString {
            return idfv
        }
        #endif
        if let stored = Keychain.get(key) { return stored }
        let fresh = UUID().uuidString
        Keychain.set(fresh, for: key)
        return fresh
    }
}
