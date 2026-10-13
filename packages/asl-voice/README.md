# @genseam/asl-voice (ASL Voice Assistant Bridge)

> [!IMPORTANT]
> **Status: Conceptual Schema (`conceptual-schema`)**
> This package defines formal AgentScript data records and protocol types for streaming speech chunks, voice intents, and voice activity detection (VAD). It is a **conceptual/theoretical interface specification**, not a live operating system audio driver. Speech synthesis and intent parsing functions operate on mock data structures without live microphone capture or speaker playback.

Real-time Voice Stream Assistant, 16kHz PCM Audio Bridge, and sub-millisecond Voice Router conceptual schema for AgentScript.

## Features
- **16kHz PCM Audio Streaming Protocol:** Data records and framing schemas for conversational voice agents.
- **Voice Intent Schemas:** Speech-to-intent mappings and data structures.
- **EDDIE Layer 2 Integration:** Connects speech input schemas into consultative clarification and follow-up loops.

## Verification
```asn
;; Run voice schema verification
(:test-voice
  :do "./bin/asl test asl/packages/asl-voice/tests/voiceTest.asl"
  :summary "Verify 16kHz PCM audio streaming records and voice intent schemas")
```

## License
MIT

