import Foundation
@testable import ASAAttributionSDK

/// Mock Transaction Monitor for testing
/// This allows controlled testing of transaction capture without real StoreKit transactions
final class MockTransactionMonitor: TransactionMonitoring {
    
    // MARK: - Properties
    private let transactionID: String
    private let delay: TimeInterval
    
    // MARK: - Initialization
    init(transactionID: String, delay: TimeInterval = 0.5) {
        self.transactionID = transactionID
        self.delay = delay
    }
    
    // MARK: - TransactionMonitoring Implementation
    func start(onTransactionId: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + delay) {
            onTransactionId(self.transactionID)
        }
    }
    
    func stop() {
        // Mock implementation - no-op for testing
    }
    
    // MARK: - Factory Methods
    
    /// Create a mock transaction monitor with specific transaction ID
    static func withTransaction(_ transactionID: String, delay: TimeInterval = 0.5) -> MockTransactionMonitor {
        return MockTransactionMonitor(transactionID: transactionID, delay: delay)
    }
    
    /// Create a mock transaction monitor with a generated test transaction ID
    static func withTestTransaction(delay: TimeInterval = 0.5) -> MockTransactionMonitor {
        let testTransactionID = "test_txn_\(Date().timeIntervalSince1970)_\(Int.random(in: 1000...9999))"
        return MockTransactionMonitor(transactionID: testTransactionID, delay: delay)
    }
} 