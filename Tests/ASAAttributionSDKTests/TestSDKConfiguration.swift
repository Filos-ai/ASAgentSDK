import Foundation
@testable import ASAAttributionSDK

// MARK: - Test SDK Configuration

/// Test-only SDK configuration that allows dependency injection
/// This class is only available in tests and allows mocking of dependencies
class TestSDKConfiguration {
    
    public private(set) var dependencies: SDKDependencies
    private var mockAttributionProvider: MockASAAttributionManager
    private var mockTransactionMonitor: MockTransactionMonitor
    private var mockAPIClient: MockAPIClient
    private var currentScenario: MockASAAttributionManager.MockScenario
    private var currentTransactionId: String
    
    init(
        mockAPIClient: MockAPIClient? = nil,
        scenario: MockASAAttributionManager.MockScenario = .asaUserWithValidToken
    ) {
        self.currentScenario = scenario
        self.currentTransactionId = "test_txn_123"
        self.mockAttributionProvider = MockASAAttributionManager(scenario: scenario)
        self.mockTransactionMonitor = MockTransactionMonitor(transactionID: self.currentTransactionId)
        self.mockAPIClient = mockAPIClient ?? MockAPIClient(apiKey: "sk_test_key")
        
        self.dependencies = SDKDependencies(
            attributionProvider: self.mockAttributionProvider,
            transactionMonitor: self.mockTransactionMonitor,
            apiClient: self.mockAPIClient
        )
        
        // Set the scenario for API client too
        self.setAPIClientScenario(scenario)
    }
    
    /// Update the scenario for the attribution provider and recreate dependencies
    func setScenario(_ scenario: MockASAAttributionManager.MockScenario) {
        self.currentScenario = scenario
        
        // Recreate the mock attribution provider with new scenario
        self.mockAttributionProvider = MockASAAttributionManager(scenario: scenario)
        
        // Update API client scenario
        self.setAPIClientScenario(scenario)
        
        // Recreate dependencies with updated mocks
        self.dependencies = SDKDependencies(
            attributionProvider: self.mockAttributionProvider,
            transactionMonitor: self.mockTransactionMonitor,
            apiClient: self.mockAPIClient
        )
    }
    
    /// Set mock transaction for transaction monitor and recreate dependencies
    func setMockTransaction(transactionId: String?) {
        let transactionIdToUse = transactionId ?? "test_txn_123"
        self.currentTransactionId = transactionIdToUse
        
        // Recreate the mock transaction monitor with new transaction ID
        self.mockTransactionMonitor = MockTransactionMonitor(transactionID: transactionIdToUse)
        
        // Recreate dependencies with updated mocks
        self.dependencies = SDKDependencies(
            attributionProvider: self.mockAttributionProvider,
            transactionMonitor: self.mockTransactionMonitor,
            apiClient: self.mockAPIClient
        )
    }
    
    /// Update the API client and recreate dependencies
    func updateAPIClient(_ apiClient: MockAPIClient) {
        self.mockAPIClient = apiClient
        
        // Recreate dependencies with updated API client
        self.dependencies = SDKDependencies(
            attributionProvider: self.mockAttributionProvider,
            transactionMonitor: self.mockTransactionMonitor,
            apiClient: self.mockAPIClient
        )
    }
    
    /// Helper method to set API client scenario based on attribution scenario
    private func setAPIClientScenario(_ scenario: MockASAAttributionManager.MockScenario) {
        switch scenario {
        case .asaUserWithValidToken:
            MockAPIClient.currentScenario = .asaUserWithValidToken
        case .nonASAUser:
            MockAPIClient.currentScenario = .nonASAUser
        case .tokenUnavailable:
            MockAPIClient.currentScenario = .tokenUnavailable
        case .tokenError:
            MockAPIClient.currentScenario = .tokenError
        case .invalidToken:
            MockAPIClient.currentScenario = .invalidToken
        case .networkTimeout:
            MockAPIClient.currentScenario = .networkTimeout
        case .customToken(let token):
            MockAPIClient.currentScenario = .customToken(token)
        }
    }
    
    /// Configure the SDK with test dependencies
    /// - Parameters:
    ///   - attributionProvider: Mock attribution provider
    ///   - transactionMonitor: Mock transaction monitor
    ///   - apiClient: Mock API client
    static func configure(
        attributionProvider: ASAAttributionProviding? = nil,
        transactionMonitor: TransactionMonitoring? = nil,
        apiClient: APIClientProtocol? = nil
    ) {
        let finalAttributionProvider = attributionProvider ?? ProductionASAAttributionProvider()
        let finalTransactionMonitor = transactionMonitor ?? ProductionTransactionMonitor()
        let finalAPIClient = apiClient ?? ProductionAPIClient(apiKey: "sk_test_key")
        
        let testDependencies = SDKDependencies(
            attributionProvider: finalAttributionProvider,
            transactionMonitor: finalTransactionMonitor,
            apiClient: finalAPIClient
        )
        
        ASAAttributionSDK.shared.dependencies = testDependencies
    }
    
    /// Reset the SDK to use production dependencies
    static func resetToProduction(apiKey: String = "sk_test_key") {
        ASAAttributionSDK.shared.dependencies = SDKDependencies.production(apiKey: apiKey)
    }
}

// MARK: - Test SDK Extension

/// Test-only extension for the SDK
/// This provides additional methods that are only available in tests
extension ASAAttributionSDK {
    
    /// Reset all state and return to production configuration
    /// This is useful for cleaning up between tests
    func resetForTesting() {
        resetState()
        dependencies = SDKDependencies.production(apiKey: "sk_test_key")
    }
    
    /// Get the current dependencies (for testing purposes)
    var currentDependencies: SDKDependencies {
        return dependencies ?? SDKDependencies.production(apiKey: "sk_test_key")
    }
} 