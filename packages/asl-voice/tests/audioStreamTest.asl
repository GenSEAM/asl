(module aslVoice/tests/audioStreamTest :x [runTests testMakeAudioStream testStreamWritePcm testStreamRingOverflow testStreamReadWindow testStreamIsFull] :i [(voice/audioStream :a as)])

fn testMakeAudioStream -> Bool
  (let [(st (as/makeAudioStream 512 16000))] (assert (= st.capacity 512) "Capacity must equal 512") (assert (= st.sampleRate 16000) "Sample rate must equal 16000") (assert (= (as/streamBufferSize st) 0) "Initial buffer size must equal 0") (assert (not (as/streamIsFull? st)) "Initial buffer must not be full") true)

fn testStreamWritePcm -> Bool
  (let [(st0 (as/makeAudioStream 10 16000)) (chunk1 (list 0.1 0.2 0.3)) (st1 (as/streamWritePcm st0 chunk1)) (chunk2 (list 0.4 0.5)) (st2 (as/streamWritePcm st1 chunk2))] (assert (= (as/streamBufferSize st1) 3) "Buffer size after first write must equal 3") (assert (= st1.totalWritten 3) "Total written after first write must equal 3") (assert (= (as/streamBufferSize st2) 5) "Buffer size after second write must equal 5") (assert (= st2.totalWritten 5) "Total written after second write must equal 5") true)

fn testStreamRingOverflow -> Bool
  (let [(st0 (as/makeAudioStream 4 16000)) (st1 (as/streamWritePcm st0 (list 1.0 2.0 3.0))) (st2 (as/streamWritePcm st1 (list 4.0 5.0))) (win (as/streamReadWindow st2 4))] (assert (not (as/streamIsFull? st1)) "st1 must not be full before overflow") (assert (as/streamIsFull? st2) "st2 must be full after overflow") (assert (= (as/streamBufferSize st2) 4) "Buffer size must clamp to capacity 4") (assert (= st2.totalWritten 5) "Total written must preserve cumulative count 5") (assert (= (listLength win) 4) "Window length must equal 4") (let [(h1 (optionOr (listHead win) 0.0)) (h2 (optionOr (listHead (optionOr (listTail win) (list))) 0.0))] (assert (= h1 2.0) "First retained element must be 2.0") (assert (= h2 3.0) "Second retained element must be 3.0") true))

fn testStreamReadWindow -> Bool
  (let [(st0 (as/makeAudioStream 8 16000)) (st1 (as/streamWritePcm st0 (list 1.0 2.0 3.0 4.0 5.0))) (w3 (as/streamReadWindow st1 3)) (w10 (as/streamReadWindow st1 10)) (w0 (as/streamReadWindow st1 0))] (assert (= (listLength w3) 3) "Read window 3 must return 3 samples") (assert (= (listLength w10) 5) "Read window exceeding buffer size must clamp to current size 5") (assert (listEmpty? w0) "Read window of size 0 must return empty list") true)

fn testStreamIsFull -> Bool
  (let [(st0 (as/makeAudioStream 3 16000)) (st1 (as/streamWritePcm st0 (list 0.1 0.2 0.3))) (st2 (as/streamWritePcm st1 (list 0.4)))] (assert (not (as/streamIsFull? st0)) "Empty stream must not be full") (assert (as/streamIsFull? st1) "Stream matching capacity must be full") (assert (as/streamIsFull? st2) "Stream after overflow must remain full") (assert (= (as/streamBufferSize st2) 3) "Overflowed stream size must remain 3") true)

fn runTests -> Bool
  (do (assert (testMakeAudioStream) "test-make-audio-stream must pass") (assert (testStreamWritePcm) "test-stream-write-pcm must pass") (assert (testStreamRingOverflow) "test-stream-ring-overflow must pass") (assert (testStreamReadWindow) "test-stream-read-window must pass") (assert (testStreamIsFull) "test-stream-is-full must pass") true)
