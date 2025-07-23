import Foundation
import StoreKit

/// Monitors StoreKit transactions for original transaction IDs
public final class TransactionMonitor: NSObject {
    public static let shared = TransactionMonitor()
    
    // MARK: - Properties
    private var hasStarted = false
    private var hasCapturedTransaction = false // Flag to prevent duplicate captures
    private var transactionIdCallback: ((String) -> Void)?
    private let lockQueue = DispatchQueue(label: "com.asaattribution.transactionmonitor", attributes: .concurrent)
    
    #if os(iOS)
    private var storeKit2Task: Task<Void, Never>?
    #endif

    // MARK: - Initialization
    private override init() {
        super.init()
        ASAAttributionSDK.shared.logInfo("TransactionMonitor: Initialized singleton instance")
    }

    // MARK: - Public Methods
    
    /// Starts monitoring transactions and calls the callback when a transaction ID is captured
    /// - Parameter onTransactionId: Callback called once a transaction ID is available
    public func start(onTransactionId: @escaping (String) -> Void) {
        lockQueue.async(flags: .barrier) {
            ASAAttributionSDK.shared.logInfo("TransactionMonitor: start() called")
            
            guard !self.hasStarted else { 
                ASAAttributionSDK.shared.logInfo("TransactionMonitor: Already started, ignoring start() call")
                return 
            }
            
            ASAAttributionSDK.shared.logInfo("TransactionMonitor: Setting up transaction monitoring")
            self.hasStarted = true
            self.hasCapturedTransaction = false
            self.transactionIdCallback = onTransactionId
            
            DispatchQueue.main.async {
                ASAAttributionSDK.shared.logInfo("TransactionMonitor: Starting transaction monitoring")
                
                #if os(iOS)
                if #available(iOS 15.0, *) {
                    ASAAttributionSDK.shared.logInfo("TransactionMonitor: Using StoreKit 2 listener (iOS 15+)")
                    self.startStoreKit2Listener()
                } else {
                    ASAAttributionSDK.shared.logInfo("TransactionMonitor: Using StoreKit 1 listener (iOS < 15)")
                    self.startStoreKit1Listener()
                }
                #else
                ASAAttributionSDK.shared.logInfo("TransactionMonitor: Using StoreKit 1 listener (non-iOS platform)")
                self.startStoreKit1Listener()
                #endif
                
                // Also start StoreKit 1 listener for restored transactions even on iOS 15+
                // This ensures we capture any restored transactions that might not come through StoreKit 2
                #if os(iOS)
                if #available(iOS 15.0, *) {
                    ASAAttributionSDK.shared.logInfo("TransactionMonitor: Adding StoreKit 1 observer for additional coverage")
                    SKPaymentQueue.default().add(self)
                }
                #endif
            }
        }
    }
    
    /// Stops monitoring transactions
    public func stop() {
        lockQueue.async(flags: .barrier) {
            ASAAttributionSDK.shared.logInfo("TransactionMonitor: stop() called")
            
            guard self.hasStarted else { 
                ASAAttributionSDK.shared.logInfo("TransactionMonitor: Not started, ignoring stop() call")
                return 
            }
            
            ASAAttributionSDK.shared.logInfo("TransactionMonitor: Stopping transaction monitoring")
            
            self.hasStarted = false
            self.hasCapturedTransaction = true // Prevent any further captures
            self.transactionIdCallback = nil
            
            DispatchQueue.main.async {
                #if os(iOS)
                if #available(iOS 15.0, *) {
                    ASAAttributionSDK.shared.logInfo("TransactionMonitor: Cancelling StoreKit 2 task")
                    self.storeKit2Task?.cancel()
                    self.storeKit2Task = nil
                }
                #endif
                
                ASAAttributionSDK.shared.logInfo("TransactionMonitor: Removing from SKPaymentQueue")
                SKPaymentQueue.default().remove(self)
                ASAAttributionSDK.shared.logInfo("TransactionMonitor: Monitoring stopped successfully")
            }
        }
    }

    // MARK: - Private Methods
    
    private func handleTransactionId(_ id: String, source: String) {
        lockQueue.async(flags: .barrier) {
            // Check if we've already captured a transaction
            guard !self.hasCapturedTransaction && self.hasStarted else {
                ASAAttributionSDK.shared.logInfo("TransactionMonitor: Transaction ID from \(source) ignored - already captured or stopped")
                return
            }
            
            // Mark as captured immediately to prevent race conditions
            self.hasCapturedTransaction = true
            
            ASAAttributionSDK.shared.logInfo("TransactionMonitor: Transaction ID captured from \(source): \(id)")
            
            guard let callback = self.transactionIdCallback else {
                ASAAttributionSDK.shared.logInfo("TransactionMonitor: WARNING - No callback available for transaction ID: \(id)")
                return
            }
            
            // Call the callback on main queue
            DispatchQueue.main.async {
                ASAAttributionSDK.shared.logInfo("TransactionMonitor: Calling callback with transaction ID: \(id)")
                callback(id)
                
                ASAAttributionSDK.shared.logInfo("TransactionMonitor: Stopping monitoring after successful capture")
                self.stop()
            }
        }
    }

    // MARK: - StoreKit 2
    
    #if os(iOS)
    @available(iOS 15.0, *)
    private func startStoreKit2Listener() {
        ASAAttributionSDK.shared.logInfo("TransactionMonitor: Starting StoreKit 2 listener")
        
        storeKit2Task = Task.detached(priority: .background) { [weak self] in
            guard let self = self else { 
                ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 2 task - self is nil, exiting")
                return 
            }
            
            ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 2 task started, waiting for transaction updates")
            
            for await result in StoreKit.Transaction.updates {
                ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 2 received transaction update")
                
                // Check if we're still monitoring and haven't captured yet
                let shouldContinue = await self.lockQueue.sync {
                    return self.hasStarted && !self.hasCapturedTransaction
                }
                
                guard shouldContinue else { 
                    ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 2 - monitoring stopped or transaction already captured, breaking loop")
                    break 
                }
                
                do {
                    ASAAttributionSDK.shared.logInfo("TransactionMonitor: Verifying StoreKit 2 transaction")
                    let transaction = try self.checkVerified(result)
                    let originalId = String(transaction.originalID)
                    
                    ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 2 transaction verified, original ID: \(originalId)")
                    
                    self.handleTransactionId(originalId, source: "StoreKit 2")
                    
                    ASAAttributionSDK.shared.logInfo("TransactionMonitor: Finishing StoreKit 2 transaction")
                    await transaction.finish()
                    ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 2 transaction finished, breaking loop")
                    break // Stop after first successful capture
                } catch {
                    // Log error but continue monitoring
                    ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 2 transaction verification failed: \(error.localizedDescription)")
                }
            }
            
            ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 2 task completed")
        }
        
        ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 2 listener setup complete")
    }

    @available(iOS 15.0, *)
    private func checkVerified(_ result: StoreKit.VerificationResult<StoreKit.Transaction>) throws -> StoreKit.Transaction {
        ASAAttributionSDK.shared.logInfo("TransactionMonitor: Checking StoreKit 2 transaction verification")
        
        switch result {
        case .verified(let transaction):
            ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 2 transaction verified successfully")
            return transaction
        case .unverified(_, let error):
            ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 2 transaction verification failed: \(error.localizedDescription)")
            throw error
        }
    }
    #endif

    // MARK: - StoreKit 1
    
    private func startStoreKit1Listener() {
        ASAAttributionSDK.shared.logInfo("TransactionMonitor: Starting StoreKit 1 listener")
        ASAAttributionSDK.shared.logInfo("TransactionMonitor: Adding self to SKPaymentQueue")
        SKPaymentQueue.default().add(self)
        ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 listener setup complete")
        
        // Also trigger restore to catch any pending restored transactions
        ASAAttributionSDK.shared.logInfo("TransactionMonitor: Triggering restore completed transactions to catch any pending restorations")
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
}

// MARK: - StoreKit 1 Observer

extension TransactionMonitor: SKPaymentTransactionObserver {
    public func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - paymentQueue updated with \(transactions.count) transactions")
        
        // Check if we should continue processing
        let shouldContinue = lockQueue.sync {
            return hasStarted && !hasCapturedTransaction
        }
        
        guard shouldContinue else { 
            ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - monitoring not started or transaction already captured, ignoring transactions")
            return 
        }
        
        for (index, transaction) in transactions.enumerated() {
            // Double-check we haven't captured yet (in case of race conditions)
            let stillValid = lockQueue.sync {
                return hasStarted && !hasCapturedTransaction
            }
            
            guard stillValid else {
                ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - Transaction already captured, stopping processing")
                return
            }
            
            ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - Processing transaction \(index + 1)/\(transactions.count)")
            ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - Transaction state: \(transaction.transactionState.rawValue)")
            
            if let transactionId = transaction.transactionIdentifier {
                ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - Transaction ID: \(transactionId)")
            } else {
                ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - Transaction ID is nil")
            }
            
            if let originalTransaction = transaction.original {
                ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - Original transaction ID: \(originalTransaction.transactionIdentifier ?? "nil")")
            } else {
                ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - No original transaction")
            }
            
            switch transaction.transactionState {
            case .purchased:
                ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - Transaction purchased")
                let originalId = transaction.original?.transactionIdentifier ?? transaction.transactionIdentifier
                if let id = originalId {
                    ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - Using transaction ID: \(id)")
                    self.handleTransactionId(id, source: "StoreKit 1 Purchase")
                    return // Stop after first successful capture
                } else {
                    ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - WARNING: No transaction ID available for purchased transaction")
                }
                
            case .restored:
                ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - Transaction restored")
                // For restored transactions, we MUST use the original transaction ID
                if let originalTransaction = transaction.original,
                   let originalId = originalTransaction.transactionIdentifier {
                    ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - Using original transaction ID for restored transaction: \(originalId)")
                    self.handleTransactionId(originalId, source: "StoreKit 1 Restore")
                    return // Stop after first successful capture
                } else if let currentId = transaction.transactionIdentifier {
                    // Fallback to current transaction ID if original is not available
                    ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - WARNING: Original transaction not available, using current ID: \(currentId)")
                    self.handleTransactionId(currentId, source: "StoreKit 1 Restore (fallback)")
                    return // Stop after first successful capture
                } else {
                    ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - ERROR: No transaction ID available for restored transaction")
                }
                
            case .failed:
                ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - Transaction failed: \(transaction.error?.localizedDescription ?? "Unknown error")")
                if let error = transaction.error {
                    ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - Error code: \((error as NSError).code)")
                    ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - Error domain: \((error as NSError).domain)")
                }
                
            case .purchasing:
                ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - Transaction purchasing")
                
            case .deferred:
                ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - Transaction deferred")
                
            @unknown default:
                ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - Unknown transaction state: \(transaction.transactionState.rawValue)")
            }
        }
        
        ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - Finished processing all transactions")
    }
    
    public func paymentQueue(_ queue: SKPaymentQueue, removedTransactions transactions: [SKPaymentTransaction]) {
        ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - Removed \(transactions.count) transactions from queue")
    }
    
    public func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - Restore completed transactions finished")
        
        // Log all transactions in the queue to see what we have
        ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - Current queue has \(queue.transactions.count) transactions")
        for (index, transaction) in queue.transactions.enumerated() {
            ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - Queue transaction \(index): state=\(transaction.transactionState.rawValue), id=\(transaction.transactionIdentifier ?? "nil")")
        }
    }
    
    public func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - Restore completed transactions failed: \(error.localizedDescription)")
    }
    
    // MARK: - Additional StoreKit 1 delegate methods for comprehensive monitoring
    
    @available(iOS 13.0, macOS 10.15, *)
    public func paymentQueue(_ queue: SKPaymentQueue, shouldContinueTransaction transaction: SKPaymentTransaction, in storefront: SKStorefront) -> Bool {
        ASAAttributionSDK.shared.logInfo("TransactionMonitor: StoreKit 1 - shouldContinueTransaction called for transaction: \(transaction.transactionIdentifier ?? "nil")")
        return true // Continue processing
    }
} 
