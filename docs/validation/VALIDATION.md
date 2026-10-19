# Sawti validation ledger

This is the initial implementation evidence ledger. It records observations and blocked checks; it does not certify Sawti.

## Current environment (2026-10-18)

| Requirement | Observed | Result |
|---|---|---|
| Apple Silicon M2 / 8 GB | Yes: MacBook Air, `Mac14,2`, Apple M2, 8 GB | Accepted by user as the development target; MacBook Pro qualification is separate if included in release support claims |
| macOS 14.2+ | macOS 26.6.2 | API floor is satisfied on this host; oldest advertised OS remains unqualified |
| Xcode build tools | `xcode-select` points to `/Applications/Xcode.app/Contents/Developer`; Xcode 27.1 (27A9275) | Selected; Xcode build tools are now available |
| macOS SDK | 27.0 from the selected Xcode 27.1 installation | Available; actual app/package build remains untested |
| Swift tools 6.2 | Apple Swift 6.4, target `arm64-apple-macosx26.0` | Toolchain requirement is satisfied; no repository build has been run |
| Stable local code-signing identity | Original `SawtiProbe.keychain-db` contains the self-signed Sawti Probe Local Development certificate (SHA-256 `7F93BD3AF2E78FDF245DD8A8A77F788D53F3C232E4CA852D141AAD45C95812A5`; SHA-1 identity `7D60FFE66E505EF9CAA56F6EA57413AB9DEF1EF4`). A separate recovery keychain contains a replacement self-signed identity (SHA-256 `B65431C33A1A05B1777EED4B7FECE9AA531122D37E17C76D4FFAB7E8E7A55BEF`; SHA-1 identity `DD7AD770EE104069C486B4B7D3ABF8175C8838A0`). `security find-identity -v -p codesigning` reports one valid identity for the recovery keychain. A local Swift key-level test successfully signed a disposable message | Both identities are preserved, but the disposable arm64 Mach-O bundle still could not be signed: `codesign` returned `errSecInternalComponent`, and verification reports no signature. A narrow attempt to allow `/usr/bin/codesign` on the recovery key returned Security status `-128` (user canceled); no access grant was confirmed |
| Keychain and trust scope | The original keychain was left untouched. A separate `SawtiProbeRecovery.keychain-db` was created; a generated unlock secret was stored as one generic-password item in the login keychain and successfully retrieved to unlock the recovery keychain in a local Swift probe. The keychain search list was temporarily extended for signing and restored to login-only. The recovery keychain was relocked after the attempts. `security dump-trust-settings` still lists only the original certificate's user-level Code Signing trust rule; no system-wide trust setting was added. `security verify-cert -c recovery-cert.pem -p codeSign` reported successful verification | The recovery identity is enumerated as valid and its private key can sign within the unlocked probe process. Code Signing policy verification succeeds, but the recovery certificate's separate user trust-setting entry and `codesign` process access remain unconfirmed. The Mach-O signing attempt still returns `errSecInternalComponent`; no persistent private-key access grant or bundle signature was produced |
| Safe isolated test environment | Not established | **Pending**: issue #790 identifies real-data test writes; first create P1 isolation guards before running inherited suites |
| Actual app/mic audio capture through helpers | Not attempted | **Pending**: no helper code or permission prompt has run |
| Processing sandbox/model access | Not attempted | **Pending**: validate with actual installed local model before Alpha |

## Gate status

| Gate | Status | Evidence / next action |
|---|---|---|
| G0 baseline and identity | In progress | Baseline pinned and source/issue registers added. Xcode/Swift prerequisite, one enumerated recovery identity, and in-process private-key signing are confirmed. The generated recovery-keychain secret unlocks the keychain, but external `codesign` still returns `errSecInternalComponent`; the narrow `/usr/bin/codesign` access change returned user-canceled status `-128`, and the recovery certificate's user trust entry remains unconfirmed |
| GA P0.4 helper/TCC feasibility | **Blocked before test** | The replacement identity passes `security find-identity`; the private key signs data in-process and `security verify-cert` reports Code Signing policy success. The separate `codesign` process still returns `errSecInternalComponent`, leaving the bundle unsigned; the access-list change was canceled. No helper, TCC, or capture behavior has been tested |
| G1 isolated test infrastructure | Not started | Must prevent personal data access before inherited tests run |
| Gα Sawti Alpha | Not started | Depends on GA/G0/G1 and early slices in the approved implementation plan |

No repository app build, launch, unit/integration test, model load, microphone prompt, system-audio permission request, fixture recording or installed package has been performed against this checkout. The Xcode/Swift version checks and disposable signing checks are environment/identity probes, not repository app builds or capture tests. Code Signing policy verification for both probe certificates succeeds, and the recovery private key signs a disposable message in-process, but the external Mach-O signing attempt returned `errSecInternalComponent` and left no signature. The original keychain's saved unlock secret was rejected; the separate recovery keychain's generated unlock secret succeeds. A narrow access-list change for `/usr/bin/codesign` returned user-canceled status `-128`. Do not infer that a helper can launch or obtain TCC permissions from certificate policy verification or in-process signing alone.

## Evidence rules

- Store only disposable test signals/recordings under an explicit temporary Sawti probe root. Never copy from `~/Library/Application Support/MeetingTranscriber`, Nour's personal recordings or AcademiaOS.
- Record bundle identifier, signing identity/designated requirement, process ancestry, permission state, OS/build, channel configuration, saved file hashes and frame counts with each capture attempt.
- A granted TCC entry, successful `start()` return or zero application error is not proof of audio delivery. Analyze the bytes written by the helper and a known marker in each required source.
- A blocked startup/stop test passes only when the UI remains responsive, the unaffected channel persists independently and the declared supervisor policy actually terminates or latches the failed helper.
- Do not run inherited suite/E2E scripts until P1.2 has isolated defaults, HOME, test file roots and permission access. For the first safe baseline, record exact command, toolchain, environment and whether any test was skipped.
