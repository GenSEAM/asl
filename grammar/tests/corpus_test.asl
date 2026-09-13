(module grammar/corpusTest
  :d "Automated assertion test suite for grammar corpus"
  :x [TestcorpusIntegrity])

(df TestcorpusIntegrity [] -> Bool
  (let [(f1 (file-read "asl/grammar/corpus/valid/01-basics.asl"))
        (f1b (if (.-ok f1) f1 (file-read "../corpus/valid/01-basics.asl")))
        (f1c (if (.-ok f1b) f1b (file-read "grammar/corpus/valid/01-basics.asl")))]
    (assert (.-ok f1c) "basics corpus file loaded cleanly")
    (assert (> (string-length (.-value f1c)) 0) "corpus file is not empty")
    (let [(f2 (file-read "asl/grammar/corpus/valid/02-match.asl"))
          (f2b (if (.-ok f2) f2 (file-read "../corpus/valid/02-match.asl")))
          (f2c (if (.-ok f2b) f2b (file-read "grammar/corpus/valid/02-match.asl")))]
      (assert (.-ok f2c) "match corpus file loaded cleanly")
      (assert (> (string-length (.-value f2c)) 0) "corpus file is not empty")
      true)))

(TestcorpusIntegrity)
