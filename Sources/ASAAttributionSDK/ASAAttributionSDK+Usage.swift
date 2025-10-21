import Foundation

/*
 ASA Attribution SDK Usage Example
 
 This file demonstrates how to integrate and use the ASA Attribution SDK in your iOS app.
 
 ## Basic Integration
 
 ### 1. Initialize the SDK in your AppDelegate or @main App struct
 
 ```swift
 import ASAAttributionSDK
 
 @main
 struct MyApp: App {
     init() {
         // Configure the SDK with your API key
         ASAAttributionSDK.shared.configure(apiKey: "your-api-key-here")
     }
     
     var body: some Scene {
         WindowGroup {
             ContentView()
         }
     }
 }
 ```
 
 ### 2. For UIKit apps, use AppDelegate
 
 ```swift
 import UIKit
 import ASAAttributionSDK
 
 @main
 class AppDelegate: UIResponder, UIApplicationDelegate {
     func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
         
         // Configure the SDK
         ASAAttributionSDK.shared.configure(apiKey: "your-api-key-here")
         
         return true
     }
 }
 ```
 
 ## How It Works
 
   Once configured, the SDK will automatically run in the background:
  
  1. **Check user status** - Determine if a user record exists
  2. **Create new user** - If no user exists, create one in the backend
  3. **Resolve ASA attribution** - Check if the user came from Apple Search Ads
  4. **Monitor transactions** - Listen for StoreKit purchases (runs in parallel)
  5. **Associate transactions** - Link purchase data to the user record
  6. **Terminate** - Stop all operations when complete or if user is non-ASA
  
  ⚡️ **All operations run in background threads** - No blocking of the main thread during app launch
 
 ## SDK States
 
 The SDK tracks these persistent states:
 - `userCreated`: User record exists in backend
 - `attributionResolved`: ASA attribution has been determined
 - `isASAUser`: User originated from Apple Search Ads
 - `transactionCaptured`: Purchase transaction ID captured
 - `associationComplete`: Transaction linked to user record
 
 ## Termination Conditions
 
 The SDK will automatically stop operating when:
 - User is determined to be non-ASA (`isASAUser = false`)
 - Full attribution flow is complete (`associationComplete = true`)
 
 ## Debugging
 
 ```swift
 // Check current SDK state
 let currentState = ASAAttributionSDK.shared.getDebugState()
 print(currentState)
 
 // Reset SDK state (useful for testing)
 ASAAttributionSDK.shared.resetState()
 ```
 
 ## Error Handling
 
 The SDK handles errors gracefully:
 - **Network failures**: Automatic retry with exponential backoff
 - **API errors**: Logged with appropriate error messages
 - **Invalid states**: SDK will retry on next app launch
 
   ## Performance
  
  The SDK is designed for minimal impact:
  - **Non-blocking configuration** - Returns immediately, runs in background
  - **Thread-safe operations** - All state management is synchronized
  - **Parallel execution** - Attribution and transaction monitoring run concurrently
  - **Automatic termination** - Operations stop when not needed
  - **Efficient StoreKit integration** - Supports both v1 and v2
 
## Requirements
 
- iOS 13.0+ (Attribution only works on iOS 14.3+)
- **IMPORTANT: Native iOS devices ONLY - Not supported on macOS, iPad apps running on macOS, or Catalyst apps**
- Swift 5.9+
- StoreKit framework
- AdServices framework (for ASA attribution - iOS only)
 
## Platform Support
 
✅ **Supported:**
- iPhone running iOS 13.0+ (attribution requires iOS 14.3+)
- iPad running iPadOS 13.0+ (attribution requires iPadOS 14.3+)
 
❌ **NOT Supported:**
- macOS (native Mac apps)
- iPad apps running on macOS (Apple Silicon Macs with "Designed for iPad" apps)
- Mac Catalyst apps
- Other platforms (watchOS, tvOS)
 
**Why?** The SDK relies on Apple's AdServices framework which is only available on native iOS devices.
 
The SDK will automatically detect unsupported platforms and gracefully terminate without crashing.
You can check platform support programmatically:
 
```swift
if ASAAttributionSDK.isPlatformSupported() {
    ASAAttributionSDK.shared.configure(apiKey: "your-key")
} else {
    print("ASA Attribution not available on this platform")
}
```
 
## Backend Configuration
 
 Ensure your backend functions are properly deployed:
 - `create-user`: Creates new user records
 - `resolve-asa-attribution`: Resolves ASA attribution tokens
 - `associate-user`: Links transaction IDs to users
 
 ## API Key Security
 
 - Store API keys securely (consider using Keychain)
 - Use different keys for development/production environments
 - Rotate keys regularly for security
 
 ## Testing
 
 For testing purposes:
 
 ```swift
 // Reset state to test different scenarios
 ASAAttributionSDK.shared.resetState()
 
 // Check logs in Console.app for detailed flow information
 // Filter by subsystem: "com.asaattribution.sdk"
 ```
 
 */ 