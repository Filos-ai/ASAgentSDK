import XCTest
@testable import ASAAttributionSDK

final class ASAAttributionSDKTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Reset state before each test
        ASAAttributionSDK.shared.resetState()
    }
    
    override func tearDown() {
        super.tearDown()
        // Clean up after each test
        ASAAttributionSDK.shared.resetState()
    }
    
    func testStateManagerInitialState() {
        // Create a test-specific UserDefaults to avoid interference
        let testUserDefaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let stateManager = StateManager(userDefaults: testUserDefaults)
        
        XCTAssertFalse(stateManager.userCreated)
        XCTAssertFalse(stateManager.attributionResolved)
        XCTAssertFalse(stateManager.isASAUser)
        XCTAssertFalse(stateManager.transactionCaptured)
        XCTAssertFalse(stateManager.associationComplete)
        XCTAssertNil(stateManager.userId)
        XCTAssertNil(stateManager.originalTransactionID)
        XCTAssertFalse(stateManager.shouldTerminate)
        XCTAssertFalse(stateManager.canAssociate)
    }
    
    func testStateManagerUserCreation() {
        let testUserDefaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let stateManager = StateManager(userDefaults: testUserDefaults)
        
        stateManager.setUserCreated(userId: "123")
        
        XCTAssertTrue(stateManager.userCreated)
        XCTAssertEqual(stateManager.userId, "123")
        XCTAssertFalse(stateManager.shouldTerminate)
        XCTAssertFalse(stateManager.canAssociate)
    }
    
    func testStateManagerAttributionResolution() {
        let testUserDefaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let stateManager = StateManager(userDefaults: testUserDefaults)
        
        stateManager.setUserCreated(userId: "123")
        stateManager.setAttributionResolved(isASAUser: true)
        
        XCTAssertTrue(stateManager.attributionResolved)
        XCTAssertTrue(stateManager.isASAUser)
        XCTAssertFalse(stateManager.shouldTerminate)
        XCTAssertFalse(stateManager.canAssociate)
    }
    
    func testStateManagerNonASAUserTermination() {
        let testUserDefaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let stateManager = StateManager(userDefaults: testUserDefaults)
        
        stateManager.setUserCreated(userId: "123")
        stateManager.setAttributionResolved(isASAUser: false)
        
        XCTAssertTrue(stateManager.attributionResolved)
        XCTAssertFalse(stateManager.isASAUser)
        XCTAssertTrue(stateManager.shouldTerminate)
        XCTAssertFalse(stateManager.canAssociate)
    }
    
    func testStateManagerTransactionCapture() {
        let testUserDefaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let stateManager = StateManager(userDefaults: testUserDefaults)
        
        stateManager.setUserCreated(userId: "123")
        stateManager.setAttributionResolved(isASAUser: true)
        stateManager.setTransactionCaptured(transactionId: "trans123")
        
        XCTAssertTrue(stateManager.transactionCaptured)
        XCTAssertEqual(stateManager.originalTransactionID, "trans123")
        XCTAssertFalse(stateManager.shouldTerminate)
        XCTAssertTrue(stateManager.canAssociate)
    }
    
    func testStateManagerAssociationComplete() {
        let testUserDefaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let stateManager = StateManager(userDefaults: testUserDefaults)
        
        stateManager.setUserCreated(userId: "123")
        stateManager.setAttributionResolved(isASAUser: true)
        stateManager.setTransactionCaptured(transactionId: "trans123")
        stateManager.setAssociationComplete()
        
        XCTAssertTrue(stateManager.associationComplete)
        XCTAssertTrue(stateManager.shouldTerminate)
        XCTAssertTrue(stateManager.canAssociate)
    }
    
    func testStateManagerReset() {
        let testUserDefaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let stateManager = StateManager(userDefaults: testUserDefaults)
        
        // Set up some state
        stateManager.setUserCreated(userId: "123")
        stateManager.setAttributionResolved(isASAUser: true)
        stateManager.setTransactionCaptured(transactionId: "trans123")
        stateManager.setAssociationComplete()
        
        // Verify state is set
        XCTAssertTrue(stateManager.userCreated)
        XCTAssertTrue(stateManager.attributionResolved)
        XCTAssertTrue(stateManager.isASAUser)
        XCTAssertTrue(stateManager.transactionCaptured)
        XCTAssertTrue(stateManager.associationComplete)
        
        // Reset and verify
        stateManager.reset()
        
        XCTAssertFalse(stateManager.userCreated)
        XCTAssertFalse(stateManager.attributionResolved)
        XCTAssertFalse(stateManager.isASAUser)
        XCTAssertFalse(stateManager.transactionCaptured)
        XCTAssertFalse(stateManager.associationComplete)
        XCTAssertNil(stateManager.userId)
        XCTAssertNil(stateManager.originalTransactionID)
    }
    
    func testAPIClientInitialization() {
        let apiClient = APIClient(apiKey: "test-key")
        
        // Test that the API client can be initialized
        XCTAssertNotNil(apiClient)
    }
    
    func testSDKSingletonAccess() {
        let sdk1 = ASAAttributionSDK.shared
        let sdk2 = ASAAttributionSDK.shared
        
        XCTAssertTrue(sdk1 === sdk2)
    }
    
    func testSDKDebugState() {
        let debugState = ASAAttributionSDK.shared.getDebugState()
        
        XCTAssertTrue(debugState.contains("ASA Attribution SDK State"))
        XCTAssertTrue(debugState.contains("User Created: false"))
        XCTAssertTrue(debugState.contains("Attribution Resolved: false"))
    }
    
    func testSDKResetState() {
        // This test verifies that resetState doesn't crash
        XCTAssertNoThrow(ASAAttributionSDK.shared.resetState())
    }
    
    func testASAAttributionManagerAttributionResult() {
        // Test the attribution result enum
        let adServicesResult = ASAAttributionManager.AttributionResult.adServices(token: "test-token")
        let unavailableResult = ASAAttributionManager.AttributionResult.unavailable(reason: "test-reason")
        
        switch adServicesResult {
        case .adServices(let token):
            XCTAssertEqual(token, "test-token")
        case .unavailable:
            XCTFail("Should be adServices result")
        }
        
        switch unavailableResult {
        case .unavailable(let reason):
            XCTAssertEqual(reason, "test-reason")
        case .adServices:
            XCTFail("Should be unavailable result")
        }
    }
    
    func testAPIErrorDescriptions() {
        let networkError = APIError.networkError(NSError(domain: "test", code: 1, userInfo: nil))
        let clientError = APIError.clientError(400, "Bad Request")
        let serverError = APIError.serverError(500)
        
        XCTAssertTrue(networkError.localizedDescription.contains("Network error"))
        XCTAssertTrue(clientError.localizedDescription.contains("Client error (400)"))
        XCTAssertTrue(serverError.localizedDescription.contains("Server error (500)"))
    }
} 