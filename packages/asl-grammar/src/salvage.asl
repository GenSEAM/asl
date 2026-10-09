(module asl-grammar/salvage
  :x [main]
  :i [(asl-grammar/peg :a peg)])

fn ! main args: (List String) -> (Result Int64 String)
  (let [(input (optionOr (listHead args) ""))
        (output (optionOr (listGet args 1) ""))
        (path (optionOr (listGet args 2) "asl/grammar/aslGrammar.asn"))]
    (if (or (= input "") (= output ""))
      (err "usage: salvage.asl in out [grammar]")
      (mt (peg/grammarLoad! path)
        ((err e) (err e))
        ((ok g) (mt (peg/grammarWithStart g "genFile")
                  ((err e) (err e))
                  ((ok gen) (mt (fileReadString input)
                              ((err _) (err (str "cannot read " input)))
                              ((ok text) (mt (peg/grammarSalvage gen text)
                                           ((none) (err (str "no prefix of " input " is accepted by genFile")))
                                           ((some kept) (mt (fileWrite output kept)
                                                          ((err _) (err (str "cannot write " output)))
                                                          ((ok _) (do (println (str "(:salvage :in \"" input "\" :bytes " (stringLength text) " :kept " (stringLength kept) ")")) (ok 0))))))))))))))
