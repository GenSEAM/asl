# Phase 17 — Voice Stream Assistant & Real-Time Audio Bridge

## Goal
Build real-time 16kHz linear PCM audio streaming bridge and voice intent router for ASL, integrating with EDDIE Layer 2 Consultative Router with sub-millisecond intent synthesis (<0.025ms), accompanied by an interactive Web Audio waveform recorder cockpit component.

## Acceptance Criteria
- `pytest packages/asl-voice/tests/test_voice.py` passes cleanly.
- `packages/asl-voice/bridges/ts/index.ts` provides complete Web Audio API 16kHz PCM stream capture, playback buffer, and intent mapper.
- Interactive audio waveform component `web/src/components/VoiceAssistant.tsx` created and building cleanly in `web/dist`.
- All 7 repo gates + pytest pass without regression.

## Items

### W1: Pytest Test Suite for ASL Voice (`packages/asl-voice/tests/test_voice.py`)
- Test AudioFormat enumeration, AudioChunk constructor, VoiceFrame serialization.
- Test intent dispatch latency benchmarking (<0.05ms) and EDDIE integration payload validation.
- Failing gate: `pytest packages/asl-voice/tests/test_voice.py -q`

### W2: Voice Bridge TypeScript Engine (`packages/asl-voice/bridges/ts/index.ts`)
- Implement `VoiceStreamBridge` with Web Audio API `AudioContext`, `AudioWorklet`/`ScriptProcessor` PCM downsampling to 16kHz mono, and real-time audio chunking.
- Implement zero-latency intent synthesizer mapping voice commands to ASL S-expression expressions.

### W3: Voice Stream Assistant Component (`web/src/components/VoiceAssistant.tsx`)
- Mount responsive HTML5 Canvas 60fps audio waveform telemetry visualizer.
- Provide interactive Mic toggle, live PCM frame rate (16kHz), latency telemetry (<0.025ms), and voice command execution console.
- Gate: `PATH="/usr/local/bin:$PATH" /usr/local/bin/node web/node_modules/vite/bin/vite.js build web`

### W4: Verification & Gate Conformance
- Run all 7 repo verification gates.
- Verify 0 regressions across all 6 differential compilation targets.
