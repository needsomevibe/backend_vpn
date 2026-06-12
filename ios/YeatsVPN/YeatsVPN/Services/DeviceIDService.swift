import Foundation
import UIKit

protocol DeviceIDServicing {
    var deviceId: String { get }
}

struct DeviceIDService: DeviceIDServicing {
    var deviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }
}
