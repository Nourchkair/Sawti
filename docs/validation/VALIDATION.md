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
| Stable local code-signing identity | Dedicated `SawtiProbe.keychain-db` contains the self-signed Sawti Probe Local Development certificate (SHA-256 `7F93BD3AF2E78FDF245DD8A8A77F788D53F3C232E4CA852D141AAD45C95812A5`; SHA-1 identity `7D60FFE66E505EF9CAA56F6EA57413AB9DEF1EF4`). `security find-identity -v -p codesigning` reports one valid identity | Identity is enumerated as valid, but a disposable arm64 Mach-O bundle could not be signed: `codesign` returned `errSecInternalComponent`, and verification reports no signature |
| Keychain and trust scope | Dedicated keychain is outside the user's current keychain search list; that list contains only `login.keychain-db`. The keychain unlock secret is stored as one generic-password item in the login keychain. `security dump-trust-settings` reports one trust entry for this certificate constrained to Code Signing; `security verify-cert -p codeSign` succeeds | A user-level, Code Signing-only trust rule is configured for the Sawti probe certificate. No system-wide trust setting was added. The saved keychain secret was retrieved without displaying it, but `SecKeychainUnlock` returned `errSecAuthFailed`; no persistent private-key access grant was made |
| Safe isolated test environment | Not established | **Pending**: issue #790 identifies real-data test writes; first create P1 isolation guards before running inherited suites |
| Actual app/mic audio capture through helpers | Not attempted | **Pending**: no helper code or permission prompt has run |
| Processing sandbox/model access | Not attempted | **Pending**: validate with actual installed local model before Alpha |

## Gate status

| Gate | Status | Evidence / next action |
|---|---|---|
| G0 baseline and identity | In progress | Baseline pinned and source/issue registers added. Xcode/Swift prerequisite, one enumerated signing identity and user-scoped Code Signing trust are confirmed; the dedicated keychain unlock secret did not unlock it, and the Mach-O signing probe produced no signature |
| GA P0.4 helper/TCC feasibility | **Blocked before test** | Toolchain and certificate trust are ready. The disposable Mach-O signing probe returned `errSecInternalComponent`; no helper, TCC, or capture behavior has been tested |
| G1 isolated test infrastructure | Not started | Must prevent personal data access before inherited tests run |
| Gα Sawti Alpha | Not started | Depends on GA/G0/G1 and early slices in the approved implementation plan |

No repository app build, launch, unit/integration test, model load, microphone prompt, system-audio permission request, fixture recording or installed package has been performed against this checkout. The Xcode/Swift version checks and disposable signing checks are environment/identity probes, not repository app builds or capture tests. Code Signing policy evaluation for the dedicated certificate succeeds, but the Mach-O signing probe returned `errSecInternalComponent` and left no signature; the generated keychain unlock secret was rejected by the keychain. Do not infer that a helper can launch or obtain TCC permissions from certificate trust alone.

## Evidence rules

- Store only disposable test signals/recordings under an explicit temporary Sawti probe root. Never copy from `~/Library/Application Support/MeetingTranscriber`, Nour's personal recordings or AcademiaOS.
- Record bundle identifier, signing identity/designated requirement, process ancestry, permission state, OS/build, channel configuration, saved file hashes and frame counts with each capture attempt.
- A granted TCC entry, successful `start()` return or zero application error is not proof of audio delivery. Analyze the bytes written by the helper and a known marker in each required source.
- A blocked startup/stop test passes only when the UI remains responsive, the unaffected channel persists independently and the declared supervisor policy actually terminates or latches the failed helper.
- Do not run inherited suite/E2E scripts until P1.2 has isolated defaults, HOME, test file roots and permission access. For the first safe baseline, record exact command, toolchain, environment and whether any test was skipped.
