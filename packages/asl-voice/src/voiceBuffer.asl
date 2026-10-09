(module aslVoice/voiceBuffer
  :x [VoiceBufferConfig VoiceBufferState VoiceBufferResult
      voiceBufferCreate voiceBufferStepFrame isUtteranceSettled?]
  :i [])

(schema VoiceBufferConfig
  (:f sampleRate I64)
  (:f preRollFrames I64)
  (:f speechActivationFrames I64)
  (:f silenceHangoverFrames I64))

(schema VoiceBufferState
  (:f isUtteranceActive Bool)
  (:f preRollBuffer (List F64))
  (:f accumulatedSamples (List F64))
  (:f speechConsecutiveFrames I64)
  (:f silenceConsecutiveFrames I64)
  (:f totalFramesStreamed I64))

(schema VoiceBufferResult
  (:f isUtteranceActive Bool)
  (:f actionKind Str)
  (:f settledSamples (List F64)))

fn voiceBufferCreate cfg: VoiceBufferConfig -> VoiceBufferState
  (VoiceBufferState
    :isUtteranceActive false
    :preRollBuffer (list)
    :accumulatedSamples (list)
    :speechConsecutiveFrames 0
    :silenceConsecutiveFrames 0
    :totalFramesStreamed 0)

fn voiceBufferStepFrame cfg: VoiceBufferConfig st: VoiceBufferState frameSamples: (List F64) isSpeech: Bool -> (Pair VoiceBufferState VoiceBufferResult)
  (let [(total (+ st.totalFramesStreamed 1))
        (active st.isUtteranceActive)
        (actFrames cfg.speechActivationFrames)
        (hangoverFrames cfg.silenceHangoverFrames)]
    (if (not active)
      (if isSpeech
        (let [(speechCount (+ st.speechConsecutiveFrames 1))]
          (if (>= speechCount actFrames)
            (let [(initialSamples (listAppend st.preRollBuffer frameSamples))
                  (nextSt (VoiceBufferState
                            :isUtteranceActive true
                            :preRollBuffer (list)
                            :accumulatedSamples initialSamples
                            :speechConsecutiveFrames speechCount
                            :silenceConsecutiveFrames 0
                            :totalFramesStreamed total))
                  (res (VoiceBufferResult :isUtteranceActive true :actionKind "speech-started" :settledSamples (list)))]
              (pair nextSt res))
            (let [(nextPre (listAppend st.preRollBuffer frameSamples))
                  (nextSt (VoiceBufferState
                            :isUtteranceActive false
                            :preRollBuffer nextPre
                            :accumulatedSamples (list)
                            :speechConsecutiveFrames speechCount
                            :silenceConsecutiveFrames 0
                            :totalFramesStreamed total))
                  (res (VoiceBufferResult :isUtteranceActive false :actionKind "silence-idle" :settledSamples (list)))]
              (pair nextSt res))))
        (let [(nextPre (listAppend st.preRollBuffer frameSamples))
              (nextSt (VoiceBufferState
                        :isUtteranceActive false
                        :preRollBuffer nextPre
                        :accumulatedSamples (list)
                        :speechConsecutiveFrames 0
                        :silenceConsecutiveFrames (+ st.silenceConsecutiveFrames 1)
                        :totalFramesStreamed total))
              (res (VoiceBufferResult :isUtteranceActive false :actionKind "silence-idle" :settledSamples (list)))]
          (pair nextSt res)))
      (if isSpeech
        (let [(newSamples (listAppend st.accumulatedSamples frameSamples))
              (nextSt (VoiceBufferState
                        :isUtteranceActive true
                        :preRollBuffer (list)
                        :accumulatedSamples newSamples
                        :speechConsecutiveFrames (+ st.speechConsecutiveFrames 1)
                        :silenceConsecutiveFrames 0
                        :totalFramesStreamed total))
              (res (VoiceBufferResult :isUtteranceActive true :actionKind "collecting-speech" :settledSamples (list)))]
          (pair nextSt res))
        (let [(silenceCount (+ st.silenceConsecutiveFrames 1))]
          (if (>= silenceCount hangoverFrames)
            (let [(settled st.accumulatedSamples)
                  (nextSt (VoiceBufferState
                            :isUtteranceActive false
                            :preRollBuffer (list)
                            :accumulatedSamples (list)
                            :speechConsecutiveFrames 0
                            :silenceConsecutiveFrames 0
                            :totalFramesStreamed total))
                  (res (VoiceBufferResult :isUtteranceActive false :actionKind "utterance-settled" :settledSamples settled))]
              (pair nextSt res))
            (let [(newSamples (listAppend st.accumulatedSamples frameSamples))
                  (nextSt (with st :isUtteranceActive true :preRollBuffer (list) :accumulatedSamples newSamples :silenceConsecutiveFrames silenceCount :totalFramesStreamed total))
                  (res (VoiceBufferResult :isUtteranceActive true :actionKind "collecting-speech" :settledSamples (list)))]
              (pair nextSt res)))))))

fn isUtteranceSettled? res: VoiceBufferResult -> Bool
  (= res.actionKind "utterance-settled")
