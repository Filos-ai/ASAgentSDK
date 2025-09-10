import Foundation
import os.log

/// Main ASA Attribution SDK class
public class ASAAttributionSDK {
    
    // MARK: - Properties
    public static let shared = ASAAttributionSDK()
    internal let stateManager = StateManager()
    private var hasConfigured = false
    private var apiClient: (any APIClientProtocol)?
    
    // Infinite Loop Prevention
    private var isExecutingFlow = false
    
    // Dependency injection for testing
    internal var dependencies: SDKDependencies?
    
    // MARK: - Components
    private let backgroundQueue = DispatchQueue(label: "com.asaattribution.sdk.background", qos: .background)
    
    // MARK: - Environment Detection
    private static var isProductionEnvironment: Bool {
        #if DEBUG
        return false
        #else
        // Check if we're running in a production build
        // This will be true for App Store builds and release builds
        return true
        #endif
    }
    
    // MARK: - Install Type Detection
    
    /// Determines if this is a first install vs an app update
    /// Uses persisted state if available, otherwise determines from Documents directory creation date
    /// Once determined, the result is persisted for consistency across app launches
    /// - Returns: True if this appears to be a first install, false if it's an update
    private func isFirstInstallVsUpdate() -> Bool {
        // Check if we've already determined and persisted the install type
        if stateManager.installTypeResolved {
            let installType = stateManager.isFirstInstall ? "first install" : "app update"
            logInfo("Install type already determined from persistent storage: \(installType)")
            return stateManager.isFirstInstall
        }
        
        // First time determining install type - use Documents directory creation date
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last,
              let attributes = try? FileManager.default.attributesOfItem(atPath: documentsURL.path),
              let creationDate = attributes[.creationDate] as? Date else {
            logInfo("Could not determine install type from Documents directory - defaulting to treating as fresh install")
            let isFirstInstall = true
            stateManager.setInstallType(isFirstInstall: isFirstInstall)
            return isFirstInstall
        }
        
        // If Documents directory was created recently (e.g., within last 24 hours), 
        // it's likely a fresh install
        let timeInterval = Date().timeIntervalSince(creationDate)
        let oneDayInSeconds: TimeInterval = 24 * 60 * 60
        
        let isFirstInstall = timeInterval < oneDayInSeconds
        logInfo("Install type determined from Documents directory created \(String(format: "%.1f", timeInterval / 3600)) hours ago: \(isFirstInstall ? "first install" : "app update")")
        
        // Persist the determination for future app launches
        stateManager.setInstallType(isFirstInstall: isFirstInstall)
        
        return isFirstInstall
    }
    
    /// Returns true if the SDK is running in a production environment
    /// - Note: Logging is disabled in production environments for performance and privacy
    public static var isProduction: Bool {
        return isProductionEnvironment
    }
    
    // MARK: - Initialization
    private init() {}
    
    // MARK: - Public Configuration
    
    /// Configures the SDK with the required API key
    /// - Parameter apiKey: The API key for backend authentication
    /// - Note: This method returns immediately and runs all operations in the background
    public func configure(apiKey: String) {
        guard !hasConfigured else {
            logInfo("SDK already configured")
            return
        }
        
        // Set up dependencies if not already set (for testing)
        if dependencies == nil {
            dependencies = .production(apiKey: apiKey)
        }
        
        self.apiClient = dependencies?.apiClient
        self.hasConfigured = true
        
        
        // Start the configuration flow in background thread to avoid blocking app launch
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.executeConfigurationFlow()
        }
    }
    
    // MARK: - Configuration Flow
    
    /// Executes the main configuration flow according to requirements
    private func executeConfigurationFlow() {
        backgroundQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.logInfo("Starting ASA Attribution SDK configuration flow")
            self.logInfo(self.stateManager.debugDescription())
            
            // Check if this is a first install vs an app update
            // Only proceed with SDK operations for first installs
            if !self.isFirstInstallVsUpdate() {
                self.logInfo("SDK detected app update (not first install) - skipping attribution flow to avoid duplicate backend entries")
                return
            }
            
            self.logInfo("SDK detected first install - proceeding with attribution flow")
            
            // Start transaction monitoring immediately to avoid missing any transactions
            if !self.stateManager.transactionCaptured {
                self.startTransactionMonitoring()
            }
            
            // Check termination conditions first
            if self.stateManager.shouldTerminate {
                self.logInfo("SDK terminating - flow already complete or user is non-ASA")
                return
            }
            
            // Execute the state machine flow
            self.executeNextStep()
        }
    }
    
    /// Executes the next step in the configuration flow
    /// This method runs operations in parallel rather than sequentially to avoid blocking
    private func executeNextStep() {
        backgroundQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Prevent concurrent execution to avoid infinite loops
            guard !self.isExecutingFlow else {
                self.logInfo("executeNextStep already in progress, skipping concurrent call")
                return
            }
            
            self.isExecutingFlow = true
            defer { self.isExecutingFlow = false }
            
            // Log current state for debugging
            self.logInfo("executeNextStep() - Current state: userCreated=\(self.stateManager.userCreated), attributionResolved=\(self.stateManager.attributionResolved), isASAUser=\(self.stateManager.isASAUser)")
            
            // Step 1: Check if user exists
            if !self.stateManager.userCreated {
                // Check if we can retry user creation
                if !self.stateManager.retryManager.canRetry(.createUser) {
                    let timeUntilRetry = self.stateManager.retryManager.timeUntilNextRetry(.createUser)
                    self.logInfo("User creation in backoff - next retry in \(String(format: "%.1f", timeUntilRetry)) seconds")
                    return
                }
                
                self.logInfo("No user exists - creating new user")
                self.createNewUser()
                return
            }
            
            // Step 2: Check if we have a confirmed non-ASA user
            if self.stateManager.attributionResolved && !self.stateManager.isASAUser {
                self.logInfo("User is confirmed non-ASA user - terminating SDK operations")
                return
            }
            
            // Step 3: Check if flow is complete
            if self.stateManager.associationComplete {
                self.logInfo("ASA Attribution flow complete - terminating SDK operations")
                return
            }
            
            // Step 4: Start parallel operations
            var shouldContinue = false
            
            // Try to resolve attribution if not resolved yet
            if !self.stateManager.attributionResolved {
                // Check if we can retry attribution resolution
                if self.stateManager.retryManager.canRetry(.resolveAttribution) {
                    self.resolveASAAttribution()
                    shouldContinue = true
                } else {
                    let timeUntilRetry = self.stateManager.retryManager.timeUntilNextRetry(.resolveAttribution)
                    self.logInfo("Attribution resolution in backoff - next retry in \(String(format: "%.1f", timeUntilRetry)) seconds")
                }
            }
            
            // Try to associate if we have everything needed
            if self.stateManager.canAssociate && !self.stateManager.associationComplete {
                // Check if we can retry association
                if self.stateManager.retryManager.canRetry(.associateUser) {
                    self.associateTransaction()
                    shouldContinue = true
                } else {
                    let timeUntilRetry = self.stateManager.retryManager.timeUntilNextRetry(.associateUser)
                    self.logInfo("Transaction association in backoff - next retry in \(String(format: "%.1f", timeUntilRetry)) seconds")
                }
            }
            
            if !shouldContinue {
                self.logInfo("Configuration flow complete - waiting for transaction or next launch")
            }
        }
    }
    
    // MARK: - Flow Steps
    
    /// Step 2: Creates a new user in the backend
    private func createNewUser() {
        backgroundQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.logInfo("Creating new user...")
            
            // Fetch ASA attribution token first
            dependencies?.attributionProvider.fetchAttribution { [weak self] result in
                guard let self = self, let apiClient = self.apiClient else { return }
                
                // Ensure we handle the response in background
                self.backgroundQueue.async {
                    var asaToken: String?
                    switch result {
                    case .adServices(let token):
                        asaToken = token
                        self.logInfo("ASA attribution token obtained")
                    case .unavailable(let reason):
                        self.logInfo("ASA attribution token unavailable: \(reason)")
                        asaToken = nil
                    }
                    
                    // Create user with or without ASA token
                    apiClient.createUser(asaAttributionToken: asaToken) { [weak self] result in
                        guard let self = self else { return }
                        
                        // Ensure response handling is in background
                        self.backgroundQueue.async {
                            switch result {
                            case .success(let response):
                                self.stateManager.retryManager.recordSuccess(.createUser)
                                self.handleCreateUserResponse(response)
                            case .failure(let error):
                                self.stateManager.retryManager.recordFailure(.createUser)
                                self.logError("Failed to create user: \(error.localizedDescription)")
                                // Don't retry immediately - will be handled by backoff on next executeNextStep
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// Resolves ASA attribution for an existing user (runs in parallel with transaction monitoring)
    private func resolveASAAttribution() {
        backgroundQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.logInfo("Resolving ASA attribution...")
            
            guard let apiClient = self.apiClient,
                  let userIdString = self.stateManager.userId,
                  let userId = Int(userIdString) else {
                self.logError("Cannot resolve attribution - missing API client or user ID")
                return
            }
            
            // Fetch ASA attribution token
            dependencies?.attributionProvider.fetchAttribution { [weak self] result in
                guard let self = self else { return }
                
                // Ensure we handle the response in background
                self.backgroundQueue.async {
                    switch result {
                    case .adServices(let token):
                        // Resolve attribution with the token
                        apiClient.resolveAttribution(userId: userId, asaAttributionToken: token) { [weak self] result in
                            guard let self = self else { return }
                            
                            // Ensure response handling is in background
                            self.backgroundQueue.async {
                                switch result {
                                case .success(let response):
                                    self.stateManager.retryManager.recordSuccess(.resolveAttribution)
                                    self.handleResolveAttributionResponse(response)
                                case .failure(let error):
                                    self.stateManager.retryManager.recordFailure(.resolveAttribution)
                                    self.logError("Failed to resolve attribution: \(error.localizedDescription)")
                                    // Continue with other operations even if attribution fails, but respect backoff
                                    self.executeNextStep()
                                }
                            }
                        }
                        
                    case .unavailable(let reason):
                        self.logInfo("ASA attribution token unavailable: \(reason)")
                        // Can't resolve without token, will try again next launch
                        // Continue with other operations (like transaction monitoring)
                        self.executeNextStep()
                    }
                }
            }
        }
    }
    
    /// Starts monitoring transactions (called immediately when SDK is configured)
    private func startTransactionMonitoring() {
        backgroundQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.logInfo("Starting transaction monitoring...")
            
            dependencies?.transactionMonitor.start { [weak self] transactionId in
                guard let self = self else { return }
                
                // Ensure transaction handling is in background
                self.backgroundQueue.async {
                    self.logInfo("Transaction captured: \(transactionId)")
                    self.handleTransactionCapture(transactionId: transactionId)
                }
            }
        }
    }
    
    /// Handles transaction capture - waits for user creation if needed
    private func handleTransactionCapture(transactionId: String) {
        // Store the transaction immediately
        self.stateManager.setTransactionCaptured(transactionId: transactionId)
        
        // Check if we can associate immediately or need to wait
        if self.stateManager.userCreated {
            self.logInfo("Transaction captured after user creation - proceeding with flow")
            self.executeNextStep()
        } else {
            self.logInfo("Transaction captured before user creation - will associate when user is created")
            // Transaction is stored and waiting. When user is created, handleCreateUserResponse 
            // will call executeNextStep() which will detect both userCreated=true and 
            // transactionCaptured=true, then proceed to association
        }
    }
    
    /// Step 6: Associates transaction with user
    private func associateTransaction() {
        backgroundQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.logInfo("Associating transaction with user...")
            
            guard let apiClient = self.apiClient,
                  let userIdString = self.stateManager.userId,
                  let userId = Int(userIdString),
                  let transactionId = self.stateManager.originalTransactionID else {
                self.logError("Cannot associate transaction - missing required data")
                return
            }
            
            apiClient.associateUser(userId: userId, transactionId: transactionId) { [weak self] result in
                guard let self = self else { return }
                
                // Ensure response handling is in background
                self.backgroundQueue.async {
                    switch result {
                    case .success(let response):
                        if response.success == true {
                            self.stateManager.retryManager.recordSuccess(.associateUser)
                            self.logInfo("Transaction association successful")
                            self.stateManager.setAssociationComplete()
                            self.logInfo("ASA Attribution flow complete")
                        } else {
                            self.stateManager.retryManager.recordFailure(.associateUser)
                            self.logError("Transaction association failed")
                        }
                        
                    case .failure(let error):
                        self.stateManager.retryManager.recordFailure(.associateUser)
                        self.logError("Failed to associate transaction: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    // MARK: - Response Handlers
    
    private func handleCreateUserResponse(_ response: APIClient.CreateUserResponse) {
        logInfo("Create user response received")
        
        // Handle incomplete backend responses where userCreated flag is not set properly
        // If we have a userId and attribution is resolved for an ASA user, treat it as user created
        var shouldMarkUserAsCreated = false
        
        if let userId = response.userId {
            if response.userCreated == true {
                // Explicit user creation confirmation
                shouldMarkUserAsCreated = true
                logInfo("User explicitly created with ID: \(userId)")
            } else if response.userCreated == nil || response.userCreated == false {
                // Handle incomplete backend response: if attribution is resolved for ASA user, assume user was created
                if response.asaAttributionResolved == true && response.didUserComeFromAsa == true {
                    shouldMarkUserAsCreated = true
                    logInfo("User implicitly created with ID: \(userId) (backend response incomplete but ASA user confirmed)")
                } else if response.didUserComeFromAsa == false {
                    logInfo("User was not created (non-ASA user)")
                } else {
                    logInfo("User creation status unclear from backend response")
                }
            }
        }
        
        // Set user as created if we determined it should be
        if shouldMarkUserAsCreated {
            if let userId = response.userId {
                stateManager.setUserCreated(userId: String(userId))
                logInfo("User marked as created with ID: \(userId)")
            }
        }
        
        // Update attribution resolution state if provided
        if let attributionResolved = response.asaAttributionResolved {
            if attributionResolved {
                let isASAUser = response.didUserComeFromAsa != false
                stateManager.setAttributionResolved(isASAUser: isASAUser)
                logInfo("Attribution resolved during user creation: \(isASAUser ? "ASA user" : "non-ASA user")")
            }
        }
        
        // Check if user is confirmed non-ASA
        if response.didUserComeFromAsa == false {
            logInfo("User confirmed as non-ASA during creation - terminating SDK operations")
            stateManager.setAttributionResolved(isASAUser: false)
            return
        }
        
        // Add small delay to ensure state persistence is complete before proceeding
        // This prevents infinite loops on real devices where UserDefaults might have persistence delays
        backgroundQueue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.logInfo("Proceeding to next step after state persistence delay")
            self?.executeNextStep()
        }
    }
    
    private func handleResolveAttributionResponse(_ response: APIClient.ResolveAttributionResponse) {
        logInfo("Resolve attribution response received")
        
        // Check if attribution was resolved
        if let attributionResolved = response.asaAttributionResolved {
            if attributionResolved {
                let isASAUser = response.didUserComeFromAsa == true
                stateManager.setAttributionResolved(isASAUser: isASAUser)
                
                if isASAUser {
                    logInfo("User confirmed as ASA user")
                    // Continue with the flow - we might be able to associate now
                    executeNextStep()
                } else {
                    logInfo("User confirmed as non-ASA user - terminating SDK operations")
                    return
                }
            } else {
                logInfo("Attribution resolution failed - will retry next launch")
                // Don't return - we might still want to capture transaction data
            }
        } else {
            logInfo("Attribution resolution pending - will retry next launch")
            // Don't return - we might still want to capture transaction data
        }
        
        // Even if attribution failed, continue with other operations
        executeNextStep()
    }
    
    // MARK: - Public Utility Methods
    
    /// Returns whether this appears to be a first install vs an app update
    /// This method is exposed publicly so developers can use it for their own logic if needed
    /// - Returns: True if this appears to be a first install, false if it's an update
    public func isFirstInstall() -> Bool {
        return isFirstInstallVsUpdate()
    }
    
    /// Returns the current state for debugging purposes
    public func getDebugState() -> String {
        return backgroundQueue.sync {
            let stateDescription = stateManager.debugDescription()
            let retryStats = """
            
            Retry Statistics:
            - \(stateManager.retryManager.getFailureStats(.createUser))
            - \(stateManager.retryManager.getFailureStats(.resolveAttribution))
            - \(stateManager.retryManager.getFailureStats(.associateUser))
            """
            return stateDescription + retryStats
        }
    }
    
    /// Resets all SDK state (useful for testing)
    public func resetState() {
        backgroundQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.stateManager.reset()
            self.hasConfigured = false // Reset configuration flag for testing
            self.apiClient = nil // Clear API client reference
            self.dependencies = nil // Clear dependencies
            self.isExecutingFlow = false // Reset execution flag
            self.logInfo("SDK state reset")
        }
    }
    
    /// Resets all SDK state synchronously (for testing)
    public func resetStateSync() {
        backgroundQueue.sync {
            self.stateManager.reset()
            self.hasConfigured = false // Reset configuration flag for testing
            self.apiClient = nil // Clear API client reference
            self.dependencies = nil // Clear dependencies
            self.isExecutingFlow = false // Reset execution flag
            self.logInfo("SDK state reset (sync)")
        }
    }
    
    /// Get retry manager for testing purposes
    public func getRetryManager() -> RetryManager {
        return stateManager.retryManager
    }
    
    // MARK: - Logging
    
    @available(iOS 14.0, macOS 11.0, *)
    private var logger: Logger {
        Logger(subsystem: "com.asaattribution.sdk", category: "ASAAttributionSDK")
    }
    
    private let osLog = OSLog(subsystem: "com.asaattribution.sdk", category: "ASAAttributionSDK")
    
    internal func logInfo(_ message: String) {
        // Only log in non-production environments
        guard !Self.isProductionEnvironment else { return }
        
        if #available(iOS 14.0, macOS 11.0, *) {
            logger.info("\(message, privacy: .public)")
        } else {
            os_log("%{public}@", log: osLog, type: .info, message)
        }
    }
    
    private func logError(_ message: String) {
        // Only log in non-production environments
        guard !Self.isProductionEnvironment else { return }
        
        if #available(iOS 14.0, macOS 11.0, *) {
            logger.error("\(message, privacy: .public)")
        } else {
            os_log("%{public}@", log: osLog, type: .error, message)
        }
    }
}
