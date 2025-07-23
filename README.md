# ASAgentSDK

A lightweight iOS SDK for Apple Search Ads attribution tracking and transaction association.

## Overview

ASAgentSDK automatically:
- Detects users who came from Apple Search Ads campaigns
- Tracks their purchase transactions
- Associates transactions with users for attribution analytics

The SDK runs entirely in the background with minimal performance impact.

## Installation

### Swift Package Manager

Add the package to your Xcode project:

1. Open your project in Xcode
2. Go to **File → Add Package Dependencies**
3. Enter the repository URL:
   ```
   https://github.com/Filos-ai/ASAgentSDK.git
   ```
4. Select **Up to Next Major** and click **Add Package**

### Manual Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Filos-ai/ASAgentSDK.git", from: "1.0.1")
]
```

## Integration

### Step 1: Import the SDK

```swift
import ASAgentSDK
```

### Step 2: Configure on App Launch

#### SwiftUI Apps

```swift
import SwiftUI
import ASAgentSDK

@main
struct MyApp: App {
    init() {
        // Configure the SDK with your API key
        ASAAttributionSDK.shared.configure(apiKey: "your-api-key")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

#### UIKit Apps

```swift
import UIKit
import ASAgentSDK

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, 
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Configure the SDK with your API key
        ASAAttributionSDK.shared.configure(apiKey: "your-api-key")
        
        return true
    }
}
```

### Step 3: That's It!

The SDK automatically handles:
- ✅ Attribution detection
- ✅ Transaction monitoring
- ✅ Backend communication
- ✅ State management

## Configuration

The SDK requires only one parameter:

- **apiKey**: Your backend API key for authentication

## Requirements

- **iOS**: 13.0+ (Attribution works on iOS 14.3+)
- **Swift**: 5.9+
- **Frameworks**: StoreKit, AdServices (automatically linked)

## Debugging

### Check Current State
```swift
let state = ASAAttributionSDK.shared.getDebugState()
print(state)
```

### Reset State (Testing Only)
```swift
ASAAttributionSDK.shared.resetState()
```

## How It Works

1. **App Launch**: SDK checks if user exists and their attribution status
2. **Attribution**: Determines if user came from Apple Search Ads
3. **Monitoring**: Tracks purchase transactions for ASA users
4. **Association**: Links transactions to users for analytics
5. **Completion**: SDK stops operations when flow is complete

## Support

For issues or questions:
- Check the [Issues](https://github.com/Filos-ai/ASAgentSDK/issues) page
- Contact support

## License

Licensed under the MIT License. See [LICENSE](LICENSE) for details. 