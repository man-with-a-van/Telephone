# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Telephone is a macOS VoIP SIP softphone (Cocoa app, mixed Objective-C + Swift 5, minimum target macOS 13.5, universal arm64+x86_64). It wraps the [PJSIP](https://www.pjsip.org/) C library and an App Store receipt-validation XPC service. README states pull requests are not accepted for legal reasons.

## Building

The app cannot be built without prebuilt third-party libraries placed under `ThirdParty/`. They are gitignored and must be produced locally per the exact recipe in `README.md`:

- `ThirdParty/Opus` — Opus 1.3.1 (optional; remove `--with-opus` from PJSIP configure if skipping)
- `ThirdParty/LibreSSL` — LibreSSL 3.1.5
- `ThirdParty/PJSIP` — pjproject 2.10, with the three patches in `ThirdParty/PJSIP/patches/` applied and the specific `config_site.h` from the README

All three must be built with `-arch arm64 -arch x86_64 -mmacosx-version-min=13.5` and installed via `--prefix=/path/to/Telephone/ThirdParty/<Name>`. Do not skip the patches or change the prefix — the Xcode project resolves headers/libs from those exact locations.

After third-party libs are in place, build via `Telephone.xcodeproj` (no workspace, no Package.swift, no SPM/CocoaPods/Carthage).

## Testing

Tests use XCTest. Shared schemes exist for the lower layers, which is the fast path when iterating on framework code:

```sh
xcodebuild -project Telephone.xcodeproj -scheme Domain      -destination 'platform=macOS' test
xcodebuild -project Telephone.xcodeproj -scheme UseCases    -destination 'platform=macOS' test
xcodebuild -project Telephone.xcodeproj -scheme ReceiptValidationTests -destination 'platform=macOS' test
```

Run a single test:

```sh
xcodebuild -project Telephone.xcodeproj -scheme UseCases -destination 'platform=macOS' \
  -only-testing:UseCasesTests/SimpleContactMatchingIndexTests/testFoo test
```

`TelephoneTests` (the app-level test bundle) has no shared scheme — run it from inside Xcode, or build the `Telephone` scheme there first to generate one. The `Telephone` app scheme itself is not in `xcshareddata` either.

## Architecture

The codebase is organised as concentric layers, each a separate Xcode target. Dependencies only point inward (`Telephone → UseCases → Domain`). There is no DI container — wiring is fully manual in `Telephone/CompositionRoot.swift`, instantiated once from `AppController`.

### Layers (inner → outer)

- **`Domain/`** — pure-Swift framework. Protocols and value types only: `SystemAudioDevice`, `UserAgentAudioDevice`, `SoundIO`, `SystemSoundIO`, plus a few small concrete value types (`SimpleSystemAudioDevice`, `PreferredSoundIO`, `SystemToUserAgentAudioDeviceMap`, etc.). No Cocoa, no PJSIP, no I/O.
- **`UseCases/`** — application-logic framework. ~150+ files, each typically one protocol or one small type. Domain entities (`Account`, `Call`, `CallHistory`, `Contact`, `Product`, `Ringtone`, `MusicPlayer`, `Store`, …), use-case command objects conforming to `@objc protocol UseCase { func execute() }`, and event-target/event-source protocols. Depends only on `Domain` and Foundation.
- **`Telephone/`** (app target) — UI, system integration, PJSIP bridging, Storyboards/XIBs, ObjC + Swift mixed. Adapters live here that turn system frameworks into `UseCases` protocols (`CoreAudio*Factory`, `CNContactStoreToContactsAdapter`, `SKPaymentQueueToStoreAdapter`, `NSSoundToSoundAdapter`, `FoundationToUseCasesTimerAdapter`, …). View controllers are mostly ObjC; newer code is Swift.
- **`ReceiptValidation/`** — separate sandboxed XPC service that validates App Store receipts (ASN.1 / PKCS7 parsing, signature + checksum validation). The app talks to it via `Telephone/ReceiptXPCGateway.swift`. It has its own bridging header and entitlements file.
- **`AddressBookPlugIns/`** — two ObjC bundles (`TelephoneAddressBookPhonePlugIn`, `TelephoneAddressBookSIPAddressPlugIn`) that add Telephone as a callable action in macOS Address Book.

### Test-double frameworks

`DomainTestDoubles/` and `UseCasesTestDoubles/` are real Xcode framework targets, separate from the test bundles, holding `Spy` / `Fake` / `Stub` / `Null` implementations of the public protocols. The test bundles (`DomainTests`, `UseCasesTests`, `TelephoneTests`, `ReceiptValidationTests`) link them. When you add a new protocol to `Domain` or `UseCases`, expect to add a matching double in the corresponding test-doubles framework rather than declaring one inside a test file.

### PJSIP bridging

PJSIP is a C library; the bridging surface is concentrated in `Telephone/AKSIP*.{h,m}`:

- `AKSIPUserAgent` is the single PJSUA wrapper (singleton: `AKSIPUserAgent.shared()`). PJSIP C callbacks live in `Telephone/PJSUAOn*.m` files and forward into the user agent / accounts / calls.
- `AKSIPAccount`, `AKSIPCall`, `AKSIPURI`, `AKSIPURIFormatter`, `AKSIPURIParser` model SIP entities at the ObjC layer.
- Swift-side adapters bridge ObjC notifications into `UseCases` event-target protocols: `AKSIPUserAgentEventSource`, `AKSIPCallEventSource`, `AKSIPUserAgent+Calls`, `AKSIPUserAgent+UserAgent`.
- `Telephone/Telephone-Bridging-Header.h` is the only path for Swift code to see ObjC headers; add new ObjC headers there if Swift needs them.

### Recurring patterns to recognise before editing

The codebase prefers many tiny types over big classes, composed via decorators. Naming is load-bearing — recognising the pattern tells you where a behaviour lives:

- `EnqueuingX` — wraps `X` to dispatch every call on an `ExecutionQueue` (usually a `GCDExecutionQueue` on the main queue). Used to marshal PJSIP/CoreAudio callbacks back to the main thread before they hit UI/use-case code.
- `Notifying*`, `*EventTarget`, `*EventTargets`, `*EventSource` — observer pattern. `EventSource` types translate system notifications (NSNotificationCenter, KVO, Core Audio property listeners, SKPaymentQueue, CNContactStoreDidChange, NSCalendarDay) into calls on `EventTarget` protocols. `EventTargets` (plural) is a multicaster.
- `Weak*` — non-retaining wrapper over an `EventTarget` so the observer doesn't create a retain cycle.
- `Default*` — the production implementation of a protocol when there are also decorators around it (e.g. `DefaultRingtonePlaybackUseCase` is wrapped by `ConditionalRingtonePlaybackUseCase`).
- `Settings*` — use cases that load/save state through `KeyValueSettings` (a thin protocol over `UserDefaults`, see `KeyValueSettings+UserDefaults.swift`) or `PropertyListStorage`.
- `Logging*`, `Truncating*`, `Reversed*`, `LazyDiscarding*`, `RecordCounting*`, `ReceiptValidating*` — additional decorator layers; they wrap the protocol they're named after.
- `*Factory` — manual factories. Composition happens in `CompositionRoot.swift` and `*Factory` types; there is no reflection-based DI.

When changing behaviour, first check whether the right answer is a new decorator or a different decorator order in `CompositionRoot.swift`, rather than modifying an existing concrete type.

### Settings migrations

User defaults schema changes go through `Telephone/ProgressiveSettingsMigration.swift` plus a `*SettingsMigration.swift` per change (`AccountUUIDSettingsMigration`, `IPVersionSettingsMigration`, `TCPTransportSettingsMigration`, …). New migrations must be registered in `DefaultSettingsMigrationFactory` so they actually run.

### Localization

Strings live in `en.lproj/`, `de.lproj/`, `ru.lproj/` under `Telephone/`, `UseCases/`, and `AddressBookPlugIns/`. Each has its own `Localizable.strings` and per-XIB strings files; updating user-facing text means touching all three locales.
