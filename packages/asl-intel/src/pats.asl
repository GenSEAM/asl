(module asl-intel/pats
  :x [lit ws0! ws1! idRun! patModuleId! patModuleIdNoDot! patExports! patImportsBlock! patImportName!
      patFnParen! patFnNewline! patSchemaParen! patMacroParen! patSchemaLine! patMacroLine!
      patPackage! patEntry! patDepsBlock! patModsBlock! patQuoted! patWordRunDeps! patWordRunMods!
      patFnHeader! patOutlineFn! patDeadFn! patVacTestFn! patVacProdStub! patQueryDecl! patWordLit!]
  :i [(asl-intel/rx :a r)])

fn lit s: String -> r/Rx
  (r/rxLit (stringToBytes s))

fn ws0! -> r/Rx
  (r/rxRep (r/clsSpace!) 0 true)

fn ws1! -> r/Rx
  (r/rxRep (r/clsSpace!) 1 true)

fn idRun! spec: String -> r/Rx
  (r/rxRep (r/clsSet! spec) 1 true)

fn startNl -> r/Rx
  (r/rxAlt (list (r/rxBos) (lit "\n")))

fn startNlMulti -> r/Rx
  (r/rxAlt (list (r/rxBol) (lit "\n")))

fn patModuleId! -> r/Rex
  (r/rexCompile! (r/rxSeq (list (lit "(module") (ws1!) (r/rxGroup 1 (idRun! "a-zA-Z0-9_/.-")))) 1 (r/preByte) 40)

fn patModuleIdNoDot! -> r/Rex
  (r/rexCompile! (r/rxSeq (list (lit "(module") (ws1!) (r/rxGroup 1 (idRun! "a-zA-Z0-9_/-")))) 1 (r/preByte) 40)

fn patExports! -> r/Rex
  (r/rexCompile! (r/rxSeq (list (lit ":x") (ws1!) (lit "[") (r/rxGroup 1 (r/rxRep (r/clsNot! "]") 0 true)) (lit "]"))) 1 (r/preByte) 58)

fn patImportsBlock! -> r/Rex
  (r/rexCompile! (r/rxSeq (list (lit ":i") (ws1!) (lit "[") (r/rxGroup 1 (r/rxRep (r/clsAny) 0 false)) (lit "]") (ws0!) (lit ")"))) 1 (r/preByte) 58)

fn patImportName! -> r/Rex
  (r/rexCompile! (r/rxSeq (list (lit "(") (r/rxGroup 1 (idRun! "a-zA-Z0-9_/.-")))) 1 (r/preByte) 40)

fn patFnParen! -> r/Rex
  (r/rexCompile! (r/rxSeq (list (lit "(fn") (ws1!))) 0 (r/preByte) 40)

fn patFnNewline! -> r/Rex
  (r/rexCompile! (r/rxSeq (list (lit "\nfn") (ws1!))) 0 (r/preByte) 10)

fn patSchemaParen! -> r/Rex
  (r/rexCompile! (r/rxSeq (list (lit "(schema") (ws1!))) 0 (r/preByte) 40)

fn patMacroParen! -> r/Rex
  (r/rexCompile! (r/rxSeq (list (lit "(macro") (ws1!))) 0 (r/preByte) 40)

fn patSchemaLine! -> r/Rex
  (r/rexCompileLead! (r/rxSeq (list (startNl) (ws0!) (lit "(schema") (ws1!) (r/rxGroup 1 (idRun! "a-zA-Z0-9_-")))) 1 (r/preNewline) 0 (list "(schema") false)

fn patMacroLine! -> r/Rex
  (r/rexCompileLead! (r/rxSeq (list (startNl) (ws0!) (lit "(macro") (ws1!) (r/rxGroup 1 (idRun! "a-zA-Z0-9_-")))) 1 (r/preNewline) 0 (list "(macro") false)

fn patPackage! -> r/Rex
  (r/rexCompile! (r/rxSeq (list (lit ":package") (ws1!) (r/rxGroup 1 (idRun! "a-zA-Z0-9_-")))) 1 (r/preByte) 58)

fn patEntry! -> r/Rex
  (r/rexCompile! (r/rxSeq (list (lit ":entry") (ws1!) (lit "\"") (r/rxGroup 1 (r/rxRep (r/clsNot! "\"") 1 true)) (lit "\""))) 1 (r/preByte) 58)

fn blockPat! key: String -> r/Rex
  (r/rexCompile! (r/rxSeq (list (lit key) (ws1!) (r/rxOne (r/clsSet! "[(")) (r/rxGroup 1 (r/rxRep (r/clsNot! "])") 0 true)) (r/rxOne (r/clsSet! "])")))) 1 (r/preByte) 58)

fn patDepsBlock! -> r/Rex
  (blockPat! ":dependencies")

fn patModsBlock! -> r/Rex
  (blockPat! ":modules")

fn patQuoted! -> r/Rex
  (r/rexCompile! (r/rxSeq (list (lit "\"") (r/rxGroup 1 (r/rxRep (r/clsNot! "\"") 1 true)) (lit "\""))) 1 (r/preByte) 34)

fn patWordRunDeps! -> r/Rex
  (r/rexCompile! (r/rxGroup 1 (idRun! "a-zA-Z0-9_-")) 1 (r/preAny) 0)

fn patWordRunMods! -> r/Rex
  (r/rexCompile! (r/rxGroup 1 (idRun! "a-zA-Z0-9_/.-")) 1 (r/preAny) 0)

fn patFnHeader! -> r/Rex
  (r/rexCompileLead!
    (r/rxSeq (list (startNlMulti) (ws0!) (r/rxOpt (lit "(")) (ws0!) (r/rxAlt (list (lit "fn") (lit "defn"))) (ws1!)
                   (r/rxGroup 1 (r/rxSeq (list (r/rxOpt (lit "!")) (ws0!) (idRun! "a-zA-Z0-9_?.-"))))
                   (ws0!) (r/rxGroup 2 (r/rxRep (r/clsNot! "\n") 0 true)) (ws0!) (lit "->") (ws0!)
                   (r/rxGroup 3 (r/rxRep (r/clsNot! "\n") 1 true))))
    3 (r/preLine) 0 (list "fn" "defn") true)

fn patOutlineFn! -> r/Rex
  (r/rexCompileLead!
    (r/rxSeq (list (startNl) (ws0!) (r/rxAlt (list (r/rxSeq (list (lit "(fn") (ws1!))) (r/rxSeq (list (lit "fn") (ws1!)))))
                   (r/rxGroup 1 (r/rxSeq (list (r/rxOpt (lit "!")) (ws0!) (idRun! "a-zA-Z0-9_-"))))
                   (r/rxGroup 2 (r/rxRep (r/clsNot! "\n") 0 false))
                   (r/rxOpt (r/rxSeq (list (lit "->") (ws0!) (r/rxGroup 3 (r/rxRep (r/clsSetSpace! "a-zA-Z0-9_()-") 1 true)))))
                   (r/rxAlt (list (lit "\n") (lit ")")))))
    3 (r/preNewline) 0 (list "(fn" "fn") false)

fn patDeadFn! -> r/Rex
  (r/rexCompileLead!
    (r/rxSeq (list (startNl) (ws0!) (r/rxAlt (list (lit "fn") (lit "defn"))) (ws1!)
                   (r/rxGroup 1 (r/rxSeq (list (r/rxOpt (lit "!")) (ws0!) (idRun! "a-zA-Z0-9_-"))))))
    1 (r/preNewline) 0 (list "fn" "defn") false)

fn nextDecl! -> r/Rx
  (r/rxSeq (list (lit "\n") (ws0!) (r/rxAlt (list (lit "fn") (lit "defn") (lit "schema") (lit "macro") (lit "(module") (lit "(schema") (lit "(macro") (r/rxEos)))))

fn patVacTestFn! -> r/Rex
  (r/rexCompileLead!
    (r/rxSeq (list (startNl) (ws0!) (r/rxAlt (list (lit "fn") (lit "defn"))) (ws1!)
                   (r/rxGroup 1 (r/rxSeq (list (r/rxOpt (lit "!")) (ws0!)
                                               (r/rxAlt (list (r/rxSeq (list (lit "test") (r/rxRep (r/clsSet! "a-zA-Z0-9_-") 0 true))) (lit "RunTests") (lit "runTests"))))))
                   (r/rxRep (r/clsNot! "\n") 0 true) (ws0!) (lit "->") (ws0!) (idRun! "a-zA-Z0-9_() -") (ws0!) (lit "\n")
                   (r/rxGroup 2 (r/rxRep (r/clsAny) 0 false))
                   (r/rxLook (nextDecl!))))
    2 (r/preNewline) 0 (list "fn" "defn") false)

fn patVacProdStub! -> r/Rex
  (r/rexCompileLead!
    (r/rxSeq (list (startNl) (ws0!) (r/rxAlt (list (lit "fn") (lit "defn"))) (ws1!)
                   (r/rxGroup 1 (r/rxSeq (list (r/rxOpt (lit "!")) (ws0!) (idRun! "a-zA-Z0-9_-"))))
                   (r/rxRep (r/clsNot! "\n") 0 true) (ws0!) (lit "->") (ws0!) (r/rxGroup 2 (idRun! "a-zA-Z0-9_() -")) (ws0!) (lit "\n") (ws0!)
                   (r/rxGroup 3 (r/rxAlt (list (idRun! "a-zA-Z0-9_\":-") (r/rxSeq (list (lit "(") (idRun! "a-zA-Z0-9_-") (lit ")"))))))
                   (ws0!)
                   (r/rxAlt (list (r/rxSeq (list (lit "\n") (ws0!) (lit "\n"))) (nextDecl!)))))
    3 (r/preNewline) 0 (list "fn" "defn") false)

fn patQueryDecl! -> r/Rex
  (r/rexCompile!
    (r/rxSeq (list (r/rxAlt (list (r/rxSeq (list (lit "fn") (ws1!))) (r/rxSeq (list (lit "schema") (ws1!))) (r/rxSeq (list (lit "macro") (ws1!)))))
                   (r/rxGroup 1 (r/rxSeq (list (r/rxOpt (lit "!")) (ws0!) (idRun! "a-zA-Z0-9_-"))))))
    1 (r/preAny) 0)

fn patWordLit! word: String -> r/Rex
  (r/rexCompile! (r/rxSeq (list (r/rxWordB) (lit word) (r/rxWordB))) 0 (r/preAny) 0)
