(module aslHarness/streamDemuxerTest :x [testExtractDeepseekThink testExtractBracketThought testContentQuarantineSeparation testToolcallNormalization testDemuxStreamFlow testEmptyAndBareStreams runTests] :i [(streamDemuxer :a demux)])

fn testExtractDeepseekThink -> Bool
  (let [(raw "<think>Calculating prime factors of 42</think>Answer is 42") (q (demux/extractThoughtChannel raw))] (assert q.quarantined "Quarantined flag must be true for think tags") (assert (= q.thoughtTokens "Calculating prime factors of 42") "Thought tokens must match exactly") (assert (> q.tokenCount 0) "Token count must be strictly positive") true)

fn testExtractBracketThought -> Bool
  (let [(raw "[THOUGHT]Reviewing security constraints[/THOUGHT]Deploy completed") (q (demux/extractThoughtChannel raw))] (assert q.quarantined "Quarantined flag must be true for bracket thoughts") (assert (= q.thoughtTokens "Reviewing security constraints") "Thought tokens must match") (assert (> q.tokenCount 0) "Token count must be positive") true)

fn testContentQuarantineSeparation -> Bool
  (let [(raw1 "<think>internal reasoning</think>Final user output") (raw2 "[THOUGHT]planning step[/THOUGHT]action payload") (c1 (demux/extractContentChannel raw1)) (c2 (demux/extractContentChannel raw2))] (assert (= c1 "Final user output") "Content 1 must not contain think tags") (assert (not (stringContains? c1 "internal reasoning")) "Content 1 must quarantine thoughts") (assert (= c2 "action payload") "Content 2 must not contain thought tags") (assert (not (stringContains? c2 "planning step")) "Content 2 must quarantine thoughts") true)

fn testToolcallNormalization -> Bool
  (let [(jsonCall "{\"name:\": \"read_file\", \"arguments:\": [\"foo.txt\"]}") (asnCall "(:call :tool \"read_file\" :args [\"foo.txt\"])") (normJson (demux/normalizeToolcallOutput jsonCall)) (normAsn (demux/normalizeToolcallOutput asnCall))] (assert (stringStartsWith? normJson "(:call") "Normalized JSON must start with :call") (assert (stringContains? normJson ":tool") "Normalized JSON must contain :tool keyword") (assert (= normAsn asnCall) "Pure ASN toolcall must remain unchanged") true)

fn testDemuxStreamFlow -> Bool
  (let [(d1 (demux/makeStreamDemuxer "kimi-3" true true)) (d2 (demux/makeStreamDemuxer "gpt-4o" false true)) (raw "<think>need to check file</think>(:call :tool \"check\" :args [\"src\"])") (r1 (demux/demuxLlmStream d1 raw)) (r2 (demux/demuxLlmStream d2 raw))] (assert (= r1.modelFamily "kimi-3") "Model family 1 must be kimi-3") (assert (= r2.modelFamily "gpt-4o") "Model family 2 must be gpt-4o") (assert r1.hasToolcall "Result 1 must identify tool call") (assert r2.hasToolcall "Result 2 must identify tool call") (assert r1.quarantine.quarantined "Result 1 must have quarantined thoughts") (assert (not (stringContains? r1.content "<think>")) "Stripped result must not have think tags") (assert (stringContains? r2.content "<think>") "Unstripped result must retain raw content") true)

fn testEmptyAndBareStreams -> Bool
  (let [(d (demux/makeStreamDemuxer "gemini-flash" true true)) (rEmpty (demux/demuxLlmStream d "")) (rBare (demux/demuxLlmStream d "Hello world plain response"))] (assert (= rEmpty.content "") "Empty stream produces empty content") (assert (not rEmpty.quarantine.quarantined) "Empty stream has unquarantined thoughts") (assert (= rBare.content "Hello world plain response") "Bare stream preserves response") (assert (not rBare.quarantine.quarantined) "Bare stream has no thinking tokens") (assert (not rBare.hasToolcall) "Bare stream has no tool calls") true)

fn runTests -> Bool
  (and (testExtractDeepseekThink) (and (testExtractBracketThought) (and (testContentQuarantineSeparation) (and (testToolcallNormalization) (and (testDemuxStreamFlow) (testEmptyAndBareStreams))))))
