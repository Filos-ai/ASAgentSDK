import Foundation
import AdServices

public final class ASAAttributionManager {
    public enum AttributionResult {
        case adServices(token: String)
        case unavailable(reason: String)
    }
    
    private let apiClient: APIClient
    
    public init(apiKey: String) {
        self.apiClient = APIClient(apiKey: apiKey)
    }

    public static func fetchAttribution(completion: @escaping (AttributionResult) -> Void) {
        #if os(iOS)
        if #available(iOS 14.3, *) {
            Task {
                do {
                    let token = try await AAAttribution.attributionToken()
                    completion(.adServices(token: token))
                } catch {
                    completion(.unavailable(reason: "AdServices error: \(error.localizedDescription)"))
                }
            }
        } else {
            completion(.unavailable(reason: "Apple Search Ads attribution is only supported on iOS 14.3 and later."))
        }
        #else
        completion(.unavailable(reason: "Apple Search Ads attribution is only supported on iOS 14.3 and later."))
        #endif
    }
    
        // MARK: - Background Operation Methods
    
    /// Creates a user in background with full completion guarantee
    /// - Parameter asaAttributionToken: Optional ASA attribution token
    /// - Parameter completion: Called when operation completes (may take 30+ seconds)
    /// - Note: No timeouts - operation will complete even if it takes several minutes
    public func createUserBackground(
        asaAttributionToken: String?,
        completion: @escaping (Result<APIClient.CreateUserResponse, Error>) -> Void
    ) {
        apiClient.createUserBackground(asaAttributionToken: asaAttributionToken, completion: completion)
    }
    
    /// Async version for background operation (iOS 13+)
    @available(iOS 13.0, macOS 10.15, *)
    public func createUserBackgroundAsync(asaAttributionToken: String?) async throws -> APIClient.CreateUserResponse {
        return try await withCheckedThrowingContinuation { continuation in
            createUserBackground(asaAttributionToken: asaAttributionToken) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    /// Resolves attribution in background with full completion guarantee
    public func resolveAttributionBackground(
        userId: Int,
        asaAttributionToken: String,
        completion: @escaping (Result<APIClient.ResolveAttributionResponse, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.apiClient.resolveAttribution(
                userId: userId,
                asaAttributionToken: asaAttributionToken,
                completion: completion
            )
        }
    }
    
    /// Associates transaction in background
    public func associateUserBackground(
        userId: Int,
        transactionId: String,
        completion: @escaping (Result<APIClient.AssociateUserResponse, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.apiClient.associateUser(
                userId: userId,
                transactionId: transactionId,
                completion: completion
            )
        }
    }
} 