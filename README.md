# Sawti

Sawti is an independent macOS transcription application derived from [Meeting Transcriber](https://github.com/pasrom/meeting-transcriber). The project keeps its own app identity, local data paths, development build, and roadmap. Its first internal milestone is focused on preserving recordings and transcripts before adding online-meeting capture.

## Alpha development scope

The current code provides a microphone-only recording route through an in-bundle helper process, on-device transcription through the existing WhisperKit and Parakeet engines, a full transcript viewer, and plain-text export. The engine's original segment text is saved separately before normalization or speaker labeling; the final transcript remains a separate artifact. Transcript and audio files are written with owner-only file permissions.

The helper feasibility probe passed for a disposable app, but Sawti's packaged app has not yet passed live microphone permission, real recording, or spoken-word transcription validation. Treat this checkout as an internal prototype, not a release-ready recorder.

## Local processing and network use

Recording and inference use local macOS audio capture and local models; Sawti does not require a paid transcription API or subscription. The selected model may need to be fetched on first use. Offline inference is only possible after the required model files are present locally and still needs a Sawti-specific validation run. Optional protocol providers remain available, but the default provider is disabled so transcripts are not sent to a summarization service by the core workflow.

## Build

Requires macOS 14.2 or later and the Swift toolchain declared by the package. Build the local development app bundle without fetching the optional echo-cancellation model:

```bash
SAWTI_SKIP_OPTIONAL_MODEL_FETCH=1 ./scripts/run_app.sh --build-only
```

The bundle is created at `app/MeetingTranscriber/.build/MeetingTranscriber-Dev.app`. Use `./scripts/run_app.sh` to build and launch it. macOS may ask for microphone permission when a recording is started. Local self-signed or ad-hoc signatures are for development only and cannot be used for distribution or notarization.

Run the isolated unit and integration suite from the repository root:

```bash
./scripts/test-isolated.sh
```

That suite uses a disposable test home and skips tests that require downloading or loading real ASR/VAD models. It does not qualify actual audio capture, transcription accuracy, or performance.

## Data locations

- App data and recovery recordings: `~/Library/Application Support/Sawti/`
- Default protocol and transcript output: `~/Downloads/Sawti/`
- Logs: `~/Library/Logs/Sawti/`

Sawti does not import or migrate data from an installed Meeting Transcriber app. Original and final transcript files are stored separately when the corresponding output preference is enabled. Use the in-app transcript viewer's **Export Copy…** action to create a user-selected plain-text copy.

## Current limitations

- The in-person microphone flow is implemented but needs a live Sawti-bundle/TCC and spoken-marker test before it can be considered reliable.
- Google Meet, Zoom, and Teams audio capture have not passed Sawti's Beta validation. Existing upstream app-audio mechanisms remain in the codebase; the Alpha helper route is microphone-only.
- The disposable helper used for feasibility is not a substitute for testing the final package signature, clean-install permission prompt, or macOS permission persistence after rebuilds.
- Runtime memory, thermal behavior, long-session completeness, transcript accuracy, and offline operation on an M2 Mac with 8 GB RAM remain unmeasured.
- AcademiaOS integration is deferred until Sawti is dependable as an independent application.

See [`docs/validation/VALIDATION.md`](docs/validation/VALIDATION.md) for evidence and pending checks, and [`docs/CAPABILITY_REGISTER.md`](docs/CAPABILITY_REGISTER.md) for the disposition of inherited features. The repository retains the upstream MIT license and notices.
