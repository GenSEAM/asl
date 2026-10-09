(module aslVoice/roomNoise :x [NoiseAdvisorConfig NoiseAdvisorState makeNoiseAdvisor makeInitialNoiseAdvisorState computeNoiseAdvice] :i [])

(schema NoiseAdvisorConfig (:f noisyThresholdDb F64) (:f quietThresholdDb F64) (:f minFloorDb F64) (:f maxFloorDb F64) (:f dwellFrames I64))

(schema NoiseAdvisorState (:f currentFloorDb F64) (:f isNoisy Bool) (:f persistenceCount I64) (:f adviceCode Str) (:f adviceMessage Str))

fn clampFloor val: F64 minDb: F64 maxDb: F64 -> F64
  (if (< val minDb) minDb (if (> val maxDb) maxDb val))

fn updateRunningFloor curr: F64 frameDb: F64 minDb: F64 maxDb: F64 -> F64
  (let [(raw (+ (* curr 0.95) (* frameDb 0.05)))] (clampFloor raw minDb maxDb))

fn makeNoiseAdvisor noisyDb: F64 quietDb: F64 -> NoiseAdvisorConfig
  (NoiseAdvisorConfig :noisyThresholdDb noisyDb :quietThresholdDb quietDb :minFloorDb -70.0 :maxFloorDb -25.0 :dwellFrames 5)

fn makeInitialNoiseAdvisorState -> NoiseAdvisorState
  (NoiseAdvisorState :currentFloorDb -55.0 :isNoisy false :persistenceCount 0 :adviceCode "OK" :adviceMessage "Room acoustic environment is optimal")

fn computeNoiseAdvice cfg: NoiseAdvisorConfig st: NoiseAdvisorState frameDb: F64 -> NoiseAdvisorState
  (let [(minFloor cfg.minFloorDb) (maxFloor cfg.maxFloorDb) (dwell cfg.dwellFrames) (isSilent (<= frameDb minFloor)) (newFloor (if isSilent minFloor (updateRunningFloor st.currentFloorDb frameDb minFloor maxFloor)))] (if isSilent (let [(newCount (+ st.persistenceCount 1))] (if (>= newCount dwell) (NoiseAdvisorState :currentFloorDb minFloor :isNoisy false :persistenceCount newCount :adviceCode "MIC_MUTED_OR_DEAD" :adviceMessage "Microphone input is completely silent or disconnected") (with st :currentFloorDb newFloor :isNoisy false :persistenceCount newCount))) (if st.isNoisy (if (< frameDb cfg.quietThresholdDb) (let [(newCount (+ st.persistenceCount 1))] (if (>= newCount dwell) (NoiseAdvisorState :currentFloorDb newFloor :isNoisy false :persistenceCount 0 :adviceCode "OK" :adviceMessage "Room acoustic environment is optimal") (NoiseAdvisorState :currentFloorDb newFloor :isNoisy true :persistenceCount newCount :adviceCode "ROOM_TOO_NOISY" :adviceMessage "Ambient room noise exceeds recommended acoustic threshold"))) (NoiseAdvisorState :currentFloorDb newFloor :isNoisy true :persistenceCount 0 :adviceCode "ROOM_TOO_NOISY" :adviceMessage "Ambient room noise exceeds recommended acoustic threshold")) (if (>= frameDb cfg.noisyThresholdDb) (let [(newCount (+ st.persistenceCount 1))] (if (>= newCount dwell) (NoiseAdvisorState :currentFloorDb newFloor :isNoisy true :persistenceCount 0 :adviceCode "ROOM_TOO_NOISY" :adviceMessage "Ambient room noise exceeds recommended acoustic threshold") (NoiseAdvisorState :currentFloorDb newFloor :isNoisy false :persistenceCount newCount :adviceCode "OK" :adviceMessage "Room acoustic environment is optimal"))) (NoiseAdvisorState :currentFloorDb newFloor :isNoisy false :persistenceCount 0 :adviceCode "OK" :adviceMessage "Room acoustic environment is optimal")))))
