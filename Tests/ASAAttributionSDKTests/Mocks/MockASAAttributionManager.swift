import Foundation
@testable import ASAAttributionSDK

/// Mock ASA Attribution Manager for testing different attribution scenarios
/// This allows us to test various flows without relying on real ASA tokens
final class MockASAAttributionManager: ASAAttributionProviding {
    
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
    
    // MARK: - Properties
    private let scenario: MockScenario
    private let delay: TimeInterval
    
    // MARK: - Mock ASA Tokens
    private static let validASAToken = "0Mifil0N48iir4nXxRRKXZudvO7JpeAzHLCPF6SeVFAhEpHW2EOXsgKGdgaTxrRDHOyDFVoCST/NjTrZF+/qNctTSSxdX9MzcwAAAVADAAABFwAAAIBIUp4vWgAH0plCL1YjwMqxD4V4II64ABwRLdvoDdcMqyroMYszFaD/+wIn54EaaoFXRWdgVNYbn/r52TtlI5y9T5MbRj4IT0fRicTEUwSo4T7qmFkeoH4LhaVcnXWQ8sTJGA7pKEddQtD0NWBFZtCJatZGzX7O+EIKo5XsbfgBwQAAABH0WlS6HAhMZHh7WcrdFHvLUwAAAJ8BgC6fAPX2cJk19xkWL9TBj9lp+KkAAACGBwiZQ1BE1X/QJeX+c8+EWhH3aHFC2XLSEHTA8RZcx+ErRjeReWykOxec7G9RKI1McjwAW36bP+hCBQiIBjjk4EofUywbzXgbS1FXFzeM+lqZCy5LIupGNLR9JD3wNR35qzl1M5gOE6yyGCbfQb3/QeUKSx1WEudJJWRt0CvDcUpp/XpVnVgAAAAAAAAAAAAAAAAAAAABBEocAAA="
    
    private static let invalidASAToken = "invalid_token_format"
    
    // MARK: - Initialization
    init(scenario: MockScenario, delay: TimeInterval = 0.5) {
        self.scenario = scenario
        self.delay = delay
    }
    
    // MARK: - ASAAttributionProviding Implementation
    func fetchAttribution(completion: @escaping (ASAAttributionManager.AttributionResult) -> Void) {
        // Simulate network delay
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + delay) {
            let result: ASAAttributionManager.AttributionResult
            
            switch self.scenario {
            case .asaUserWithValidToken:
                result = .adServices(token: Self.validASAToken)
                
            case .nonASAUser:
                // This will resolve to attribution = false
                result = .adServices(token: self.generateNonASAToken())
                
            case .tokenUnavailable:
                result = .unavailable(reason: "AdServices unavailable for testing")
                
            case .tokenError:
                result = .unavailable(reason: "AdServices error: Mock error for testing")
                
            case .invalidToken:
                result = .adServices(token: Self.invalidASAToken)
                
            case .networkTimeout:
                result = .unavailable(reason: "Network timeout during testing")
                
            case .customToken(let token):
                result = .adServices(token: token)
            }
            
            completion(result)
        }
    }
    
    // MARK: - Helper Methods
    
    /// Generates a token that will resolve to attribution = false
    private func generateNonASAToken() -> String {
        // This is a mock token that when sent to Apple's API will return attribution = false
        // In real testing, you would need to generate or obtain such a token
        return "mock_non_asa_token_that_resolves_to_false"
    }
    
    // MARK: - Factory Methods
    
    /// Create a mock for ASA user with valid token
    static func asaUser(delay: TimeInterval = 0.5) -> MockASAAttributionManager {
        return MockASAAttributionManager(scenario: .asaUserWithValidToken, delay: delay)
    }
    
    /// Create a mock for non-ASA user
    static func nonASAUser(delay: TimeInterval = 0.5) -> MockASAAttributionManager {
        return MockASAAttributionManager(scenario: .nonASAUser, delay: delay)
    }
    
    /// Create a mock for token unavailable scenario
    static func tokenUnavailable(delay: TimeInterval = 0.5) -> MockASAAttributionManager {
        return MockASAAttributionManager(scenario: .tokenUnavailable, delay: delay)
    }
    
    /// Create a mock for token error scenario
    static func tokenError(delay: TimeInterval = 0.5) -> MockASAAttributionManager {
        return MockASAAttributionManager(scenario: .tokenError, delay: delay)
    }
    
    /// Create a mock for invalid token scenario
    static func invalidToken(delay: TimeInterval = 0.5) -> MockASAAttributionManager {
        return MockASAAttributionManager(scenario: .invalidToken, delay: delay)
    }
    
    /// Create a mock for network timeout scenario
    static func networkTimeout(delay: TimeInterval = 0.5) -> MockASAAttributionManager {
        return MockASAAttributionManager(scenario: .networkTimeout, delay: delay)
    }
    
    /// Create a mock with custom token
    static func customToken(_ token: String, delay: TimeInterval = 0.5) -> MockASAAttributionManager {
        return MockASAAttributionManager(scenario: .customToken(token), delay: delay)
    }
} 