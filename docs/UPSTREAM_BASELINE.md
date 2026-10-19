# Sawti upstream baseline

Recorded 2026-10-18 for the initial Sawti implementation.

## Selected source

- Upstream: [pasrom/meeting-transcriber](https://github.com/pasrom/meeting-transcriber)
- Sawti working branch: `sawti/dev`
- Base commit: `a4f6af6df2674bc4e18097084a128af469823fab` (`test(app): pin who owns the queue snapshot file`, committed 2026-10-08)
- Upstream `main` observed during setup: the same commit. `v0.8.1` remains an older release and is not the starting point.
- Local Git `origin` fetch URL is upstream. Its push URL is deliberately set to `disabled://sawti-upstream-read-only`, and `push.default` is `nothing`; do not remove that guard as part of ordinary development. No upstream fork or Sawti remote is configured.
- Sawti inherits the repository's MIT license and commit ancestry. Keep the copyright and permission notice, review transitive code/model obligations against the exact assets shipped, and record Sawti-specific attribution additively.

## Source facts confirmed at the pinned commit

| Area | Observed implementation |
|---|---|
| App | Native SwiftUI/AppKit menu-bar app in `app/MeetingTranscriber`; Swift Package Manager; Swift 6 language mode |
| Capture | `tools/audiotap` AudioTapLib using Core Audio process taps for app audio and AVAudioEngine for microphone audio; the app currently calls it in-process |
| Platform declarations | Both main SPM manifests declare macOS 14; actual capture code guards macOS 14.2 APIs |
| ASR | WhisperKit 1.1.0 and FluidAudio 0.17.4 are pinned in `app/MeetingTranscriber/Package.resolved`; the app includes WhisperKit and Parakeet adapters |
| Other ML paths | FluidAudio also supplies VAD and diarization paths; current source and third-party notice must be reconciled before redistribution |
| Storage | Existing recording staging/sidecars and queue snapshots are Meeting Transcriber-owned paths. Sawti must establish independent roots before it creates production data |
| Network-capable code | Model installation/update checking, opt-in live caption paths, automation/debug HTTP routes and optional protocol providers exist in source. They are not presumed disabled merely because a control is hidden |
| Release | `scripts/build_release.sh`, `.github/workflows/release.yml` and `Casks/` contain Meeting Transcriber identity and maintainer-owned release destinations |
| Tests | XCTest, ViewInspector, snapshot tests, integration scripts and hardware/manual lanes exist. Issue #790 documents tests that can write to the real Meeting Transcriber application-support directory |

The app package declares a Swift tools version of 6.2. This host presently exposes only Command Line Tools with Swift 6.0.3. No app build or repository test has been run. Do not lower the manifest version to work around the host.

## Host inventory for feasibility work

Observed with system metadata on 2026-10-18:

- Architecture: `arm64`
- Product: MacBook Air, model identifier `Mac14,2`, Apple M2, 8 GB memory
- macOS: 26.6.2
- Selected developer directory: `/Library/Developer/CommandLineTools`
- Compiler: Apple Swift 6.0.3
- Valid code-signing identities: zero

This machine is an M2/8 GB development host, but it is a MacBook Air rather than the MacBook Pro named in Sawti's qualification requirement. It can support source work and a provisional feasibility probe after the toolchain/signing prerequisites are resolved. It cannot alone certify the intended MacBook Pro's thermal or device-specific behavior. Do not claim the signed-helper/TCC feasibility gate has passed until a stable local signing identity and a Swift 6.2-capable build environment are available and actual audio reaches saved probe files.

## License and release findings to carry forward

- `LICENSE` is MIT and must remain present.
- `THIRD-PARTY-NOTICES.md` claims FluidAudio 0.15.6 in one section while the app lockfile resolves FluidAudio 0.17.4. Its bundled-component inventory must be reconciled against the exact dependency graph and assets before Sawti release; do not copy the notice unchanged as proof of compliance.
- `Package.swift` references a checksum-pinned LocalVQE binary hosted under a maintainer repository. Inspect the actual resolved target graph and license before deciding whether Sawti retains, removes from its product graph, or replaces the optional echo-cancellation path.
- Existing signing/release/Homebrew workflows reference upstream identities and repositories. No Sawti release tag may be pushed or release workflow run until destinations, bundle identity, secrets and publishing steps have been reviewed and made Sawti-owned.

## Verification log

| Check | Result |
|---|---|
| Checkout commit and branch | `a4f6af6df2674bc4e18097084a128af469823fab`, branch `sawti/dev` |
| Working tree at start | Clean |
| Upstream `main` at setup | Same SHA as the selected baseline |
| SPM lock pins | WhisperKit 1.1.0; FluidAudio 0.17.4; exact revisions recorded in the lockfile |
| Repository tests/build | Not run; Swift 6.2 requirement is unmet and issue #790 marks unsafe real-user test writes |
| Helper/TCC signing | Not run; zero valid identities and no Swift 6.2 toolchain |
| Exact target model | Not present on this host; current host is M2 MacBook Air, not the stated Pro |
