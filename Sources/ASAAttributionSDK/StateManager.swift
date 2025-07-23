import Foundation
import os.log
import os

/// Manages retry logic and exponential backoff for failed operations
public final class RetryManager {
    
    // MARK: - Operation Types
    public enum OperationType: String, CaseIterable {
        case createUser = "create_user"
        case resolveAttribution = "resolve_attribution"
        case associateUser = "associate_user"
    }
    
    // MARK: - Retry Configuration
    private struct RetryConfig {
        let maxRetries: Int
        let baseDelay: TimeInterval
        let maxDelay: TimeInterval
        let backoffMultiplier: Double
        let jitterRange: ClosedRange<Double>
        
        static let `default` = RetryConfig(
            maxRetries: 3,
            baseDelay: 1.0,        // Start with 1 second
            maxDelay: 300.0,       // Cap at 5 minutes
            backoffMultiplier: 2.0, // Double each time
            jitterRange: 0.8...1.2  // ±20% jitter
        )
    }
    
    // MARK: - Failure Tracking
    private struct FailureInfo {
        let consecutiveFailures: Int
        let lastFailureTime: Date
        let nextRetryTime: Date
    }
    
    // MARK: - Properties
    private let userDefaults: UserDefaults
    private let queue = DispatchQueue(label: "com.asaattribution.sdk.retrymanager", attributes: .concurrent)
    private let config = RetryConfig.default
    
    // MARK: - State Keys
    private enum StateKey: String {
        case createUserFailures = "ai.asagent.retry.create_user_failures"
        case createUserLastFailure = "ai.asagent.retry.create_user_last_failure"
        case resolveAttributionFailures = "ai.asagent.retry.resolve_attribution_failures"
        case resolveAttributionLastFailure = "ai.asagent.retry.resolve_attribution_last_failure"
        case associateUserFailures = "ai.asagent.retry.associate_user_failures"
        case associateUserLastFailure = "ai.asagent.retry.associate_user_last_failure"
    }
    
    // MARK: - Initialization
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    // MARK: - Public Methods
    
    /// Check if an operation can be retried
    /// - Parameter operation: The operation type to check
    /// - Returns: True if operation can be retried now, false if in backoff period
    public func canRetry(_ operation: OperationType) -> Bool {
        return queue.sync {
            guard let failureInfo = getFailureInfo(for: operation) else {
                return true // No previous failures
            }
            
            // Check if we've exceeded max retries
            if failureInfo.consecutiveFailures >= config.maxRetries {
                // Reset after a long period (24 hours)
                if Date().timeIntervalSince(failureInfo.lastFailureTime) > 86400 {
                    resetFailures(for: operation)
                    return true
                }
                return false
            }
            
            // Check if enough time has passed since last failure
            return Date() >= failureInfo.nextRetryTime
        }
    }
    
    /// Get the time until next retry is allowed
    /// - Parameter operation: The operation type to check
    /// - Returns: Time interval until next retry, or 0 if can retry now
    public func timeUntilNextRetry(_ operation: OperationType) -> TimeInterval {
        return queue.sync {
            guard let failureInfo = getFailureInfo(for: operation) else {
                return 0 // No failures, can retry immediately
            }
            
            let timeRemaining = failureInfo.nextRetryTime.timeIntervalSince(Date())
            return max(0, timeRemaining)
        }
    }
    
    /// Record a successful operation
    /// - Parameter operation: The operation that succeeded
    public func recordSuccess(_ operation: OperationType) {
        queue.async(flags: .barrier) {
            self.resetFailures(for: operation)
        }
    }
    
    /// Record a failed operation
    /// - Parameter operation: The operation that failed
    public func recordFailure(_ operation: OperationType) {
        queue.async(flags: .barrier) {
            let currentFailures = self.getConsecutiveFailures(for: operation)
            let newFailureCount = currentFailures + 1
            let now = Date()
            
            // Calculate next retry time with exponential backoff and jitter
            let backoffDelay = min(
                self.config.baseDelay * pow(self.config.backoffMultiplier, Double(currentFailures)),
                self.config.maxDelay
            )
            
            // Add jitter to prevent thundering herd
            let jitter = Double.random(in: self.config.jitterRange)
            let finalDelay = backoffDelay * jitter
            let nextRetryTime = now.addingTimeInterval(finalDelay)
            
            // Store failure info
            self.setConsecutiveFailures(newFailureCount, for: operation)
            self.setLastFailureTime(now, for: operation)
            
            // Log the backoff
            let message = "Operation \(operation.rawValue) failed \(newFailureCount) times. Next retry in \(String(format: "%.1f", finalDelay)) seconds"
            self.logRetryInfo(message)
        }
    }
    
    /// Get failure statistics for debugging
    /// - Parameter operation: The operation to check
    /// - Returns: Failure info string for debugging
    public func getFailureStats(_ operation: OperationType) -> String {
        return queue.sync {
            guard let failureInfo = getFailureInfo(for: operation) else {
                return "\(operation.rawValue): No failures"
            }
            
            let timeUntilRetry = max(0, failureInfo.nextRetryTime.timeIntervalSince(Date()))
            return "\(operation.rawValue): \(failureInfo.consecutiveFailures) failures, next retry in \(String(format: "%.1f", timeUntilRetry))s"
        }
    }
    
    /// Reset all failure tracking (useful for testing)
    func resetAllFailures() {
        queue.async(flags: .barrier) {
            for operation in OperationType.allCases {
                self.resetFailures(for: operation)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func getFailureInfo(for operation: OperationType) -> FailureInfo? {
        let failures = getConsecutiveFailures(for: operation)
        guard failures > 0, let lastFailureTime = getLastFailureTime(for: operation) else {
            return nil
        }
        
        // Calculate next retry time
        let backoffDelay = min(
            config.baseDelay * pow(config.backoffMultiplier, Double(failures - 1)),
            config.maxDelay
        )
        let jitter = Double.random(in: config.jitterRange)
        let finalDelay = backoffDelay * jitter
        let nextRetryTime = lastFailureTime.addingTimeInterval(finalDelay)
        
        return FailureInfo(
            consecutiveFailures: failures,
            lastFailureTime: lastFailureTime,
            nextRetryTime: nextRetryTime
        )
    }
    
    private func getConsecutiveFailures(for operation: OperationType) -> Int {
        let key = getFailuresKey(for: operation)
        return userDefaults.integer(forKey: key)
    }
    
    private func setConsecutiveFailures(_ count: Int, for operation: OperationType) {
        let key = getFailuresKey(for: operation)
        if count <= 0 {
            userDefaults.removeObject(forKey: key)
        } else {
            userDefaults.set(count, forKey: key)
        }
    }
    
    private func getLastFailureTime(for operation: OperationType) -> Date? {
        let key = getLastFailureKey(for: operation)
        return userDefaults.object(forKey: key) as? Date
    }
    
    private func setLastFailureTime(_ date: Date, for operation: OperationType) {
        let key = getLastFailureKey(for: operation)
        userDefaults.set(date, forKey: key)
    }
    
    private func resetFailures(for operation: OperationType) {
        setConsecutiveFailures(0, for: operation)
        let lastFailureKey = getLastFailureKey(for: operation)
        userDefaults.removeObject(forKey: lastFailureKey)
    }
    
    private func getFailuresKey(for operation: OperationType) -> String {
        switch operation {
        case .createUser: return StateKey.createUserFailures.rawValue
        case .resolveAttribution: return StateKey.resolveAttributionFailures.rawValue
        case .associateUser: return StateKey.associateUserFailures.rawValue
        }
    }
    
    private func getLastFailureKey(for operation: OperationType) -> String {
        switch operation {
        case .createUser: return StateKey.createUserLastFailure.rawValue
        case .resolveAttribution: return StateKey.resolveAttributionLastFailure.rawValue
        case .associateUser: return StateKey.associateUserLastFailure.rawValue
        }
    }
    
    private func logRetryInfo(_ message: String) {
        // Only log in non-production environments
        #if DEBUG
        // Use the same logging infrastructure as the main SDK
        if #available(iOS 14.0, macOS 11.0, *) {
            let logger = Logger(subsystem: "com.asaattribution.sdk", category: "RetryManager")
            logger.info("\(message, privacy: .public)")
        } else {
            let osLog = OSLog(subsystem: "com.asaattribution.sdk", category: "RetryManager")
            os_log("%{public}@", log: osLog, type: .info, message)
        }
        #endif
    }
}

// MARK: - Import required for logging

/// Manages persistent state for the ASA Attribution SDK
final class StateManager {
    
    // MARK: - State Keys
    private enum StateKey: String, CaseIterable {
        case userCreated = "ai.asagent.user_created"
        case attributionResolved = "ai.asagent.attribution_resolved"
        case isASAUser = "ai.asagent.is_asa_user"
        case transactionCaptured = "ai.asagent.transaction_captured"
        case associationComplete = "ai.asagent.association_complete"
        case userId = "ai.asagent.user_id"
        case originalTransactionID = "ai.asagent.original_transaction_id"
    }
    
    // MARK: - Properties
    private let userDefaults: UserDefaults
    private let queue = DispatchQueue(label: "com.asaattribution.sdk.statemanager", attributes: .concurrent)
    let retryManager: RetryManager
    
    // MARK: - Initialization
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.retryManager = RetryManager(userDefaults: userDefaults)
    }
    
    // MARK: - State Properties
    
    /// Whether a user has been created in the backend
    var userCreated: Bool {
        get { queue.sync { userDefaults.bool(forKey: StateKey.userCreated.rawValue) } }
        set { queue.async(flags: .barrier) { self.userDefaults.set(newValue, forKey: StateKey.userCreated.rawValue) } }
    }
    
    /// Whether ASA attribution has been resolved (success or failure)
    var attributionResolved: Bool {
        get { queue.sync { userDefaults.bool(forKey: StateKey.attributionResolved.rawValue) } }
        set { queue.async(flags: .barrier) { self.userDefaults.set(newValue, forKey: StateKey.attributionResolved.rawValue) } }
    }
    
    /// Whether the user is an ASA user (only valid when attributionResolved is true)
    var isASAUser: Bool {
        get { queue.sync { userDefaults.bool(forKey: StateKey.isASAUser.rawValue) } }
        set { queue.async(flags: .barrier) { self.userDefaults.set(newValue, forKey: StateKey.isASAUser.rawValue) } }
    }
    
    /// Whether a transaction ID has been captured
    var transactionCaptured: Bool {
        get { queue.sync { userDefaults.bool(forKey: StateKey.transactionCaptured.rawValue) } }
        set { queue.async(flags: .barrier) { self.userDefaults.set(newValue, forKey: StateKey.transactionCaptured.rawValue) } }
    }
    
    /// Whether the user-transaction association is complete
    var associationComplete: Bool {
        get { queue.sync { userDefaults.bool(forKey: StateKey.associationComplete.rawValue) } }
        set { queue.async(flags: .barrier) { self.userDefaults.set(newValue, forKey: StateKey.associationComplete.rawValue) } }
    }
    
    /// User ID from the backend
    var userId: String? {
        get { queue.sync { userDefaults.string(forKey: StateKey.userId.rawValue) } }
        set { queue.async(flags: .barrier) { self.userDefaults.set(newValue, forKey: StateKey.userId.rawValue) } }
    }
    
    /// Original transaction ID from StoreKit
    var originalTransactionID: String? {
        get { queue.sync { userDefaults.string(forKey: StateKey.originalTransactionID.rawValue) } }
        set { queue.async(flags: .barrier) { self.userDefaults.set(newValue, forKey: StateKey.originalTransactionID.rawValue) } }
    }
    
    // MARK: - Computed Properties
    
    /// Whether the SDK should terminate operations (non-ASA user or completed flow)
    var shouldTerminate: Bool {
        return queue.sync {
            return (attributionResolved && !isASAUser) || associationComplete
        }
    }
    
    /// Whether all required data is available for association
    var canAssociate: Bool {
        return queue.sync {
            return userCreated && 
                   attributionResolved && 
                   isASAUser && 
                   transactionCaptured && 
                   userId != nil && 
                   originalTransactionID != nil
        }
    }
    
    // MARK: - State Management
    
    /// Resets all state (useful for testing or error recovery)
    func reset() {
        queue.sync(flags: .barrier) {
            for key in StateKey.allCases {
                self.userDefaults.removeObject(forKey: key.rawValue)
            }
            self.userDefaults.synchronize()
            // Also reset retry failures
            self.retryManager.resetAllFailures()
        }
    }
    
    /// Updates user creation state
    func setUserCreated(userId: String) {
        queue.sync(flags: .barrier) {
            self.userDefaults.set(userId, forKey: StateKey.userId.rawValue)
            self.userDefaults.set(true, forKey: StateKey.userCreated.rawValue)
        }
    }
    
    /// Updates attribution resolution state
    func setAttributionResolved(isASAUser: Bool) {
        queue.sync(flags: .barrier) {
            self.userDefaults.set(isASAUser, forKey: StateKey.isASAUser.rawValue)
            self.userDefaults.set(true, forKey: StateKey.attributionResolved.rawValue)
        }
    }
    
    /// Updates transaction capture state
    func setTransactionCaptured(transactionId: String) {
        queue.sync(flags: .barrier) {
            self.userDefaults.set(transactionId, forKey: StateKey.originalTransactionID.rawValue)
            self.userDefaults.set(true, forKey: StateKey.transactionCaptured.rawValue)
        }
    }
    
    /// Marks the association as complete
    func setAssociationComplete() {
        queue.sync(flags: .barrier) {
            self.userDefaults.set(true, forKey: StateKey.associationComplete.rawValue)
        }
    }
    
    // MARK: - Debugging
    
    /// Returns a string representation of the current state for debugging
    func debugDescription() -> String {
        return queue.sync {
            return """
            ASA Attribution SDK State:
            - User Created: \(userCreated)
            - Attribution Resolved: \(attributionResolved)
            - Is ASA User: \(isASAUser)
            - Transaction Captured: \(transactionCaptured)
            - Association Complete: \(associationComplete)
            - User ID: \(userId ?? "nil")
            - Original Transaction ID: \(originalTransactionID ?? "nil")
            - Should Terminate: \(shouldTerminate)
            - Can Associate: \(canAssociate)
            """
        }
    }
} 