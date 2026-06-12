import Foundation
import Network

protocol ConnectivityMonitoring: AnyObject {
    var isOnline: Bool { get }
}

final class ConnectivityMonitor: ConnectivityMonitoring {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "YeatsVPN.Connectivity")
    private(set) var isOnline = true

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isOnline = path.status == .satisfied
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
