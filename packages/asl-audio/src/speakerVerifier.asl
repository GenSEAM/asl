(module asl-audio/speakerVerifier :x [dotProduct vectorNorm calculateCosineSimilarity calculateMultiCentroidSimilarity adaptiveThresholdBySnr verifySpeakerEmbedding SpeakerCentroids makeSpeakerCentroids SpeakerVerificationResult verifyCandidateFrame] :i [])

(schema SpeakerCentroids
  (:f nearField (List Float64))
  (:f deskMic (List Float64))
  (:f farField (List Float64)))

(schema SpeakerVerificationResult
  (:f isVerified Bool)
  (:f maxScore Float64)
  (:f adaptiveThreshold Float64)
  (:f matchedCluster String))

fn dotProductLoop a: (List Float64) b: (List Float64) idx: Int64 len: Int64 acc: Float64 -> Float64
  (if (>= idx len)
    acc
    (let [(valA (optionOr (listGet a idx) 0.0))
          (valB (optionOr (listGet b idx) 0.0))]
      (dotProductLoop a b (+ idx 1) len (+ acc (* valA valB)))))

fn dotProduct a: (List Float64) b: (List Float64) -> Float64
  (let [(lenA (listLength a))
        (lenB (listLength b))
        (len (if (< lenA lenB) lenA lenB))]
    (dotProductLoop a b 0 len 0.0))

fn vectorNormLoop v: (List Float64) idx: Int64 len: Int64 acc: Float64 -> Float64
  (if (>= idx len)
    acc
    (let [(val (optionOr (listGet v idx) 0.0))]
      (vectorNormLoop v (+ idx 1) len (+ acc (* val val)))))

fn vectorNorm v: (List Float64) -> Float64
  (let [(len (listLength v))
        (sumSq (vectorNormLoop v 0 len 0.0))]
    (if (<= sumSq 0.000000000001)
      0.0
      (sqrt sumSq)))

fn calculateCosineSimilarity vec1: (List Float64) vec2: (List Float64) -> Float64
  (let [(norm1 (vectorNorm vec1))
        (norm2 (vectorNorm vec2))]
    (if (or (<= norm1 0.00000001) (<= norm2 0.00000001))
      0.0
      (let [(dot (dotProduct vec1 vec2))]
        (let [(sim (/ dot (* norm1 norm2)))]
          (if (> sim 1.0) 1.0 (if (< sim -1.0) -1.0 sim))))))

fn adaptiveThresholdBySnr snrDb: Float64 -> Float64
  (let [(delta (* 0.003 (- snrDb 18.0)))]
    (let [(tau (+ 0.72 delta))]
      (if (< tau 0.68)
        0.68
        (if (> tau 0.76) 0.76 tau))))

fn calculateMultiCentroidSimilarity candidate: (List Float64) centroids: SpeakerCentroids -> Float64
  (let [(sNear (calculateCosineSimilarity candidate centroids.nearField))
        (sDesk (calculateCosineSimilarity candidate centroids.deskMic))
        (sFar (calculateCosineSimilarity candidate centroids.farField))]
    (let [(max1 (if (>= sNear sDesk) sNear sDesk))]
      (if (>= max1 sFar) max1 sFar)))

fn makeSpeakerCentroids near: (List Float64) desk: (List Float64) far: (List Float64) -> SpeakerCentroids
  (SpeakerCentroids :nearField near :deskMic desk :farField far)

fn verifySpeakerEmbedding candidate: (List Float64) centroids: SpeakerCentroids snrDb: Float64 -> SpeakerVerificationResult
  (let [(sNear (calculateCosineSimilarity candidate centroids.nearField))
        (sDesk (calculateCosineSimilarity candidate centroids.deskMic))
        (sFar (calculateCosineSimilarity candidate centroids.farField))
        (tau (adaptiveThresholdBySnr snrDb))]
    (let [(bestCluster (if (and (>= sNear sDesk) (>= sNear sFar))
                          "nearField"
                          (if (>= sDesk sFar) "deskMic" "farField")))]
      (let [(maxScore (if (= bestCluster "nearField")
                        sNear
                        (if (= bestCluster "deskMic") sDesk sFar)))]
        (let [(verified (>= maxScore tau))]
          (SpeakerVerificationResult
            :isVerified verified
            :maxScore maxScore
            :adaptiveThreshold tau
            :matchedCluster bestCluster)))))

fn verifyCandidateFrame candidate: (List Float64) centroids: SpeakerCentroids snrDb: Float64 -> Bool
  (let [(res (verifySpeakerEmbedding candidate centroids snrDb))]
    res.isVerified)
