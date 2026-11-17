# Speech-to-Text

Owns dictation: hold `Option + Space` in any app, release to insert the transcript.
Code is in `yen-terminal/overlays/macos/Sources/Features/Dictation/`; `DictationController` orchestrates, `DictationCaptureSessionCoordinator` owns session lifecycle, and `DictationInsertionCoordinator` owns target capture, validation, and delivery.

## Platform Policy

| macOS | Recognizer | Session limit |
|-------|------------|---------------|
| 26+ (recommended) | `SpeechAnalyzer` with `DictationTranscriber`, on-device after language assets install | None from YEN; Apple can still end a session on an input, asset or resource error |
| 13–25 (supported) | `SFSpeechRecognizer`, on-device when Apple reports support, otherwise Apple's service | YEN stops at 60 seconds and inserts what it has; release and re-press to continue |

The pre-26 path is a supported runtime path, not cleanup debt.
If `SpeechAnalyzer` reports hard unavailability at runtime, YEN falls back to the legacy recognizer, including its 60-second limit and on-device availability rules.
YEN runs no speech service and never receives audio or transcripts.

**Public claims.** Say what the public APIs guarantee: Apple frameworks, no YEN service, no API key, no added binary size, language support that follows macOS and the installed assets.
Never claim an accuracy figure, a private model architecture, a daemon topology, or "unlimited" duration, and never justify the 60-second timer with undocumented Apple behavior; it is YEN's own safeguard.

## Session Contract

States: `idle -> starting -> listening -> stopping -> inserting -> idle`, with explicit `failed -> idle` branches.

- `onReady` is the only entry to `listening`: locale and model work, `prepareToAnalyze(in:)`, tap installation and `AVAudioEngine.start()` all finish first. Releasing the key during startup cancels the pending start, and the overlay never appears.
- Normal stops (key release, legacy timeout, pause) insert only the recognizer's final result. Partial text is used only for failure stops (recognizer error, watchdog, forced reset) or a `SpeechAnalyzer` stop that finalized with an error.
- Recognizers return an explicit stop payload with separate `finalText` and `fallbackText`; the controller never infers "final" from the last preview string.
- Insertions are serialized in completion order so a stop-and-restart cannot cancel a finished transcript; a hard reset bumps the queue epoch and drops stale work.
- A completed task clears the queue only if it still owns the tail, restoring immediate insertion when translation is disabled.
- A stop watchdog force-resets a wedged finalization.
- Each session logs `session`, `state`, `stop_cause`, `fallback_used`, the recognizer, and `key_up_to_insert_ms` to stdout through `print()`.

**`SpeechAnalyzer` finalization.** [CRITICAL] `finalizeAndFinishThroughEndOfInput()` guarantees results are published, not that `resultsTask` has drained them.
Never call `deliverFinalResult()` from the finalization task: its `reset()` cancels `resultsTask` and drops buffered final segments, which is how transcripts were clipped.
Deliver only from `resultsTask` completion, the short-utterance path (`resultsTaskCompleted`, set when the stream ends before key release), or the 5-second safety timeout.
Snapshot the active analyzer before launching the finalization task, and finish every analyzer session explicitly, or its result stream stays open.

**Startup guards.** Authorization decisions, abort cleanup, and recognizer callbacks have separate controller methods.
A permission reply must still match the active session before it can start capture or abort that session.
Model prepare times out at 20s and install at 180s; a stalled asset reservation is released and retried once.
A microphone conversion failure stops the session through the recoverable error path, keeps the last partial, and selects the legacy recognizer for the next session.
Result-stream errors surface through recognizer error callbacks, never only the console.
There is no eager init-time warm-up; it front-loads launch latency and shows "listening" before capture is live.

**Legacy recognizer.** Shutdown keeps both `request.endAudio()` and `task.finish()`; removing either clips the last partial.
It refreshes its locale when `Locale.current` changed since the last session and on `NSLocale.currentLocaleDidChangeNotification`, deferring while a session is active.

**Measured, left alone.** The converter uses `primeMethod = .none`, and a stop-path measurement found no frames after the first pass, so there is no drain loop.
The macOS 27 SDK includes `AnalyzerInputConverter` and `CaptureInputSequenceProvider`, but YEN still uses its existing converter and capture pipeline to support older systems.

## Insertion

1. If macOS Secure Input is active, write nothing to the pasteboard, insert nothing, and post a recovery notification. This check stays above the pasteboard write.
2. After translation, snapshot the pasteboard only for a valid local target, then put the final text on the clipboard.
3. YEN focused with a terminal surface: `SurfaceView.paste(_:)`, so palette or file-browser fields never receive dictation. YEN focused otherwise: `paste:` through the responder chain.
4. Another app focused: `DictationPasteExecutor` posts one Cmd + V pair from a reusable `CGEventSource(.privateState)`; `.combinedSessionState` would leak the held Option key into Option + Cmd + V.

Cross-app delivery is validated against the target captured at stop time:

- A readable focused element must still be the same element.
- A process-only capture (no readable element) is allowed only while the same PID is frontmost and YEN is inactive.
- The frontmost PID is re-checked immediately before the global `.cghidEventTap` post; that narrows the race but cannot bind the post to a PID.
- If the synthetic event cannot be created, the transcript stays on the clipboard with a "press Cmd + V" notification.

Local targets are checked before snapshot capture and again after the clipboard write, immediately before paste.
A failed paste reports manual recovery once and keeps the transcript on the clipboard.
Clipboard restore happens only after successful in-app paste (0.3s, guarded by `changeCount` so a newer copy wins).
After cross-app paste the transcript stays on the clipboard, because delivery cannot be proven.

## Hotkey, Overlay and Menu

`DictationHotKey` uses a session-level `CGEventTap`, not Carbon hot keys, so it consumes the event before any app sees it.
It requires exact Option + Space, consumes every keyDown including repeats (otherwise the terminal bell rings), stops when Option is released first, and re-enables the tap if the system disables it.
"Pause Dictation" does not release the tap.

The overlay is a non-activating, click-through `NSPanel` at `.statusBar` level that joins all spaces, centered on the display under the pointer.
It shows `Listening...` with a live waveform (amplitude at most 15 Hz, redraw at most 30 fps, phase frozen under Reduce Motion), then `Processing...` from the moment stop begins until insertion ends.
Optional Live Transcript Preview shows the newest 280 characters, drops whitespace and duplicate frames, coalesces repaints to one per 0.12s, and is never insertion-authoritative.
`DictationLivePreviewController` owns the normalized display cache, throttling, and pending-frame cancellation.
The session controller keeps the raw partial for finalization; each deferred frame rechecks the current preview preference and stopping state.
A partial that returns to the displayed text cancels any superseded queued frame.
VoiceOver sees one updating `Dictation` element.
A generation counter stops a late fade-out from hiding a new session.
Startup and local-speech failures never show the overlay; recovery lives in the menu and notifications.

The menu bar item blinks `record.circle` while recording (not a microphone, which macOS already shows) and is a template `waveform` when idle under Launch at Login.
Its menu shows the state (`enabled`, `paused`, `blocked`, pending login approval), the fixed shortcut, pause and resume, and recovery actions for each permission, sound input, and the local speech service.

## Permissions

Accessibility (hotkey), Microphone and Speech Recognition are required.
`DictationPermissionController` owns authorization, permission snapshots, polling, and background recovery delivery.
`DictationController` retains session teardown and foreground recovery presentation.
Onboarding and Settings > Dictation > Permissions show live status; Microphone and Speech trigger the native prompt first, and Accessibility is requested only from an explicit Grant.
A hotkey press never raises a permission prompt; it posts a non-modal recovery notification.
The permission monitor ticks every 4s (0.6s tolerance); a revocation during capture or finalization tears the session down, while one at idle only updates the blocked state without dropping an insertion still in flight.
Deep links prefer `Privacy_Accessibility`, `Privacy_Microphone` and `Privacy_SpeechRecognition`, with fallbacks for older releases.

## Translate-on-Dictate (macOS 26+)

Off by default; Apple's `Translation` framework runs on the final transcript.
The source language is the recognizer locale for that session, everywhere: Settings target options, asset preparation and stop-time translation never consult a second detector or `Locale.current`.
Stop-time translation runs only when the pair is already installed.
Missing pairs are prepared only by a Settings-owned `translationTask` while Settings is frontmost; background dictation never shows Translation UI.
Any failure, timeout, missing asset or unsupported pair inserts the original transcript.

## Microphone Selection

`AVAudioInputNode` follows the system default input unless told otherwise.
YEN enumerates Core Audio HAL input devices (aggregate and virtual included, no permission needed) and persists the choice as a device UID in `com.yenchat.yen.dictationSelectedInputDeviceUID`; no value means System Default.
`AudioObjectID` is never persisted.
`DictationInputDeviceBinder.apply(to:)` sets the device before the engine's format is read and confirms it by reading `deviceID` back; System Default skips the call so macOS keeps tracking the default.
A missing or rejected device falls back to the default and records `fallbackReason`, which both recognizers must expose.
A device change mid-session stops with `RecognizerError.audioDeviceChanged` instead of splicing in another microphone; a picker change applies to the next session.

[CRITICAL] `SettingsController.dictationInputDeviceOptions` is seeded eagerly by `makeDictationInputDeviceOptions()`.
Left empty for the row's `.onAppear` to fill, the Microphone row never renders.

## Design Decisions

- **`DictationTranscriber`, not `SpeechTranscriber`.** It shares the keyboard-dictation model, formats punctuation and capitalization for field insertion, covers the broader legacy locale set, and keeps one recognizer path whose fixes are already proven. `SpeechTranscriber`'s advantage was measured on far-field long-form audio; switch only for real meeting transcription, and only after a hardware A/B on short hold-to-talk utterances.
- **Assets.** Resolve the locale with `DictationTranscriber.supportedLocale(equivalentTo:)`, request assets through `AssetInventory`, and start capture only when they are ready; setup state goes to status surfaces, never transcript text.
- **No voice activity detection.** Hold-to-talk stays the default for an explicit privacy boundary; `SpeechDetector` would need an opt-in setting, debounce, and false-trigger measurement first.
- **Audio tap API.** `installTap(onBus:bufferSize:format:block:)` is deprecated in macOS 27. The macOS 27 SDK includes `installAudioTap`, but `DictationAudioEngineTap` still uses the legacy API for both recognizers.
  Any migration must retain the older-system fallback, single-tap ownership, and live-matrix verification; active work belongs in `_docs/todos.md`.

## Verification

Automated coverage drives the coordinator and controller headlessly: short utterances, sessions past 60 seconds, re-press during finalization, insertion ordering, final-only versus fallback insertion, the watchdog, and revocation at each phase.
Real TCC timing and live target apps need the manual matrix: `scripts/native/02-dictation-live-matrix.sh capture`, the runbook `_docs/09-quality.md`, then `... report`.
Run it from Terminal.app or iTerm2 with `/Applications/YEN.app` quit, because the always-on hotkey tap and the TCC record are shared.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Option + Space does nothing | Check the blocked state in the menu bar item, grant Accessibility, and look for a conflict in Settings > Shortcuts |
| No microphone or speech prompt, or YEN missing from the list | Use Grant to trigger the native prompt; in a release build verify entitlements with `codesign -d --entitlements -` |
| Dictation shows a local speech warning | Follow the detail under Settings > Dictation > Permissions; the status refreshes every few seconds while the pane is open; before macOS 26, System Keyboard Dictation may be off |
| Launch at Login stays pending | Approve YEN in System Settings > General > Login Items |
| Stops at 60 seconds | Expected whenever the legacy recognizer is active, including fallback on macOS 26+ |
| Bell rings while holding the key | The hotkey stopped consuming key repeats |
