# Yeats VPN iOS

SwiftUI iOS 17+ client for `https://api.yeats.uz`.

## Open

Open:

```text
ios/YeatsVPN/YeatsVPN.xcodeproj
```

Xcode will resolve the Swift Package dependency:

- `KeychainAccess` from `https://github.com/kishikawakatsumi/KeychainAccess.git`

Before building the VPN target on a fresh checkout, unpack Libbox:

```bash
ios/YeatsVPN/scripts/unpack-libbox.sh
```

## Architecture

```text
YeatsVPN
├── App
├── Core
├── Networking
├── Services
├── Features
│   ├── Auth
│   ├── Home
│   ├── VPN
│   └── Profile
├── Models
├── DesignSystem
└── Resources
```

## Backend

Base URL is configured in `AppEnvironment.live()`:

```swift
https://api.yeats.uz
```

Implemented endpoints:

- `POST /auth/register`
- `POST /auth/login`
- `POST /auth/apple`
- `POST /auth/refresh`
- `GET /me`
- `GET /vpn/profile`
- `GET /vpn/usage`

## Notes

- Tokens are stored in Keychain using `KeychainAccess`.
- Sign in with Apple is enabled through `AuthenticationServices` and requires the `uz.yeats.vpn` bundle ID to match backend `APPLE_BUNDLE_ID`.
- `APIClient` retries authenticated requests once after refreshing tokens.
- NetworkExtension, StoreKit, and Push Notifications are represented by placeholder protocols/managers for future production integrations.
- In-app VPN connection requires Apple NetworkExtension entitlement and a packet tunnel provider target.
