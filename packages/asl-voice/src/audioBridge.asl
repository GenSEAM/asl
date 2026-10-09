(module aslVoice/audioBridge :x [AudioBridgeConfig BridgeAudioChunk AudioBridgeState makeAudioBridgeConfig makeAudioChunk initAudioBridge ingestAudioChunk isQuietEdgeDetected? drainSpeechWindow renderBridgeTelemetryAsn] :i [(asl-text/string :a s)])

(schema AudioBridgeConfig (:f sampleRate I64) (:f frameDurationMs I64) (:f ringCapacityChunks I64) (:f speechEnergyThreshold F64))

(schema BridgeAudioChunk (:f chunkId Str) (:f samplesCount I64) (:f energy F64) (:f isSpeech Bool) (:f timestampMs I64))

(schema AudioBridgeState (:f config AudioBridgeConfig) (:f ringChunks (List BridgeAudioChunk)) (:f isRecording Bool) (:f totalIngestedChunks I64) (:f consecutiveSpeechChunks I64) (:f consecutiveSilenceChunks I64))

fn makeAudioBridgeConfig sampleRate: I64 frameDurMs: I64 cap: I64 threshold: F64 -> AudioBridgeConfig
  (AudioBridgeConfig :sampleRate sampleRate :frameDurationMs frameDurMs :ringCapacityChunks cap :speechEnergyThreshold threshold)

fn makeAudioChunk id: Str samples: I64 energy: F64 threshold: F64 ts: I64 -> BridgeAudioChunk
  (BridgeAudioChunk :chunkId id :samplesCount samples :energy energy :isSpeech (>= energy threshold) :timestampMs ts)

fn initAudioBridge cfg: AudioBridgeConfig -> AudioBridgeState
  (AudioBridgeState :config cfg :ringChunks (list) :isRecording true :totalIngestedChunks 0 :consecutiveSpeechChunks 0 :consecutiveSilenceChunks 0)

fn ingestAudioChunk bridge: AudioBridgeState chunk: BridgeAudioChunk -> AudioBridgeState
  (let [(cap bridge.config.ringCapacityChunks) (current bridge.ringChunks) (appended (listAppend current (list chunk))) (appendedLen (listLength appended)) (excess (- appendedLen cap)) (retained (if (> excess 0) (optionOr (listSlice appended excess appendedLen) (list)) appended)) (isSp chunk.isSpeech) (newSpRun (if isSp (+ bridge.consecutiveSpeechChunks 1) 0)) (newSilRun (if isSp 0 (+ bridge.consecutiveSilenceChunks 1))) (newTotal (+ bridge.totalIngestedChunks 1))] (with bridge :ringChunks retained :totalIngestedChunks newTotal :consecutiveSpeechChunks newSpRun :consecutiveSilenceChunks newSilRun))

fn isQuietEdgeDetected? bridge: AudioBridgeState silenceThresholdChunks: I64 -> Bool
  (and (>= bridge.consecutiveSilenceChunks silenceThresholdChunks) (> bridge.totalIngestedChunks bridge.consecutiveSilenceChunks))

fn drainSpeechWindow bridge: AudioBridgeState -> (Pair AudioBridgeState (List BridgeAudioChunk))
  (let [(chunks bridge.ringChunks) (cleared (with bridge :ringChunks (list) :consecutiveSpeechChunks 0 :consecutiveSilenceChunks 0))] (pair cleared chunks))

fn renderBridgeTelemetryAsn bridge: AudioBridgeState -> Str
  (let [(cLen (listLength bridge.ringChunks)) (tot (stringFromInt64 bridge.totalIngestedChunks)) (sp (stringFromInt64 bridge.consecutiveSpeechChunks)) (sil (stringFromInt64 bridge.consecutiveSilenceChunks))] (str "(:audio-bridge :buffered-chunks " (stringFromInt64 cLen) " :total-ingested " tot " :speech-run " sp " :silence-run " sil ")"))
