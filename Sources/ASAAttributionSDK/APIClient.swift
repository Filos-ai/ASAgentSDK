import Foundation

/// HTTP client for communicating with the ASA Attribution backend
public final class APIClient {
    
    // MARK: - Properties
    private let baseURL: String = "https://ptfygrgncpxinzsmuqha.supabase.co/functions/v1"
    private let apiKey: String
    private let session: URLSession
    private let retryDelay: TimeInterval = 2.0
    private let maxRetries = 3
    
    // Lifetime request limit (ultimate safety check)
    private let maxLifetimeRequests = 100
    private let lifetimeRequestCountKey = "ASAAttributionSDK_LifetimeRequestCount"
    
    // MARK: - Response Models
    public struct CreateUserResponse: Codable {
        public let userId: Int?
        public let didUserComeFromAsa: Bool?
        public let asaAttributionResolved: Bool?
        public let userCreated: Bool?
        
        // Regular initializer for direct instantiation (used by mocks)
        public init(userId: Int?, didUserComeFromAsa: Bool?, asaAttributionResolved: Bool?, userCreated: Bool?) {
            self.userId = userId
            self.didUserComeFromAsa = didUserComeFromAsa
            self.asaAttributionResolved = asaAttributionResolved
            self.userCreated = userCreated
        }
        
        // Custom CodingKeys to handle different field names if needed
        private enum CodingKeys: String, CodingKey {
            case userId
            case didUserComeFromAsa
            case asaAttributionResolved
            case userCreated
        }
        
        // Custom initializer to handle missing fields gracefully
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            // Handle userId - might be present or missing
            userId = try container.decodeIfPresent(Int.self, forKey: .userId)
            
            // Handle optional boolean fields
            didUserComeFromAsa = try container.decodeIfPresent(Bool.self, forKey: .didUserComeFromAsa)
            asaAttributionResolved = try container.decodeIfPresent(Bool.self, forKey: .asaAttributionResolved)
            userCreated = try container.decodeIfPresent(Bool.self, forKey: .userCreated)
        }
    }
    
    public struct ResolveAttributionResponse: Codable {
        public let didUserComeFromAsa: Bool?
        public let asaAttributionResolved: Bool?
    }
    
    public struct AssociateUserResponse: Codable {
        public let success: Bool?
        public let user: User?
        
        public struct User: Codable {
            public let id: Int
            public let transaction_id: String?
        }
    }
    
    public struct ErrorResponse: Codable {
        public let error: String
    }
    
    // MARK: - Initialization
    public init(apiKey: String) {
        self.apiKey = apiKey
        
        // Configure URLSession for reliable operation with reasonable timeouts
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0 // 30 second request timeout
        config.timeoutIntervalForResource = 120.0 // 2 minute resource timeout for long ASA calls
        config.waitsForConnectivity = true // Wait for network connectivity
        config.allowsCellularAccess = true // Allow cellular for background operation
        
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Public Methods
    
    /// Creates a new user in the backend
    /// - Parameter asaAttributionToken: Optional ASA attribution token
    /// - Parameter completion: Result callback
    /// - Note: If ASA token is provided, this may take 20-30 seconds due to backend retry logic
    public func createUser(asaAttributionToken: String?, completion: @escaping (Result<CreateUserResponse, Error>) -> Void) {
        var body: [String: Any] = [:]
        if let token = asaAttributionToken {
            body["asa_attribution_token"] = token
        }
        
        performRequest(
            endpoint: "create-user",
            body: body,
            responseType: CreateUserResponse.self,
            completion: completion
        )
    }
    
    /// Resolves ASA attribution for an existing user
    public func resolveAttribution(userId: Int, asaAttributionToken: String, completion: @escaping (Result<ResolveAttributionResponse, Error>) -> Void) {
        let body: [String: Any] = [
            "user_id": userId,
            "asa_attribution_token": asaAttributionToken
        ]
        
        performRequest(
            endpoint: "resolve-asa-attribution",
            body: body,
            responseType: ResolveAttributionResponse.self,
            completion: completion
        )
    }
    
    /// Associates a transaction ID with a user
    public func associateUser(userId: Int, transactionId: String, completion: @escaping (Result<AssociateUserResponse, Error>) -> Void) {
        let body: [String: Any] = [
            "user_id": userId,
            "transaction_id": transactionId
        ]
        
        performRequest(
            endpoint: "associate-user",
            body: body,
            responseType: AssociateUserResponse.self,
            completion: completion
        )
    }
    
    // MARK: - Async/Await Methods (iOS 13.0+)
    
    /// Creates a new user in the backend using async/await
    /// - Parameter asaAttributionToken: Optional ASA attribution token
    /// - Returns: CreateUserResponse
    /// - Note: This method may take up to 30+ seconds if ASA token resolution is required
    @available(iOS 13.0, macOS 10.15, *)
    public func createUser(asaAttributionToken: String?) async throws -> CreateUserResponse {
        return try await withCheckedThrowingContinuation { continuation in
            createUser(asaAttributionToken: asaAttributionToken) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    /// Resolves ASA attribution for an existing user using async/await
    @available(iOS 13.0, macOS 10.15, *)
    public func resolveAttribution(userId: Int, asaAttributionToken: String) async throws -> ResolveAttributionResponse {
        return try await withCheckedThrowingContinuation { continuation in
            resolveAttribution(userId: userId, asaAttributionToken: asaAttributionToken) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    /// Associates a transaction with a user using async/await
    @available(iOS 13.0, macOS 10.15, *)
    public func associateUser(userId: Int, transactionId: String) async throws -> AssociateUserResponse {
        return try await withCheckedThrowingContinuation { continuation in
            associateUser(userId: userId, transactionId: transactionId) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    // MARK: - Background Operation Methods
    
    /// Creates a new user optimized for background operation
    /// - Parameters:
    ///   - asaAttributionToken: Optional ASA attribution token
    ///   - completion: Final result callback (called on background queue)
    /// - Note: This method has no timeouts and will wait indefinitely for completion
    public func createUserBackground(
        asaAttributionToken: String?,
        completion: @escaping (Result<CreateUserResponse, Error>) -> Void
    ) {
        // Dispatch to background queue to avoid blocking
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.createUser(asaAttributionToken: asaAttributionToken, completion: completion)
        }
    }
    
    // MARK: - Private Methods
    
    /// Checks if the lifetime request limit has been exceeded
    private func hasExceededLifetimeLimit() -> Bool {
        let currentCount = UserDefaults.standard.integer(forKey: lifetimeRequestCountKey)
        return currentCount >= maxLifetimeRequests
    }
    
    /// Increments the lifetime request count
    private func incrementLifetimeRequestCount() {
        let currentCount = UserDefaults.standard.integer(forKey: lifetimeRequestCountKey)
        let newCount = currentCount + 1
        UserDefaults.standard.set(newCount, forKey: lifetimeRequestCountKey)
        
        // Debug logging to track request usage (only in debug builds)
        #if DEBUG
        print("🌐 API Request Count: \(newCount)/\(maxLifetimeRequests)")
        
        if newCount >= maxLifetimeRequests {
            print("⚠️ WARNING: Approaching lifetime API request limit!")
        }
        #endif
    }
    
    /// Gets the current lifetime request count (for debugging/monitoring)
    public func getLifetimeRequestCount() -> Int {
        return UserDefaults.standard.integer(forKey: lifetimeRequestCountKey)
    }
    
    private func performRequest<T: Codable>(
        endpoint: String,
        body: [String: Any],
        responseType: T.Type,
        attempt: Int = 1,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        // Ultimate safety check: Prevent requests if lifetime limit exceeded
        if hasExceededLifetimeLimit() {
            let currentCount = getLifetimeRequestCount()
            #if DEBUG
            print("🚫 API request blocked: Lifetime limit exceeded (\(currentCount)/\(maxLifetimeRequests))")
            #endif
            completion(.failure(APIError.lifetimeLimitExceeded(currentCount, maxLifetimeRequests)))
            return
        }
        
        // Increment request count before making the request
        incrementLifetimeRequestCount()
        
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else {
            completion(.failure(APIError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(APIError.encodingError(error)))
            return
        }
        
        let task = session.dataTask(with: request) { data, response, error in
            // Handle network error first
            if let error = error {
                completion(.failure(APIError.networkError(error)))
                return
            }
            
            // Check for HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(APIError.invalidResponse))
                return
            }
            
            // Check for data
            guard let data = data else {
                completion(.failure(APIError.noData))
                return
            }
            
            // Handle status codes
            if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                // Success case
                do {
                    let decoder = JSONDecoder()
                    let result = try decoder.decode(responseType, from: data)
                    completion(.success(result))
                } catch {
                    completion(.failure(APIError.decodingError(error)))
                }
            } else {
                // Error case - try to decode error response
                do {
                    let decoder = JSONDecoder()
                    let errorResponse = try decoder.decode(ErrorResponse.self, from: data)
                    completion(.failure(APIError.clientError(httpResponse.statusCode, errorResponse.error)))
                } catch {
                    // If error decoding fails, use status code
                    completion(.failure(APIError.unexpectedStatusCode(httpResponse.statusCode)))
                }
            }
        }
        
        task.resume()
    }
}

// MARK: - Error Types
enum APIError: Error, LocalizedError {
    case invalidURL
    case encodingError(Error)
    case networkError(Error)
    case invalidResponse
    case noData
    case decodingError(Error)
    case clientError(Int, String)
    case serverError(Int)
    case unexpectedStatusCode(Int)
    case lifetimeLimitExceeded(Int, Int) // current count, max limit
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .encodingError(let error):
            return "Request encoding error: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response"
        case .noData:
            return "No data received"
        case .decodingError(let error):
            return "Response decoding error: \(error.localizedDescription)"
        case .clientError(let code, let message):
            return "Client error (\(code)): \(message)"
        case .serverError(let code):
            return "Server error (\(code))"
        case .unexpectedStatusCode(let code):
            return "Unexpected status code: \(code)"
        case .lifetimeLimitExceeded(let current, let max):
            return "Lifetime API request limit exceeded (\(current)/\(max)). Please contact support if this is unexpected."
        }
    }
} 