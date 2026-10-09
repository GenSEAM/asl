(module aslVoice/tests/voiceBufferTest
  :x [testVoiceBufferHysteresisAndHangover testBargeInDetection runTests]
  :i [(voice/voiceBuffer :a vb)
      (voice/conversationalContext :a cc)])

fn testVoiceBufferHysteresisAndHangover -> Bool
  (let [(cfg (vb/VoiceBufferConfig :sampleRate 16000 :preRollFrames 5 :speechActivationFrames 3 :silenceHangoverFrames 4))
        (st0 (vb/voiceBufferCreate cfg))
        (f1 (list 0.1 0.2))
        (r1 (vb/voiceBufferStepFrame cfg st0 f1 true))
        (st1 (pairFirst r1))
        (r2 (vb/voiceBufferStepFrame cfg st1 f1 true))
        (st2 (pairFirst r2))
        (r3 (vb/voiceBufferStepFrame cfg st2 f1 true))
        (st3 (pairFirst r3))
        (res3 (pairSecond r3))
        (r4 (vb/voiceBufferStepFrame cfg st3 f1 true))
        (st4 (pairFirst r4))
        (r5 (vb/voiceBufferStepFrame cfg st4 f1 false))
        (st5 (pairFirst r5))
        (r6 (vb/voiceBufferStepFrame cfg st5 f1 false))
        (st6 (pairFirst r6))
        (r7 (vb/voiceBufferStepFrame cfg st6 f1 false))
        (st7 (pairFirst r7))
        (r8 (vb/voiceBufferStepFrame cfg st7 f1 false))
        (st8 (pairFirst r8))
        (res8 (pairSecond r8))]
    (assert st3.isUtteranceActive "Frame 3 activates utterance (hysteresis)")
    (assert (= res3.actionKind "speech-started") "Action kind is speech-started on activation")
    (assert st4.isUtteranceActive "Frame 4 continues speech")
    (assert st7.isUtteranceActive "Frame 7 still in hangover window")
    (assert (vb/isUtteranceSettled? res8) "Frame 8 settles utterance after silence hangover")
    (assert (> (listLength res8.settledSamples) 0) "Settled samples returned")
    (assert (not st8.isUtteranceActive) "State resets to inactive after settlement")
    true)

fn testBargeInDetection -> Bool
  (let [(ctx (cc/conversationalContextCreate "authorized-user"))
        (c1 (cc/checkBargeInInterrupt ctx false true))
        (b1 (pairSecond c1))
        (c2 (cc/checkBargeInInterrupt ctx true true))
        (b2 (pairSecond c2))]
    (assert (not b1) "No barge-in when system audio is idle")
    (assert b2 "Barge-in detected when system audio is playing")
    true)

fn runTests -> Bool
  (do
    (assert (testVoiceBufferHysteresisAndHangover) "Voice buffer hysteresis and hangover must pass")
    (assert (testBargeInDetection) "Barge-in detection must pass")
    true)
