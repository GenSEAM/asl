(module asl-audio/tests/heardnameTest :x [runHeardnameTests main] :i [(asl-audio/speakerVerifier :a sv) (asl-audio/heardname :a hn)])

fn makeMockVec val: Float64 count: Int64 -> (List Float64)
  (if (<= count 0)
    (list)
    (cons val (makeMockVec val (- count 1))))

fn runHeardnameTests -> Bool
  (let [(v1 (makeMockVec 0.5 16))
        (v2 (makeMockVec 0.5 16))
        (vOrth (list 1.0 0.0 0.0 0.0))
        (vOrth2 (list 0.0 1.0 0.0 0.0))]
    (let [(simIdent (sv/calculateCosineSimilarity v1 v2))
          (simOrth (sv/calculateCosineSimilarity vOrth vOrth2))]
      (assert (>= simIdent 0.99) (str "Identical vectors must have cosine similarity ~1.0: " (stringFromFloat64 simIdent)))
      (assert (<= simOrth 0.01) (str "Orthogonal vectors must have cosine similarity ~0.0, got: " (stringFromFloat64 simOrth)))))

  (let [(tauClean (sv/adaptiveThresholdBySnr 25.0))
        (tauNoisy (sv/adaptiveThresholdBySnr 12.0))]
    (assert (> tauClean 0.72) "Clean high SNR (>25dB) must elevate threshold above 0.72")
    (assert (< tauNoisy 0.72) "Diffuse noisy room (12dB) must relax threshold below 0.72")
    (assert (and (>= tauNoisy 0.68) (<= tauClean 0.76)) "Threshold must remain bounded in [0.68, 0.76]"))

  (let [(nearCentroid (list 0.8 0.6 0.0 0.0))
        (deskCentroid (list 0.0 0.8 0.6 0.0))
        (farCentroid (list 0.0 0.0 0.8 0.6))
        (userCandidate (list 0.05 0.78 0.59 0.02))
        (strangerCandidate (list 0.7 0.0 0.0 0.7))]
    (let [(centroids (sv/makeSpeakerCentroids nearCentroid deskCentroid farCentroid))]
      (let [(resUser (sv/verifySpeakerEmbedding userCandidate centroids 18.0))
            (resStranger (sv/verifySpeakerEmbedding strangerCandidate centroids 18.0))]
        (assert (= resUser.isVerified true) "User candidate matching desk mic must be verified")
        (assert (= resUser.matchedCluster "deskMic") "Matched cluster must be deskMic")
        (assert (>= resUser.maxScore 0.90) "Similarity to enrolled desk mic must be >= 0.90")
        (assert (= resStranger.isVerified false) "Stranger/TV speaker must be rejected"))))

  (let [(lat1 (hn/latinizeCyrillic "шроуди"))
        (lat2 (hn/latinizeCyrillic "эмит свифт"))
        (lat3 (hn/latinizeCyrillic "терминал канвас"))]
    (assert (= lat1 "shroudi") "шроуди must latinize to shroudi")
    (assert (= lat2 "emit svift") "эмит свифт must latinize to emit svift")
    (assert (= lat3 "terminal kanvas") "терминал канвас must latinize to terminal kanvas"))

  (let [(stem1 (hn/splitCamelCaseStems "emitSwift"))
        (stem2 (hn/splitCamelCaseStems "terminalCanvas"))
        (stem3 (hn/splitCamelCaseStems "sds1DarkTheme"))]
    (assert (= stem1 "emit swift") "emitSwift must split to 'emit swift'")
    (assert (= stem2 "terminal canvas") "terminalCanvas must split to 'terminal canvas'")
    (assert (= stem3 "sds1 dark theme") "sds1DarkTheme must split to 'sds1 dark theme'"))

  (let [(f1 (hn/foldStemPhonemes "canvas"))
        (f2 (hn/foldStemPhonemes "kanvas"))
        (f3 (hn/foldStemPhonemes "swift"))
        (f4 (hn/foldStemPhonemes "svift"))]
    (assert (= f1 "kanvas") "c in canvas must fold to k")
    (assert (= f1 f2) "canvas and kanvas must fold to identical phonemes")
    (assert (= f3 "svift") "w in swift must fold to v")
    (assert (= f3 f4) "swift and svift must fold to identical phonemes"))

  (let [(c1 (hn/makeAstSymbolCandidate "emitSwift" "asl/packages/asl-target-swift/src/emitSwift.asl" "symbol"))
        (c2 (hn/makeAstSymbolCandidate "terminalCanvas" "asl/packages/asl-ui/src/terminalCanvas.asl" "symbol"))
        (c3 (hn/makeAstSymbolCandidate "bento" "asl/packages/asl-ui/src/bento.asl" "package"))
        (c4 (hn/makeAstSymbolCandidate "asl-target-swift" "asl/packages/asl-target-swift" "package"))]
    (let [(candidates (list c1 c2 c3 c4))]
      (let [(match1 (hn/matchVoiceQueryToAstSymbol "эмит свифт" candidates 0.70))
            (match2 (hn/matchVoiceQueryToAstSymbol "терминал канвас" candidates 0.70))
            (match3 (hn/matchVoiceQueryToAstSymbol "таргет свифт" candidates 0.65))
            (match4 (hn/matchVoiceQueryToAstSymbol "бенто" candidates 0.70))]
        (assert (= match1.isMatched true) "эмит свифт must match")
        (assert (= match1.matchedSymbol "emitSwift") "эмит свифт must resolve to emitSwift")
        (assert (= match1.matchedPath "asl/packages/asl-target-swift/src/emitSwift.asl") "Path must be emitSwift.asl")

        (assert (= match2.isMatched true) "терминал канвас must match")
        (assert (= match2.matchedSymbol "terminalCanvas") "терминал канвас must resolve to terminalCanvas")

        (assert (= match3.isMatched true) "таргет свифт must match")
        (assert (= match3.matchedSymbol "asl-target-swift") "таргет свифт must resolve to asl-target-swift")

        (assert (= match4.isMatched true) "бенто must match")
        (assert (= match4.matchedSymbol "bento") "бенто must resolve to bento"))))

  true

fn ! main args: (List Str) -> (Result Unit IoError)
  (if (runHeardnameTests) (let [(u (println "asl-audio heardname tests passed cleanly"))] (ok ())) (let [(u (eprintln "asl-audio heardname test failure"))] (err (other))))
