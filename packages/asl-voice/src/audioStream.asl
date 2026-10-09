(module aslVoice/audioStream :x [AudioStream makeAudioStream streamWritePcm streamReadWindow streamBufferSize streamIsFull?] :i [])

(schema AudioStream (:f capacity I64) (:f sampleRate I64) (:f samples (List F64)) (:f totalWritten I64))

fn dropSamples n: I64 xs: (List F64) -> (List F64)
  (if (<= n 0) xs (optionOr (listSlice xs n (listLength xs)) (list)))

fn makeAudioStream capacity: I64 sampleRate: I64 -> AudioStream
  (AudioStream :capacity capacity :sampleRate sampleRate :samples (list) :totalWritten 0)

fn streamBufferSize st: AudioStream -> I64
  (listLength st.samples)

fn streamIsFull? st: AudioStream -> Bool
  (>= (listLength st.samples) st.capacity)

fn streamWritePcm st: AudioStream chunk: (List F64) -> AudioStream
  (if (listEmpty? chunk) st (let [(curSamples st.samples) (cap st.capacity) (allSamples (listAppend curSamples chunk)) (allLen (listLength allSamples)) (excess (- allLen cap)) (retained (if (> excess 0) (dropSamples excess allSamples) allSamples)) (newTotal (+ st.totalWritten (listLength chunk)))] (with st :capacity cap :samples retained :totalWritten newTotal)))

fn streamReadWindow st: AudioStream windowSize: I64 -> (List F64)
  (if (<= windowSize 0) (list) (let [(cur st.samples) (curLen (listLength cur))] (if (<= curLen windowSize) cur (dropSamples (- curLen windowSize) cur))))
