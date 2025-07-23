import Foundation

// MARK: - Attribution Provider Protocol

/// Protocol for ASA attribution providers
/// This allows dependency injection for testing without modifying production code
public protocol ASAAttributionProviding {
    func fetchAttribution(completion: @escaping (ASAAttributionManager.AttributionResult) -> Void)
}

// MARK: - Transaction Monitor Protocol

/// Protocol for transaction monitoring
/// This allows dependency injection for testing without modifying production code
public protocol TransactionMonitoring {
    func start(onTransactionId: @escaping (String) -> Void)
    func stop()
}

// MARK: - API Client Protocol

/// Protocol for API client
/// This allows dependency injection for testing without modifying production code
public protocol APIClientProtocol {
    func createUser(asaAttributionToken: String?, completion: @escaping (Result<APIClient.CreateUserResponse, Error>) -> Void)
    func resolveAttribution(userId: Int, asaAttributionToken: String, completion: @escaping (Result<APIClient.ResolveAttributionResponse, Error>) -> Void)
    func associateUser(userId: Int, transactionId: String, completion: @escaping (Result<APIClient.AssociateUserResponse, Error>) -> Void)
}

// MARK: - Production Implementations

/// Production implementation of ASA attribution provider
public struct ProductionASAAttributionProvider: ASAAttributionProviding {
    public init() {}
    
    public func fetchAttribution(completion: @escaping (ASAAttributionManager.AttributionResult) -> Void) {
        ASAAttributionManager.fetchAttribution(completion: completion)
    }
}

/// Production implementation of transaction monitor
public struct ProductionTransactionMonitor: TransactionMonitoring {
    public init() {}
    
    public func start(onTransactionId: @escaping (String) -> Void) {
        TransactionMonitor.shared.start(onTransactionId: onTransactionId)
    }
    
    public func stop() {
        TransactionMonitor.shared.stop()
    }
}

/// Production implementation of API client
public struct ProductionAPIClient: APIClientProtocol {
    private let apiClient: APIClient
    
    public init(apiKey: String) {
        self.apiClient = APIClient(apiKey: apiKey)
    }
    
    public func createUser(asaAttributionToken: String?, completion: @escaping (Result<APIClient.CreateUserResponse, Error>) -> Void) {
        apiClient.createUser(asaAttributionToken: asaAttributionToken, completion: completion)
    }
    
    public func resolveAttribution(userId: Int, asaAttributionToken: String, completion: @escaping (Result<APIClient.ResolveAttributionResponse, Error>) -> Void) {
        apiClient.resolveAttribution(userId: userId, asaAttributionToken: asaAttributionToken, completion: completion)
    }
    
    public func associateUser(userId: Int, transactionId: String, completion: @escaping (Result<APIClient.AssociateUserResponse, Error>) -> Void) {
        apiClient.associateUser(userId: userId, transactionId: transactionId, completion: completion)
    }
}

// MARK: - SDK Configuration Protocol

/// Protocol for SDK configuration
/// This allows for different configurations in production vs testing
public protocol SDKConfiguring {
    var attributionProvider: ASAAttributionProviding { get }
    var transactionMonitor: TransactionMonitoring { get }
    var apiClient: APIClientProtocol { get }
}

/// Production SDK configuration
public struct ProductionSDKConfiguration: SDKConfiguring {
    public let attributionProvider: ASAAttributionProviding
    public let transactionMonitor: TransactionMonitoring
    public let apiClient: APIClientProtocol
    
    public init(apiKey: String) {
        self.attributionProvider = ProductionASAAttributionProvider()
        self.transactionMonitor = ProductionTransactionMonitor()
        self.apiClient = ProductionAPIClient(apiKey: apiKey)
    }
}

/// Internal SDK configuration holder
/// This is used internally by the SDK to manage dependencies
public struct SDKDependencies {
    public let attributionProvider: ASAAttributionProviding
    public let transactionMonitor: TransactionMonitoring
    public let apiClient: APIClientProtocol
    
    public init(attributionProvider: ASAAttributionProviding, transactionMonitor: TransactionMonitoring, apiClient: APIClientProtocol) {
        self.attributionProvider = attributionProvider
        self.transactionMonitor = transactionMonitor
        self.apiClient = apiClient
    }
    
    public static func production(apiKey: String) -> SDKDependencies {
        return SDKDependencies(
            attributionProvider: ProductionASAAttributionProvider(),
            transactionMonitor: ProductionTransactionMonitor(),
            apiClient: ProductionAPIClient(apiKey: apiKey)
        )
    }
} 