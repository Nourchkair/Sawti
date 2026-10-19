# Sawti capability and preservation register

This register starts at the pinned Meeting Transcriber baseline. “Preserve” means retain the source and test coverage through extraction; it does not claim the feature has passed Sawti-specific process, privacy or M2 qualification. A feature may be exposed only when the applicable Sawti acceptance gate passes. Material removal requires a recorded scope decision.

| Existing capability / source boundary | Sawti disposition | Gate and evidence needed |
|---|---|---|
| Dual app-audio and microphone capture (`AudioCaptureSession`, `DualSourceRecorder`, `RecordingProvider`) | Preserve low-level mechanisms; begin helper extraction with an in-bundle command-line helper signed under the host's code-signing identifier; request TCC access from the host UI | Minimal mic-only helper/TCC/IPC feasibility passed in P0.4; G2 must still qualify app-audio capture, real meeting routes, faults and completeness |
| Microphone-only and manual app capture (`MicCaptureHandler`, `AppTapSession`, `AppPickerView`) | Preserve; make mic-only first-class and retain manual picker as fallback | Alpha short-session proof; G2 on actual required devices |
| Native Teams/Zoom and Chromium/WebRTC meeting detection | Preserve implementations and consent; auto-monitoring remains off until explicit opt-in and safe lifecycle are qualified | G2 detector/consent matrix; P7 route-specific claims |
| Optional app-activity microphone monitoring | Preserve code and controls; do not silently remove applications | Validate each enabled detector and permission; no new detector work on core path |
| Imported audio/video and paired-track formats | Preserve decoder/import paths; copy original bytes before any derived processing | G3 coverage plus G4 copy-only ownership/error tests |
| WhisperKit and Parakeet engines | Preserve both adapters and lock pins initially; select per-language defaults only from evidence | G3 offline, accuracy and complete-window tests; G5 memory tests |
| Offline and Sortformer diarization, speaker profiles, enrollment | Preserve existing source/data format; generic labels and manual correction are core; automatic real-name and enrollment improvements deferred | G3 speaker-mode/uncertainty checks; explicit opt-in and profile privacy before naming |
| VAD, custom vocabulary, terminology normalization, echo detection/AEC, transcript de-duplication | Preserve source and settings where safe; default destructive transforms off; immutable raw result remains available | Full source/raw/quality tests before any enabled transformation |
| Record-only mode, queue recovery, diagnostics, notifications | Preserve and repair around Sawti-owned storage/worker contracts | G2/G4 crash, recovery and safe diagnostics gates |
| Live captions / streaming models | Keep code; no Alpha/core 1.0 production control or startup model prewarm | Re-enable only after separate performance/privacy/accuracy qualification |
| Claude CLI / OpenAI-compatible provider generation | Keep source where license/build graph permits; provider-free default composition; no content is sent in core workflow | Any future enabled provider must pass its full local-content threat review and UI consent; no paid provider is required by 1.0 |
| Debug/automation HTTP server and `mt-cli` | Preserve developer tooling source; unavailable in product core; no external AcademiaOS connection | Full API surface review and auth/limits tests before any production listener can be exposed |
| Update checker, Homebrew casks and release workflows | Reconfigure for Sawti-owned identity/destinations before release; upstream targets remain disabled | P0.2 identity and P7 package/license/signature gates |
| Transcript text/Markdown generation | Preserve formatters as export adapters; create immutable raw transcript/run storage independently | Alpha full-text export and G3 round-trip/source-hash checks |

## Baseline defects and unresolved limits

- Product capture is still in-process. A throwaway command-line helper passed mic-only launch, host-granted TCC, pipe control, WAV persistence and forced teardown when signed with the host's code-signing identifier. A helper with a distinct app bundle ID did not complete the permission flow in the bounded probe; production integration and app-audio capture remain unverified.
- Issue #778 reports first mic start hanging; issue #790 reports tests writing real application data. Both are active implementation risks.
- Capture callbacks currently have write paths whose return/error accounting requires hardening. Do not equate successful tap creation with delivered, persisted audio.
- App-level process capture does not prove browser-tab isolation. No claim of capturing only a particular Meet tab is allowed.
- macOS 26.6.2's host has M2/8 GB, but is MacBook Air, not the stated Pro. Performance/thermals for the Pro remain unverified.
- Third-party notices and dependency pins need reconciliation before redistribution, particularly FluidAudio binary subdependencies.
