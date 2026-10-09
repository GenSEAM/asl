(module asl-audio/vad :x [calculateDbfs computeZcr updateNoiseFloorDb isClickTransient? isVoicedFrame? isSustainFrame? stepVadWithZcr updateBargeInState VadConfig VadState makeInitialVadState] :i [])

(schema VadConfig
  (:f minFloorDb Float64)
  (:f maxFloorDb Float64)
  (:f speechTriggerMarginDb Float64)
  (:f speechReleaseMarginDb Float64)
  (:f minZcr Float64)
  (:f maxZcr Float64)
  (:f transientClickZcr Float64)
  (:f minDwellFrames Int64)
  (:f hangoverFrames Int64))

(schema VadState
  (:f currentFloorDb Float64)
  (:f isSpeechActive Bool)
  (:f consecutiveSpeechFrames Int64)
  (:f silenceHangoverCount Int64)
  (:f totalFramesProcessed Int64)
  (:f lastFrameDbfs Float64)
  (:f lastFrameZcr Float64)
  (:f isBargeInTriggered Bool))

fn makeInitialVadState -> VadState
  (VadState
    :currentFloorDb -55.0
    :isSpeechActive false
    :consecutiveSpeechFrames 0
    :silenceHangoverCount 0
    :totalFramesProcessed 0
    :lastFrameDbfs -70.0
    :lastFrameZcr 0.0
    :isBargeInTriggered false)

fn dbNorm x: Float64 -> Float64
  (let [(t (/ (- x 1.0) (+ x 1.0)))
        (t2 (* t t))
        (s (+ 1.0 (* t2 (+ 0.33333333 (* t2 (+ 0.2 (* t2 0.14285714)))))))
        (lnX (* 2.0 (* t s)))]
    (* 8.6858896 lnX))

fn calculateDbfs energy: Float64 -> Float64
  (cond
    ((<= energy 0.000316227766) -70.0)
    ((>= energy 1.0) 0.0)
    ((< energy 0.001)
      (let [(x (* energy 1000.0))]
        (if (< x 0.3162277) (+ -70.0 (dbNorm (* x 3.16227766))) (+ -60.0 (dbNorm x)))))
    ((< energy 0.01)
      (let [(x (* energy 100.0))]
        (if (< x 0.3162277) (+ -50.0 (dbNorm (* x 3.16227766))) (+ -40.0 (dbNorm x)))))
    ((< energy 0.1)
      (let [(x (* energy 10.0))]
        (if (< x 0.3162277) (+ -30.0 (dbNorm (* x 3.16227766))) (+ -20.0 (dbNorm x)))))
    (else
      (if (< energy 0.3162277) (+ -10.0 (dbNorm (* energy 3.16227766))) (dbNorm energy))))

fn computeZcr signChanges: Int64 sampleCount: Int64 -> Float64
  (if (<= sampleCount 1)
    0.0
    (/ (int64ToFloat64 signChanges) (int64ToFloat64 (- sampleCount 1))))

fn updateNoiseFloorDb currentFloor: Float64 frameDbfs: Float64 minFloor: Float64 maxFloor: Float64 isSpeech: Bool -> Float64
  (if isSpeech
    currentFloor
    (let [(alpha (if (> frameDbfs currentFloor) 0.005 0.05))
          (blended (+ (* currentFloor (- 1.0 alpha)) (* frameDbfs alpha)))]
      (if (< blended minFloor)
        minFloor
        (if (> blended maxFloor) maxFloor blended))))

fn isClickTransient? frameDbfs: Float64 zcr: Float64 floorDb: Float64 transientZcrThreshold: Float64 -> Bool
  (if (<= frameDbfs (+ floorDb 15.0))
    false
    (> zcr transientZcrThreshold))

fn isVoicedFrame? frameDbfs: Float64 triggerLevel: Float64 zcr: Float64 minZcr: Float64 maxZcr: Float64 isClick: Bool -> Bool
  (if isClick
    false
    (if (< frameDbfs triggerLevel)
      false
      (if (< zcr minZcr)
        false
        (<= zcr maxZcr))))

fn isSustainFrame? frameDbfs: Float64 releaseLevel: Float64 zcr: Float64 isClick: Bool -> Bool
  (if isClick
    false
    (if (< frameDbfs releaseLevel)
      false
      (<= zcr 0.48)))

fn stepVadWithZcr cfg: VadConfig st: VadState frameDbfs: Float64 zcr: Float64 isTtsPlaying: Bool -> VadState
  (let [(floorDb st.currentFloorDb)
        (triggerLevel (+ floorDb cfg.speechTriggerMarginDb))
        (releaseLevel (+ floorDb cfg.speechReleaseMarginDb))
        (isClick (isClickTransient? frameDbfs zcr floorDb cfg.transientClickZcr))
        (isVoiced (isVoicedFrame? frameDbfs triggerLevel zcr cfg.minZcr cfg.maxZcr isClick))
        (isSustain (isSustainFrame? frameDbfs releaseLevel zcr isClick))
        (currSpeechCount st.consecutiveSpeechFrames)
        (newSpeechCount (if isVoiced (+ currSpeechCount 1) 0))
        (dwellMet (>= newSpeechCount cfg.minDwellFrames))
        (wasActive st.isSpeechActive)
        (isActive (if wasActive
                    (if isSustain true (> st.silenceHangoverCount 0))
                    dwellMet))
        (newHangover (if isActive
                       (if isSustain cfg.hangoverFrames (- st.silenceHangoverCount 1))
                       0))
        (newFloor (updateNoiseFloorDb floorDb frameDbfs cfg.minFloorDb cfg.maxFloorDb isActive))
        (bargeIn (and isTtsPlaying isActive))]
    (VadState
      :currentFloorDb newFloor
      :isSpeechActive isActive
      :consecutiveSpeechFrames newSpeechCount
      :silenceHangoverCount (if (< newHangover 0) 0 newHangover)
      :totalFramesProcessed (+ st.totalFramesProcessed 1)
      :lastFrameDbfs frameDbfs
      :lastFrameZcr zcr
      :isBargeInTriggered bargeIn))

fn updateBargeInState st: VadState isTtsPlaying: Bool userSpoke: Bool -> VadState
  (with st :isBargeInTriggered (and isTtsPlaying userSpoke))
