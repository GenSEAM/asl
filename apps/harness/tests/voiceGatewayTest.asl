(module aslHarness/voiceGatewayTest :x [testMakePcmFrame testIngestPcmFrame testIntentClassificationSearch testIntentClassificationAction testGatewayVersion runTests] :i [(voiceGateway :a vg)])

fn testMakePcmFrame -> Bool
  (let [(f (vg/makePcmFrame "pcm-01" true))] (assert (= f.frameId "pcm-01") "Frame ID must match") (assert (= f.sampleRate 16000) "Sample rate must be 16000") (assert (= f.durationMs 160) "Duration must be 160ms") (assert f.isSpeech "Speech flag must be true") true)

fn testIngestPcmFrame -> Bool
  (let [(f (vg/makePcmFrame "pcm-02" true)) (tr (vg/ingestPcmFrame f "найди документацию по bun" "ru" true))] (assert (= tr.frameId "pcm-02") "Transcript must inherit parent frame ID") (assert (= tr.language "ru") "Language must match detected code") (assert tr.isFinal "Terminal flag must be true") (assert (> tr.confidence 0.90) "Confidence must exceed 0.90") (assert (< tr.latencyMs 50) "Inference latency must be sub-50ms") true)

fn testIntentClassificationSearch -> Bool
  (let [(f (vg/makePcmFrame "pcm-03" true)) (trRu (vg/ingestPcmFrame f "что такое WebGPU буфер" "ru" true)) (trEn (vg/ingestPcmFrame f "what is the latest release of Bun" "en" true)) (decRu (vg/classifyVoiceIntent trRu)) (decEn (vg/classifyVoiceIntent trEn))] (assert (= decRu.routeTag ":fast-search") "Russian query must route to :fast-search") (assert decRu.groundingRequired "Russian query must require live search") (assert (= decRu.targetPreset "preset-fast-search") "Target preset must be preset-fast-search") (assert (= decEn.routeTag ":fast-search") "English query must route to :fast-search") (assert decEn.groundingRequired "English query must require live search") true)

fn testIntentClassificationAction -> Bool
  (let [(f (vg/makePcmFrame "pcm-04" true)) (trRu (vg/ingestPcmFrame f "кликни на кнопку checkout" "ru" true)) (trEn (vg/ingestPcmFrame f "click on the submit button" "en" true)) (decRu (vg/classifyVoiceIntent trRu)) (decEn (vg/classifyVoiceIntent trEn))] (assert (= decRu.routeTag ":agent-action") "Russian command must route to :agent-action") (assert (not decRu.groundingRequired) "Action command must not require web search") (assert (= decRu.targetPreset "preset-agent-action") "Target preset must be preset-agent-action") (assert (= decEn.routeTag ":agent-action") "English command must route to :agent-action") true)

fn testGatewayVersion -> Bool
  (let [(v (vg/getGatewayVersion))] (assert (= v "1.0.0") "Version must be 1.0.0") (refute (= v "0.0.0") "Version must not be 0.0.0") true)

fn runTests -> Bool
  (do (assert (testMakePcmFrame) "PCM frame test failed") (assert (testIngestPcmFrame) "Ingest PCM frame test failed") (assert (testIntentClassificationSearch) "Search intent test failed") (assert (testIntentClassificationAction) "Action intent test failed") (assert (testGatewayVersion) "Gateway version test failed") true)
