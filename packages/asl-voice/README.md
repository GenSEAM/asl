# asl-voice (package `aslVoice`)

ASL records and pure functions for a voice interface, operating on values passed in (PCM sample lists, transcript strings): voice-activity detection by frame energy and zero-crossing rate (`vad`), audio frames, pre-roll and noise floor (`audioFrame`, `audioStream`, `audioBridge`, `roomNoise`), end-of-turn heuristics and burst settling (`endturn`, `voiceSettle`, `voiceBuffer`), transcript clean-up and transliteration (`intentCleaner`, `transliterator`, `heardName`), speaker matching by feature vectors (`speakerMatch`), language detection and TTS engine selection records (`multilingualMatrix`, `ttsEngine`), spoken-output formatting (`aloud`), and a pipeline that steps frames into intents (`voice`, `voicePipeline`, `voiceIntent`, `conversationalContext`, `fastPath`, `harnessProfile`).

Nothing in the package captures from a microphone, plays audio, runs a speech model or reads files; `audioFrame.transcribeAudio` returns the fixed string `"run gate"` whatever samples it gets, and the TTS records do not call an engine. `manifest.asn` marks the package `:status "conceptual-schema"` and `:disposition :dormant`, with the waking condition "Native audio I/O streaming bridge connected via 16kHz PCM duplex session".

Module names use the prefix `aslVoice/`; `manifest.asn` lists the same 21 modules and declares no dependencies. All 21 files in `src/` pass `asl/host/out/asl-host check` (2026-10-14).

## Modules and exports

From the `:x` list in each module header under `src/` (2026-10-14): 21 modules, 167 exported names. Long lists are cut at 18 names; the header of each file has the full list.

- `aslVoice/aloud` (`src/aloud.asl`, 7): `AloudConfig`, `AloudSpeechResult`, `makeAloudConfig`, `stripVisualChrome`, `expandSpokenDurations`, `sanitizeChipForEar`, `formatForEar`.
- `aslVoice/audioBridge` (`src/audioBridge.asl`, 10): `AudioBridgeConfig`, `BridgeAudioChunk`, `AudioBridgeState`, `makeAudioBridgeConfig`, `makeAudioChunk`, `initAudioBridge`, `ingestAudioChunk`, `isQuietEdgeDetected?`, `drainSpeechWindow`, `renderBridgeTelemetryAsn`.
- `aslVoice/audioFrame` (`src/audioFrame.asl`, 10): `AudioFrame`, `PreRollBuffer`, `makeAudioFrame`, `computeFrameEnergy`, `computeDbLevel`, `makePrerollBuffer`, `pushPrerollFrame`, `drainPrerollFrames`, `trackNoiseFloor`, `transcribeAudio`.
- `aslVoice/audioStream` (`src/audioStream.asl`, 6): `AudioStream`, `makeAudioStream`, `streamWritePcm`, `streamReadWindow`, `streamBufferSize`, `streamIsFull?`.
- `aslVoice/conversationalContext` (`src/conversationalContext.asl`, 5): `SpeakerTurn`, `ConversationalContext`, `conversationalContextCreate`, `recordTurn`, `checkBargeInInterrupt`.
- `aslVoice/endturn` (`src/endturn.asl`, 9): `TurnVerdict`, `TurnAnalysis`, `makeTurnAnalysis`, `isDanglingCoordinator?`, `isHesitationParticle?`, `isHangingSubjectPronoun?`, `isDanglingAuxVerb?`, `extractTrailingToken`, `analyzeTurnCompletion`.
- `aslVoice/fastPath` (`src/fastPath.asl`, 3): `isValidAsnInput?`, `buildSymbolLexicon`, `transpileFastPath`.
- `aslVoice/harnessProfile` (`src/harnessProfile.asl`, 14): `HarnessPhoneticAlias`, `HarnessHardwareEndpoint`, `HarnessProfile`, `makePhoneticAlias`, `makeHardwareEndpoint`, `makeDefaultHarnessProfile`, `makeDefaultHynessProfile`, `addPhoneticAlias`, `addHardwareEndpoint`, `resolveHarnessAlias`, `applyHarnessAliases`, `findEndpointByKind`, `formatHarnessProfileAsn`, `formatHynessProfileAsn`.
- `aslVoice/heardName` (`src/heardName.asl`, 4): `NameMatch`, `transliterateCyrillic`, `levenshteinDistance`, `matchHeardName`.
- `aslVoice/intentCleaner` (`src/intentCleaner.asl`, 6): `CleanedIntentResult`, `stripDisfluencies`, `deduplicateConsecutiveTokens`, `repairAsrSlips`, `stripConversationalPreamble`, `cleanVoiceIntent`.
- `aslVoice/multilingualMatrix` (`src/multilingualMatrix.asl`, 6): `LocaleDialect`, `MultilingualConfig`, `LanguageDetectionResult`, `detectLanguageDialect`, `makeMultilingualConfig`, `resolveSpeechEngine`.
- `aslVoice/roomNoise` (`src/roomNoise.asl`, 5): `NoiseAdvisorConfig`, `NoiseAdvisorState`, `makeNoiseAdvisor`, `makeInitialNoiseAdvisorState`, `computeNoiseAdvice`.
- `aslVoice/speakerMatch` (`src/speakerMatch.asl`, 6): `SpeakerProfile`, `SpeakerMatchResult`, `makeSpeakerProfile`, `extractMelFeatures`, `cosineSimilarity`, `verifySpeaker`.
- `aslVoice/transliterator` (`src/transliterator.asl`, 6): `PhoneticRule`, `makePhoneticRules`, `disambiguateHomophones`, `applyCanonicalLexicon`, `emitAsnIntent`, `transliterateVoicePrompt`.
- `aslVoice/ttsEngine` (`src/ttsEngine.asl`, 12): `TtsEngineKind`, `TtsEngineConfig`, `TtsSynthesisJob`, `makeSileroConfig`, `makeKokoroConfig`, `supportsLanguage?`, `selectOptimalEngine`, `createSynthesisJob`, `sileroOnnx`, `kokoroOnnx`, `cloudStream`, `terminalSilent`.
- `aslVoice/vad` (`src/vad.asl`, 13): `VadConfig`, `VadState`, `BargeInEvent`, `makeVadConfig`, `makeInitialVadState`, `computeEnergy`, `computeZcr`, `isSpeechFrame`, `isSpeechFrame?`, `stepVad`, `triggerBargeIn`, `detectVoiceActivity`, `sliceUtteranceFrames`.
- `aslVoice/voice` (`src/voice.asl`, 15): `AudioFormat`, `AudioChunk`, `VoiceFrame`, `VoiceIntent`, `processAudioChunk`, `synthesizeSpeechEvent`, `VoicePipelineConfig`, `VoicePipelineState`, `VoicePipelineResult`, `makeVoicePipelineConfig`, `makeInitialVoicePipelineState`, `pipelineStepFrame`, `pipelineParaphraseIntent`, `pipelineFormatSpokenTts`, `renderTerminalSparkline`.
- `aslVoice/voiceBuffer` (`src/voiceBuffer.asl`, 6): `VoiceBufferConfig`, `VoiceBufferState`, `VoiceBufferResult`, `voiceBufferCreate`, `voiceBufferStepFrame`, `isUtteranceSettled?`.
- `aslVoice/voiceIntent` (`src/voiceIntent.asl`, 3): `dispatchSpeechUtterance`, `bindIntentToInflight`, `formatVoiceIntentAsn`.
- `aslVoice/voicePipeline` (`src/voicePipeline.asl`, 9): `VoicePipelineConfig`, `VoicePipelineState`, `VoicePipelineResult`, `makeVoicePipelineConfig`, `makeInitialVoicePipelineState`, `pipelineStepFrame`, `pipelineParaphraseIntent`, `pipelineFormatSpokenTts`, `renderTerminalSparkline`.
- `aslVoice/voiceSettle` (`src/voiceSettle.asl`, 12): `SettleAction`, `BurstState`, `SettleStepResult`, `makeInitialBurstState`, `ingestTranscriptFragment`, `stepSettleTimer`, `releaseBurstNow`, `ceilingReached`, `timeoutSettled`, `holdOngoing`, `quietEdge`, `instantRelease`.

## Tests

Measured 2026-10-14 with the stage-0 host, run from the directory that contains the `asl/` checkout:

```sh
asl/host/out/asl-host test asl/packages/asl-voice/tests/<file>.asl
```

12 of 12 test files exit 0 (306 assertions and refutations pass in those files).

| File | Result | Detail |
|---|---|---|
| `audioBridgeTest.asl` | pass | 41 assertions, 1 refutations |
| `audioStreamTest.asl` | pass | 27 assertions |
| `endturnSettleAloudTest.asl` | pass | 28 assertions |
| `fastPathTest.asl` | pass | 20 assertions |
| `intentCleanerTest.asl` | pass | 13 assertions |
| `transliteratorTest.asl` | pass | 31 assertions |
| `vadTest.asl` | pass | 22 assertions |
| `voiceBufferTest.asl` | pass | 11 assertions |
| `voiceIntelTest.asl` | pass | 30 assertions |
| `voiceIntentTest.asl` | pass | 29 assertions |
| `voicePipelineTest.asl` | pass | 38 assertions |
| `voiceTest.asl` | pass | 15 assertions |
