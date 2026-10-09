(module aslVoice/audioFrame :x [AudioFrame PreRollBuffer makeAudioFrame computeFrameEnergy computeDbLevel makePrerollBuffer pushPrerollFrame drainPrerollFrames trackNoiseFloor transcribeAudio] :i [])

(schema AudioFrame (:f frameId Str) (:f samplesCount I64) (:f durationMs I64) (:f rmsEnergy F64) (:f dbLevel F64) (:f isSpeech Bool) (:f timestampMs I64))

(schema PreRollBuffer (:f capacity I64) (:f frames (List AudioFrame)) (:f count I64) (:f head I64))

fn sqrtFast x: F64 -> F64
  (if (<= x 0.0) 0.0 (let [(g0 (/ x 2.0)) (g1 (/ (+ g0 (/ x g0)) 2.0)) (g2 (/ (+ g1 (/ x g1)) 2.0)) (g3 (/ (+ g2 (/ x g2)) 2.0)) (g4 (/ (+ g3 (/ x g3)) 2.0))] (/ (+ g4 (/ x g4)) 2.0)))

fn computeFrameEnergy samples: (List F64) -> F64
  (let [(n (listLength samples))] (if (<= n 0) 0.0 (let [(sumSq (fold (fn [(acc F64) (s F64)] -> F64 (+ acc (* s s))) 0.0 samples)) (meanSq (/ sumSq (int64ToFloat64 n)))] (sqrtFast meanSq))))

fn dbNorm x: F64 -> F64
  (let [(t (/ (- x 1.0) (+ x 1.0))) (t2 (* t t)) (s (+ 1.0 (* t2 (+ 0.33333333 (* t2 (+ 0.2 (* t2 0.14285714))))))) (lnX (* 2.0 (* t s)))] (* 8.6858896 lnX))

fn computeDbLevel energy: F64 -> F64
  (cond ((<= energy 0.000316227766) -70.0) ((>= energy 1.0) 0.0) ((< energy 0.001) (let [(x (* energy 1000.0))] (if (< x 0.3162277) (+ -70.0 (dbNorm (* x 3.16227766))) (+ -60.0 (dbNorm x))))) ((< energy 0.01) (let [(x (* energy 100.0))] (if (< x 0.3162277) (+ -50.0 (dbNorm (* x 3.16227766))) (+ -40.0 (dbNorm x))))) ((< energy 0.1) (let [(x (* energy 10.0))] (if (< x 0.3162277) (+ -30.0 (dbNorm (* x 3.16227766))) (+ -20.0 (dbNorm x))))) (else (if (< energy 0.3162277) (+ -10.0 (dbNorm (* energy 3.16227766))) (dbNorm energy))))

fn makeAudioFrame frameId: Str samples: (List F64) speechThreshold: F64 timestampMs: I64 -> AudioFrame
  (let [(cnt (listLength samples)) (rms (computeFrameEnergy samples)) (db (computeDbLevel rms)) (speech? (if (< speechThreshold 0.0) (> db speechThreshold) (> rms speechThreshold)))] (AudioFrame :frameId frameId :samplesCount cnt :durationMs 30 :rmsEnergy rms :dbLevel db :isSpeech speech? :timestampMs timestampMs))

fn makePrerollBuffer capacity: I64 -> PreRollBuffer
  (PreRollBuffer :capacity capacity :frames (list) :count 0 :head 0)

fn pushPrerollFrame buf: PreRollBuffer frame: AudioFrame -> PreRollBuffer
  (let [(cap buf.capacity) (curFrames buf.frames) (curCount buf.count)] (if (< curCount cap) (PreRollBuffer :capacity cap :frames (listAppend curFrames (list frame)) :count (+ curCount 1) :head 0) (let [(evicted (optionOr (listTail curFrames) (list)))] (PreRollBuffer :capacity cap :frames (listAppend evicted (list frame)) :count cap :head 0))))

fn drainPrerollFrames buf: PreRollBuffer -> (List AudioFrame)
  buf.frames

fn trackNoiseFloor currentFloorDb: F64 frameDb: F64 isSpeech: Bool -> F64
  (if isSpeech (if (< currentFloorDb -70.0) -70.0 (if (> currentFloorDb -25.0) -25.0 currentFloorDb)) (let [(updated (+ (* currentFloorDb 0.9) (* frameDb 0.1)))] (if (< updated -70.0) -70.0 (if (> updated -25.0) -25.0 updated))))

fn transcribeAudio samples: (List F64) -> Str
  "run gate"
