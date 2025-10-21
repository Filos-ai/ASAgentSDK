import Foundation
@testable import ASAAttributionSDK

/// Mock API Client that simulates edge function responses
/// Connected to the mock system to provide consistent ASA attribution scenarios
final class MockAPIClient: APIClientProtocol {
    
    // MARK: - Mock Configuration
    static var currentScenario: MockScenario = .asaUserWithValidToken
    static var delay: TimeInterval = 0.1 // Simulate network delay
    static var shouldFailRequests = false
    static var failureType: MockFailureType = .networkError
    
    // MARK: - Real-World Scenario Simulation
    var simulateIncompleteUserCreationResponse = false
    
    // MARK: - Thread Safety
    private let queue = DispatchQueue(label: "com.asagent.MockAPIClient.queue")
    
    // MARK: - Mock Scenarios
    enum MockScenario {
        case asaUserWithValidToken
        case nonASAUser
        case tokenUnavailable
        case tokenError
        case invalidToken
        case networkTimeout
        case customToken(String)
    }
    
    enum MockFailureType {
        case networkError
        case serverError
        case clientError
        case invalidResponse
    }
    
    // MARK: - Properties
    private let apiKey: String
    private let baseURL: String = "https://mock-api.supabase.co/functions/v1"
    
    // MARK: - Call Tracking for Infinite Loop Detection
    private var _createUserCallCount: Int = 0
    private var _resolveAttributionCallCount: Int = 0
    private var _associateUserCallCount: Int = 0
    
    // MARK: - Lifetime Request Limit (Ultimate Safety Check)
    private let maxLifetimeRequests = 100
    private let lifetimeRequestCountKey = "MockAPIClient_LifetimeRequestCount"
    private var _totalRequestCount: Int = 0
    
    var createUserCallCount: Int {
        return queue.sync { _createUserCallCount }
    }
    
    var resolveAttributionCallCount: Int {
        return queue.sync { _resolveAttributionCallCount }
    }
    
    var associateUserCallCount: Int {
        return queue.sync { _associateUserCallCount }
    }
    
    var totalRequestCount: Int {
        return queue.sync { _totalRequestCount }
    }
    
    // MARK: - Lifetime Request Limit Methods
    private func hasExceededLifetimeLimit() -> Bool {
        return queue.sync { _totalRequestCount >= maxLifetimeRequests }
    }
    
    private func incrementLifetimeRequestCount() {
        queue.sync {
            _totalRequestCount += 1
            print("🧪 Mock API Request Count: \(_totalRequestCount)/\(maxLifetimeRequests)")
            
            if _totalRequestCount >= maxLifetimeRequests {
                print("⚠️ Mock WARNING: Approaching lifetime API request limit!")
            }
        }
    }
    
    func getLifetimeRequestCount() -> Int {
        return queue.sync { _totalRequestCount }
    }
    
    func resetLifetimeRequestCount() {
        queue.sync { _totalRequestCount = 0 }
    }
    
    // MARK: - Mock Data
    private var _mockUsers: [Int: MockUser] = [:]
    private var _mockUserCounter = 1
    private var _mockTransactions: [String: Int] = [:] // transactionId -> userId
    
    // Thread-safe accessors
    private var mockUsers: [Int: MockUser] {
        get { queue.sync { _mockUsers } }
        set { queue.sync { _mockUsers = newValue } }
    }
    private var mockUserCounter: Int {
        get { queue.sync { _mockUserCounter } }
        set { queue.sync { _mockUserCounter = newValue } }
    }
    private var mockTransactions: [String: Int] {
        get { queue.sync { _mockTransactions } }
        set { queue.sync { _mockTransactions = newValue } }
    }
    
    struct MockUser {
        let id: Int
        let clientId: Int
        var transactionId: String?
        var hasAttribution: Bool
        let createdAt: Date
    }
    
    // MARK: - Initialization
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    // MARK: - Public Methods
    
    /// Creates a new user in the mock backend
    func createUser(asaAttributionToken: String?, completion: @escaping (Result<APIClient.CreateUserResponse, Error>) -> Void) {
        // Ultimate safety check: Prevent requests if lifetime limit exceeded
        if hasExceededLifetimeLimit() {
            let currentCount = getLifetimeRequestCount()
            print("🚫 Mock API request blocked: Lifetime limit exceeded (\(currentCount)/\(maxLifetimeRequests))")
            completion(.failure(MockAPIError.lifetimeLimitExceeded(currentCount, maxLifetimeRequests)))
            return
        }
        
        // Increment request count before making the request
        incrementLifetimeRequestCount()
        
        // Track call count for infinite loop detection
        queue.sync { _createUserCallCount += 1 }
        
        simulateNetworkDelay {
            if MockAPIClient.shouldFailRequests {
                completion(.failure(self.generateMockError()))
                return
            }
            
            guard self.isValidAPIKey(self.apiKey) else {
                completion(.failure(MockAPIError.invalidAPIKey))
                return
            }
            let response = self.handleCreateUser(asaAttributionToken: asaAttributionToken)
            completion(.success(response))
        }
    }
    
    /// Resolves ASA attribution for an existing user
    func resolveAttribution(userId: Int, asaAttributionToken: String, completion: @escaping (Result<APIClient.ResolveAttributionResponse, Error>) -> Void) {
        // Ultimate safety check: Prevent requests if lifetime limit exceeded
        if hasExceededLifetimeLimit() {
            let currentCount = getLifetimeRequestCount()
            print("🚫 Mock API request blocked: Lifetime limit exceeded (\(currentCount)/\(maxLifetimeRequests))")
            completion(.failure(MockAPIError.lifetimeLimitExceeded(currentCount, maxLifetimeRequests)))
            return
        }
        
        // Increment request count before making the request
        incrementLifetimeRequestCount()
        
        // Track call count for infinite loop detection
        queue.sync { _resolveAttributionCallCount += 1 }
        
        simulateNetworkDelay {
            if MockAPIClient.shouldFailRequests {
                completion(.failure(self.generateMockError()))
                return
            }
            
            let response = self.handleResolveAttribution(userId: userId, asaAttributionToken: asaAttributionToken)
            completion(response)
        }
    }
    
    /// Associates a transaction ID with a user
    func associateUser(userId: Int, transactionId: String, completion: @escaping (Result<APIClient.AssociateUserResponse, Error>) -> Void) {
        // Ultimate safety check: Prevent requests if lifetime limit exceeded
        if hasExceededLifetimeLimit() {
            let currentCount = getLifetimeRequestCount()
            print("🚫 Mock API request blocked: Lifetime limit exceeded (\(currentCount)/\(maxLifetimeRequests))")
            completion(.failure(MockAPIError.lifetimeLimitExceeded(currentCount, maxLifetimeRequests)))
            return
        }
        
        // Increment request count before making the request
        incrementLifetimeRequestCount()
        
        // Track call count for infinite loop detection
        queue.sync { _associateUserCallCount += 1 }
        
        simulateNetworkDelay {
            if MockAPIClient.shouldFailRequests {
                completion(.failure(self.generateMockError()))
                return
            }
            
            let response = self.handleAssociateUser(userId: userId, transactionId: transactionId)
            completion(response)
        }
    }
    
    // MARK: - Mock Edge Function Handlers
    
    private func handleCreateUser(asaAttributionToken: String?) -> APIClient.CreateUserResponse {
        // Simulate API key validation
        guard isValidAPIKey(apiKey) else {
            // Throwing here will be caught by the public createUser method and returned as a failure
            // But since this is a private method, we need to handle it at the call site
            // So, let's throw an error instead of returning a response
            // We'll change the signature to throw and update the call site
            fatalError("handleCreateUser should not be called with an invalid API key. Use the public createUser method to handle errors.")
        }
        
        // Handle ASA attribution token if provided
        if let token = asaAttributionToken {
            let attributionResult = processASAToken(token)
            
            switch attributionResult {
            case .nonASAUser:
                // Don't create user for non-ASA cases (business requirement)
                // No userId should be assigned for non-ASA users
                return APIClient.CreateUserResponse(
                    userId: nil,
                    didUserComeFromAsa: false,
                    asaAttributionResolved: true,
                    userCreated: false
                )
                
            case .asaUserValid:
                // Create user with attribution - generate userId only when needed
                var userId: Int = 0
                queue.sync {
                    userId = _mockUserCounter
                    _mockUserCounter += 1
                }
                
                let user = MockUser(
                    id: userId,
                    clientId: 1,
                    transactionId: nil,
                    hasAttribution: true,
                    createdAt: Date()
                )
                queue.sync { _mockUsers[userId] = user }
                
                // Simulate real-world incomplete response if flag is set
                if simulateIncompleteUserCreationResponse {
                    // This simulates the real backend issue: attribution is resolved but userCreated flag is not set properly
                    return APIClient.CreateUserResponse(
                        userId: userId,
                        didUserComeFromAsa: true,
                        asaAttributionResolved: true,
                        userCreated: nil  // This is the problem causing infinite loops!
                    )
                } else {
                    return APIClient.CreateUserResponse(
                        userId: userId,
                        didUserComeFromAsa: true,
                        asaAttributionResolved: true,
                        userCreated: true
                    )
                }
                
            case .tokenInvalid:
                // Create user without attribution - generate userId only when needed
                var userId: Int = 0
                queue.sync {
                    userId = _mockUserCounter
                    _mockUserCounter += 1
                }
                
                let user = MockUser(
                    id: userId,
                    clientId: 1,
                    transactionId: nil,
                    hasAttribution: false,
                    createdAt: Date()
                )
                queue.sync { _mockUsers[userId] = user }
                
                return APIClient.CreateUserResponse(
                    userId: userId,
                    didUserComeFromAsa: nil,
                    asaAttributionResolved: false,
                    userCreated: true
                )
                
            case .tokenUnresolvable:
                // Create user without attribution - generate userId only when needed
                var userId: Int = 0
                queue.sync {
                    userId = _mockUserCounter
                    _mockUserCounter += 1
                }
                
                let user = MockUser(
                    id: userId,
                    clientId: 1,
                    transactionId: nil,
                    hasAttribution: false,
                    createdAt: Date()
                )
                queue.sync { _mockUsers[userId] = user }
                
                return APIClient.CreateUserResponse(
                    userId: userId,
                    didUserComeFromAsa: nil,
                    asaAttributionResolved: nil,
                    userCreated: true
                )
            }
        } else {
            // No ASA token provided - create user without attribution - generate userId only when needed
            var userId: Int = 0
            queue.sync {
                userId = _mockUserCounter
                _mockUserCounter += 1
            }
            
            let user = MockUser(
                id: userId,
                clientId: 1,
                transactionId: nil,
                hasAttribution: false,
                createdAt: Date()
            )
            queue.sync { _mockUsers[userId] = user }
            
            return APIClient.CreateUserResponse(
                userId: userId,
                didUserComeFromAsa: nil,
                asaAttributionResolved: false,
                userCreated: true
            )
        }
    }
    
    private func handleResolveAttribution(userId: Int, asaAttributionToken: String) -> Result<APIClient.ResolveAttributionResponse, Error> {
        // Simulate API key validation
        guard isValidAPIKey(apiKey) else {
            return .failure(MockAPIError.invalidAPIKey)
        }
        
        // Check if user exists
        let user: MockUser? = queue.sync { _mockUsers[userId] }
        guard let user = user else {
            return .failure(MockAPIError.userNotFound)
        }
        
        // Check if user already has attribution
        if user.hasAttribution {
            return .success(APIClient.ResolveAttributionResponse(
                didUserComeFromAsa: false,
                asaAttributionResolved: false
            ))
        }
        
        // Process ASA token
        let attributionResult = processASAToken(asaAttributionToken)
        
        switch attributionResult {
        case .nonASAUser:
            // No user to delete since non-ASA users are never created
            return .success(APIClient.ResolveAttributionResponse(
                didUserComeFromAsa: false,
                asaAttributionResolved: true
            ))
            
        case .asaUserValid:
            // Update user with attribution
            queue.sync {
                if var user = _mockUsers[userId] {
                    user.hasAttribution = true
                    _mockUsers[userId] = user
                }
            }
            return .success(APIClient.ResolveAttributionResponse(
                didUserComeFromAsa: true,
                asaAttributionResolved: true
            ))
            
        case .tokenInvalid:
            return .success(APIClient.ResolveAttributionResponse(
                didUserComeFromAsa: nil,
                asaAttributionResolved: false
            ))
            
        case .tokenUnresolvable:
            return .success(APIClient.ResolveAttributionResponse(
                didUserComeFromAsa: nil,
                asaAttributionResolved: nil
            ))
        }
    }
    
    private func handleAssociateUser(userId: Int, transactionId: String) -> Result<APIClient.AssociateUserResponse, Error> {
        // Simulate API key validation
        guard isValidAPIKey(apiKey) else {
            return .failure(MockAPIError.invalidAPIKey)
        }
        
        // Check if user exists
        var user: MockUser? = nil
        queue.sync { user = _mockUsers[userId] }
        guard var userUnwrapped = user else {
            return .failure(MockAPIError.userNotFound)
        }
        
        // Check if user already has a transaction
        if userUnwrapped.transactionId != nil {
            return .failure(MockAPIError.userAlreadyHasTransaction)
        }
        
        // Associate transaction
        userUnwrapped.transactionId = transactionId
        queue.sync { _mockUsers[userId] = userUnwrapped; _mockTransactions[transactionId] = userId }
        
        return .success(APIClient.AssociateUserResponse(
            success: true,
            user: APIClient.AssociateUserResponse.User(
                id: userId,
                transaction_id: transactionId
            )
        ))
    }
    
    // MARK: - ASA Token Processing
    
    private enum ASATokenResult {
        case asaUserValid
        case nonASAUser
        case tokenInvalid
        case tokenUnresolvable
    }
    
    private func processASAToken(_ token: String) -> ASATokenResult {
        switch MockAPIClient.currentScenario {
        case .asaUserWithValidToken:
            return .asaUserValid
            
        case .nonASAUser:
            return .nonASAUser
            
        case .tokenUnavailable:
            return .tokenUnresolvable
            
        case .tokenError:
            return .tokenUnresolvable
            
        case .invalidToken:
            return .tokenInvalid
            
        case .networkTimeout:
            return .tokenUnresolvable
            
        case .customToken(let customToken):
            if customToken.contains("non_asa") {
                return .nonASAUser
            } else if customToken.contains("invalid") {
                return .tokenInvalid
            } else {
                return .asaUserValid
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func isValidAPIKey(_ key: String) -> Bool {
        return key.hasPrefix("sk_") && key.count > 10
    }
    
    private func simulateNetworkDelay(_ completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + MockAPIClient.delay) {
            completion()
        }
    }
    
    private func generateMockError() -> Error {
        switch MockAPIClient.failureType {
        case .networkError:
            return MockAPIError.networkError
        case .serverError:
            return MockAPIError.serverError
        case .clientError:
            return MockAPIError.clientError
        case .invalidResponse:
            return MockAPIError.invalidResponse
        }
    }
    
    // MARK: - Reset Methods
    
    func resetMockData() {
        queue.sync {
            _mockUsers.removeAll()
            _mockTransactions.removeAll()
            _mockUserCounter = 1
            // Reset call counters for infinite loop detection
            _createUserCallCount = 0
            _resolveAttributionCallCount = 0
            _associateUserCallCount = 0
        }
    }
    
    static func resetConfiguration() {
        currentScenario = .asaUserWithValidToken
        delay = 0.1
        shouldFailRequests = false
        failureType = .networkError
    }
}

// MARK: - Mock API Errors

enum MockAPIError: Error, LocalizedError {
    case invalidAPIKey
    case userNotFound
    case userAlreadyHasTransaction
    case networkError
    case serverError
    case clientError
    case invalidResponse
    case lifetimeLimitExceeded(Int, Int) // current count, max limit
    
    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid API key"
        case .userNotFound:
            return "User not found"
        case .userAlreadyHasTransaction:
            return "User already has transaction"
        case .networkError:
            return "Network error"
        case .serverError:
            return "Server error"
        case .clientError:
            return "Client error"
        case .invalidResponse:
            return "Invalid response"
        case .lifetimeLimitExceeded(let current, let max):
            return "Mock lifetime API request limit exceeded (\(current)/\(max)). Please contact support if this is unexpected."
        }
    }
}

// MARK: - Factory Methods

extension MockAPIClient {
    static func createASAUserScenario(apiKey: String = "sk_test_key") -> MockAPIClient {
        MockAPIClient.currentScenario = .asaUserWithValidToken
        return MockAPIClient(apiKey: apiKey)
    }
    
    static func createNonASAUserScenario(apiKey: String = "sk_test_key") -> MockAPIClient {
        MockAPIClient.currentScenario = .nonASAUser
        return MockAPIClient(apiKey: apiKey)
    }
    
    static func createTokenUnavailableScenario(apiKey: String = "sk_test_key") -> MockAPIClient {
        MockAPIClient.currentScenario = .tokenUnavailable
        return MockAPIClient(apiKey: apiKey)
    }
    
    static func createInvalidTokenScenario(apiKey: String = "sk_test_key") -> MockAPIClient {
        MockAPIClient.currentScenario = .invalidToken
        return MockAPIClient(apiKey: apiKey)
    }
    
    static func createNetworkTimeoutScenario(apiKey: String = "sk_test_key") -> MockAPIClient {
        MockAPIClient.currentScenario = .networkTimeout
        return MockAPIClient(apiKey: apiKey)
    }
} 