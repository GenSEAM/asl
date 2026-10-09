(module aslVoice/speakerMatch :x [SpeakerProfile SpeakerMatchResult makeSpeakerProfile extractMelFeatures cosineSimilarity verifySpeaker] :i [])

(schema SpeakerProfile (:f speakerId Str) (:f name Str) (:f embedding (List F64)) (:f threshold F64))

(schema SpeakerMatchResult (:f matched Bool) (:f speakerId Str) (:f confidence F64) (:f distance F64))

fn sqrtApprox x: F64 -> F64
  (if (<= x 0.0) 0.0 (let [(g0 (/ (+ x 1.0) 2.0)) (g1 (/ (+ g0 (/ x g0)) 2.0)) (g2 (/ (+ g1 (/ x g1)) 2.0)) (g3 (/ (+ g2 (/ x g2)) 2.0)) (g4 (/ (+ g3 (/ x g3)) 2.0)) (g5 (/ (+ g4 (/ x g4)) 2.0))] g5))

fn dotProduct a: (List F64) b: (List F64) -> F64
  (if (or (listEmpty? a) (listEmpty? b)) 0.0 (let [(ha (optionOr (listHead a) 0.0)) (hb (optionOr (listHead b) 0.0)) (ta (optionOr (listTail a) (list))) (tb (optionOr (listTail b) (list)))] (+ (* ha hb) (dotProduct ta tb))))

fn normSq v: (List F64) -> F64
  (if (listEmpty? v) 0.0 (let [(h (optionOr (listHead v) 0.0)) (t (optionOr (listTail v) (list)))] (+ (* h h) (normSq t))))

fn cosineSimilarity vecA: (List F64) vecB: (List F64) -> F64
  (let [(na (sqrtApprox (normSq vecA))) (nb (sqrtApprox (normSq vecB))) (denom (* na nb))] (if (<= denom 0.000001) 0.0 (let [(dot (dotProduct vecA vecB)) (sim (/ dot denom))] (if (> sim 1.0) 1.0 (if (< sim -1.0) -1.0 sim)))))

fn makeSpeakerProfile speakerId: Str name: Str embedding: (List F64) threshold: F64 -> SpeakerProfile
  (SpeakerProfile :speakerId speakerId :name name :embedding embedding :threshold threshold)

fn verifySpeaker profile: SpeakerProfile inputEmbedding: (List F64) -> SpeakerMatchResult
  (let [(conf (cosineSimilarity profile.embedding inputEmbedding)) (thresh profile.threshold) (isMatch (>= conf thresh)) (dist (- 1.0 conf))] (SpeakerMatchResult :matched isMatch :speakerId profile.speakerId :confidence conf :distance dist))

fn dropSamples lst: (List F64) n: I64 -> (List F64)
  (if (or (<= n 0) (listEmpty? lst)) lst (dropSamples (optionOr (listTail lst) (list)) (- n 1)))

fn computeBinEnergy samples: (List F64) count: I64 -> F64
  (if (or (<= count 0) (listEmpty? samples)) 0.0 (let [(h (optionOr (listHead samples) 0.0)) (t (optionOr (listTail samples) (list)))] (+ (* h h) (computeBinEnergy t (- count 1)))))

fn extractFilterbankBins samples: (List F64) binsRemaining: I64 binSize: I64 -> (List F64)
  (if (<= binsRemaining 0) (list) (let [(e (computeBinEnergy samples binSize)) (normVal (sqrtApprox e)) (nextSamples (dropSamples samples binSize))] (cons normVal (extractFilterbankBins nextSamples (- binsRemaining 1) binSize))))

fn extractMelFeatures samples: (List F64) -> (List F64)
  (let [(total (listLength samples)) (binSize (if (< total 16) 1 (/ total 16)))] (extractFilterbankBins samples 16 binSize))
