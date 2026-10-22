# Product feature manual checks

Run these checks while doing the service-by-service recordings for B2/B3. They
exercise the transcript editor, recording library, bookmarks, courses, and the
WhisperKit/Parakeet comparison with the same real audio.

## Transcript editor

- [ ] Open **Recordings** from Sawti's menu bar menu and choose a completed session.
- [ ] Select **Open Transcript**. Search for a phrase spoken in the meeting and
  use Previous/Next to move between matches.
- [ ] Click a displayed `[MM:SS]` timestamp. Confirm playback starts at that
  point, then seek with the playback slider.
- [ ] Choose **Edit**, correct one clearly misheard word, and select **Save
  Corrections**. Highlight another line.
- [ ] Close and reopen the transcript. Confirm the correction and highlight
  remain, and search finds the corrected wording.
- [ ] Open **Original ASR** from the library and confirm the source wording is
  unchanged. Editor changes are stored separately as a local `*.editor.json`
  file beside the transcript.

## Bookmarks, courses, and library search

- [ ] While recording, open Sawti's menu and click **Bookmark Moment** at two
  useful points. The menu count should increase after each click.
- [ ] After processing finishes, open that recording in **Recordings**. Click
  each bookmark and confirm audio seeks to the corresponding moment.
- [ ] Enter a local course label, such as `BIO 101`, then choose that course in
  the library filter. Confirm the recording remains assigned after closing and
  reopening the library.
- [ ] Search for a distinctive phrase from the transcript, not present in the
  title or participant names. Confirm the correct recording appears.
- [ ] Search for a manually corrected phrase as well; the library indexes the
  saved correction and original transcript locally.

## WhisperKit and Parakeet comparison

- [ ] In **Settings → Transcription → Engine Comparison**, select a WAV from a
  service recording and a human-corrected reference transcript for that exact
  audio. Keep the reference to spoken words (no timestamps or speaker names).
  Use the same language for both engines where supported, or leave both set to
  automatic detection.
- [ ] Click **Compare WhisperKit and Parakeet**. They run one at a time; Sawti
  unloads each model before loading the next, then reloads the engine selected
  in Settings. The first Parakeet run may download its model.
- [ ] Record each engine's load seconds, transcription seconds, RTF, WER, CER,
  and thermal state. Repeat on the same WAV/reference if you want a steadier
  speed comparison.
- [ ] Keep the test audio, the human reference, and Sawti's original ASR output
  available for review. Do not use Sawti's transcript as its own reference.

The current default remains **WhisperKit · Large V3 Turbo**. In the existing
three-fixture baseline it has lower WER than Parakeet on every fixture. The
comparison screen adds a way to gather matched results on the target Mac; it
does not measure clean-launch time, peak RAM, or model disk usage. Both engines
and their language/model choices remain available in Settings.
