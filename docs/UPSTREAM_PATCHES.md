# Upstream issue and pull-request register

Initial status check: 2026-10-18. These are candidates to inspect and adapt, not changes already validated in Sawti. The local checkout is pinned to `a4f6af6df2674bc4e18097084a128af469823fab`; the listed open PR heads are not part of that commit. Recheck their state, diff and target API before adoption. Never merge or cherry-pick a whole PR solely because its author reports passing tests.

| Reference | Status observed | Relevance and Sawti disposition |
|---|---|---|
| [PR #785](https://github.com/pasrom/meeting-transcriber/pull/785) | Open | Unified quit path, snapshot ownership, recovery gates and staged writes. Adapt the single-writer and state-retention ideas for P2.1/P2.7. It still allows capture teardown to block the main thread; its test harness touches shared production-style paths. Do not treat it as proof of bounded hardware calls or import it without isolated Sawti tests. |
| [PR #789](https://github.com/pasrom/meeting-transcriber/pull/789) | Draft | Bounded microphone no-buffer monitoring/revival policy. Useful for P2.4 after review. It does not solve first synchronous mic startup (#778); write accounting and stop/bridge races need independent review. |
| [PR #713](https://github.com/pasrom/meeting-transcriber/pull/713) | Open | Conservative wrong-output-anchor detection and bounded fallback. Candidate for P2.5. Does not solve Safari routing (#671); device-order and watchdog behavior need validation against the pinned AudioTapLib. |
| [PR #675](https://github.com/pasrom/meeting-transcriber/pull/675) | Open | Explicit CPU + Neural Engine routing avoids the reported offline-diarization Metal/MPSGraph abort. Review the pinned FluidAudio 0.17.4 API and validate all retained modes before adapting in P3.5. The author reported local build unavailability at the time of the PR. |
| [PR #801](https://github.com/pasrom/meeting-transcriber/pull/801) | Open | Moves Claude CLI work to a private temporary directory and suppresses CLI session persistence when supported. Sawti core has provider generation disabled; retain as a future privacy fix if optional CLI support is ever re-enabled. It does not make a cloud-backed CLI local. |
| [PR #759](https://github.com/pasrom/meeting-transcriber/pull/759) | Open | Adds local-folder/custom WhisperKit model-origin and tokenizer validation concepts. Reuse only the local asset completeness ideas for P3.2/P4.3; do not expose arbitrary remote model sources or ambient credential lookup by default. |
| [PR #760](https://github.com/pasrom/meeting-transcriber/pull/760) | Draft | Adds an eight-speaker Nemotron diarization option. Defer: this is outside the core gate and has no M2/8 GB qualification in the evidence inspected. Preserve existing diarizers. |
| [PR #792](https://github.com/pasrom/meeting-transcriber/pull/792) | Open | Adds opt-in English translation for captions/transcripts. Do not merge translation into immutable original-language ASR output; configuration snapshots may inform P3.1. |
| [PR #800](https://github.com/pasrom/meeting-transcriber/pull/800) | Open | Avoids menu Cancel hover loss during progress updates and uses per-job timing. Consider the native menu approach in P6.1, keyed by job/session identity rather than title. |
| [PR #798](https://github.com/pasrom/meeting-transcriber/pull/798) | Open | WhisperKit 1.1.1 dependency candidate. Release notes mention crash and download fixes but change credential discovery behavior; defer until the baseline is buildable and before/after accuracy, offline, memory, OS and license checks pass. |
| [PR #797](https://github.com/pasrom/meeting-transcriber/pull/797) | Open | FluidAudio 0.17.7 dependency candidate and additional features. Keep the pinned 0.17.4 baseline until a specific core fix justifies a separately tested version change and the shipped binary/license graph is reconciled. |

## Open issues carried into implementation

| Issue | Status observed | Consequence |
|---|---|---|
| [#790 — tests write into the real app data folder](https://github.com/pasrom/meeting-transcriber/issues/790) | Open | Do not run the full inherited suite or E2E scripts until P1 test-home isolation and access guards are in place. This is a personal-data safety issue, not a test inconvenience. |
| [#778 — microphone first-start can wedge](https://github.com/pasrom/meeting-transcriber/issues/778) | Open | P0.4 must test actual helper start/stop and blocked first-start handling; PR #789 does not cover it. |
| [#791 — Comet video-capture helper stalls app tap](https://github.com/pasrom/meeting-transcriber/issues/791) | Open | Keep app-selection scope conservative; validate Chrome/Meet, Zoom and Teams first. No universal browser claim. |
| [#745 — quit can lose last queue state](https://github.com/pasrom/meeting-transcriber/issues/745) | Open | Adapt snapshot/quit ownership in P2.1/P2.7 and verify persistence independently from live quit success. |
| [#671 — Safari app-audio capture limitations](https://github.com/pasrom/meeting-transcriber/issues/671) | Open investigation | Preserve support code but do not promise Safari capture/detection as a required route. |

Other issues in the approved v1.1 plan remain indexed there. Recheck relevant issue state before the owning task. This table records the initial implementation-time review, not a guarantee that GitHub status remains unchanged.
