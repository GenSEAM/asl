(module aslVoice/tests/voiceIntentTest :x [runTests testFormatVoiceIntentAsn testDispatchSpeechUtterance testDispatchPhoneticHomophones testBindIntentToInflight testFastPathPreservation] :i [(voice/voiceIntent :a vi) (voice/fastPath :a fp)])

fn testFormatVoiceIntentAsn -> Bool
  (let [(r1 (vi/formatVoiceIntentAsn "verify voice pipeline" (list "task-claim" "task-settle"))) (r2 (vi/formatVoiceIntentAsn "single action" (list "run-tests")))] (assert (fp/isValidAsnInput? r1) "Formatted intent r1 must be valid balanced ASN") (assert (fp/isValidAsnInput? r2) "Formatted intent r2 must be valid balanced ASN") (assert (stringContains? r1 ":goal \"verify voice pipeline\"") "r1 must contain target goal") (assert (stringContains? r1 ":action-dag [\"task-claim\" \"task-settle\"]") "r1 must contain action DAG") (assert (stringContains? r2 ":action-dag [\"run-tests\"]") "r2 must contain single action") true)

fn testDispatchSpeechUtterance -> Bool
  (let [(res1 (vi/dispatchSpeechUtterance "task claim for worker")) (res2 (vi/dispatchSpeechUtterance "run tests"))] (assert (fp/isValidAsnInput? res1) "Dispatched utterance res1 must be valid ASN") (assert (fp/isValidAsnInput? res2) "Dispatched utterance res2 must be valid ASN") (assert (stringContains? res1 ":action-dag [\"task-claim\"]") "res1 must contain task-claim in action-dag") (assert (stringContains? res2 ":action-dag [\"run-tests\"]") "res2 must contain run-tests in action-dag") true)

fn testDispatchPhoneticHomophones -> Bool
  (let [(res1 (vi/dispatchSpeechUtterance "string start swiss and asl man")) (res2 (vi/dispatchSpeechUtterance "vad config then step vad"))] (assert (fp/isValidAsnInput? res1) "Homophone repaired intent res1 must be valid ASN") (assert (fp/isValidAsnInput? res2) "Homophone repaired intent res2 must be valid ASN") (assert (stringContains? res1 "stringStartsWith?") "res1 must repair string start swiss to stringStartsWith?") (assert (stringContains? res1 "asl-mem") "res1 must repair asl man to asl-mem") (assert (stringContains? res2 "VadConfig") "res2 must repair vad config to VadConfig") (assert (stringContains? res2 "step-vad") "res2 must repair step vad to step-vad") (assert (not (stringContains? res1 "string start swiss")) "res1 must not contain raw phonetic error") true)

fn testBindIntentToInflight -> Bool
  (let [(intent (vi/formatVoiceIntentAsn "execute build" (list "task-spawn"))) (bound1 (vi/bindIntentToInflight "t394-01" intent)) (bound2 (vi/bindIntentToInflight "t394-02" "task-settle"))] (assert (fp/isValidAsnInput? bound1) "Bound in-flight frame bound1 must be valid ASN") (assert (fp/isValidAsnInput? bound2) "Bound in-flight frame bound2 must be valid ASN") (assert (stringContains? bound1 ":task-id \"t394-01\"") "bound1 must contain task ID") (assert (stringContains? bound1 ":status :active") "bound1 must contain active status") (assert (stringContains? bound2 ":task-id \"t394-02\"") "bound2 must contain task ID") (assert (stringContains? bound2 ":intent (:intent :goal \"task-settle\"") "bound2 must auto-wrap raw intent") true)

fn testFastPathPreservation -> Bool
  (let [(rawAsn "(:task :id \"t100\" :priority :high)") (dispatched (vi/dispatchSpeechUtterance rawAsn))] (assert (= dispatched rawAsn) "Pre-structured ASN must bypass transliteration") (assert (fp/isValidAsnInput? dispatched) "Bypassed expression must be valid ASN") true)

fn runTests -> Bool
  (do (assert (testFormatVoiceIntentAsn) "test-format-voice-intent-asn must pass") (assert (testDispatchSpeechUtterance) "test-dispatch-speech-utterance must pass") (assert (testDispatchPhoneticHomophones) "test-dispatch-phonetic-homophones must pass") (assert (testBindIntentToInflight) "test-bind-intent-to-inflight must pass") (assert (testFastPathPreservation) "test-fast-path-preservation must pass") true)
