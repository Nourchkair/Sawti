# Sawti validation ledger

This is the initial implementation evidence ledger. It records observations and blocked checks; it does not certify Sawti.

## Current environment (2026-10-18)

| Requirement | Observed | Result |
|---|---|---|
| Apple Silicon M2 / 8 GB | Yes: MacBook Air, `Mac14,2`, Apple M2, 8 GB | Suitable for early development; not the specified MacBook Pro; exact product qualification pending |
| macOS 14.2+ | macOS 26.6.2 | API floor is satisfied on this host; oldest advertised OS remains unqualified |
| Swift tools 6.2 | Selected Swift is 6.0.3 from Command Line Tools | **Blocked**: do not lower package/toolchain requirements |
| Stable local code-signing identity | `security find-identity` reports zero valid identities | **Blocked**: actual TCC permission persistence/helper signing cannot yet be evaluated |
| Safe isolated test environment | Not established | **Pending**: issue #790 identifies real-data test writes; first create P1 isolation guards before running inherited suites |
| Actual app/mic audio capture through helpers | Not attempted | **Pending**: no helper code or permission prompt has run |
| Processing sandbox/model access | Not attempted | **Pending**: validate with actual installed local model before Alpha |

## Gate status

| Gate | Status | Evidence / next action |
|---|---|---|
| G0 baseline and identity | In progress | Baseline pinned and source/issue registers added. Probe identity and isolation still to implement after toolchain/signing prerequisites are addressed |
| GA P0.4 helper/TCC feasibility | **Blocked before test** | Requires Swift 6.2-capable compiler and stable local signing identity; exact target model also differs. No capture result is inferred from source review |
| G1 isolated test infrastructure | Not started | Must prevent personal data access before inherited tests run |
| Gα Sawti Alpha | Not started | Depends on GA/G0/G1 and early slices in the approved implementation plan |

No build, app launch, unit/integration test, model load, microphone prompt, system-audio permission request, fixture recording or installed package has been performed against this checkout.

## Evidence rules

- Store only disposable test signals/recordings under an explicit temporary Sawti probe root. Never copy from `~/Library/Application Support/MeetingTranscriber`, Nour's personal recordings or AcademiaOS.
- Record bundle identifier, signing identity/designated requirement, process ancestry, permission state, OS/build, channel configuration, saved file hashes and frame counts with each capture attempt.
- A granted TCC entry, successful `start()` return or zero application error is not proof of audio delivery. Analyze the bytes written by the helper and a known marker in each required source.
- A blocked startup/stop test passes only when the UI remains responsive, the unaffected channel persists independently and the declared supervisor policy actually terminates or latches the failed helper.
- Do not run inherited suite/E2E scripts until P1.2 has isolated defaults, HOME, test file roots and permission access. For the first safe baseline, record exact command, toolchain, environment and whether any test was skipped.
