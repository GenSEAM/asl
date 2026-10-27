(module asl-forms/tests/catalogueKeysTest :x [runTests] :i [(asl-forms/ops :a ops) (asl-forms/tools :a t) (asl-forms/search :a s)])

fn root! -> String
  (resultOr (realPath ".") ".")

fn ctx! -> s/KnowCtx
  (let [(r (root!))]
    (s/KnowCtx :ws r :toolRoot r :binDir (str r "/bin") :vfsDir "" :toolsFile (str r "/asl/grammar/tools.asn") :home ""))

fn keyChars? c: String -> Bool
  (let [(k (charCode c))] (or (and (>= k 48) (<= k 57)) (and (>= k 65) (<= k 90)) (and (>= k 97) (<= k 122)) (= k 95)))

fn keysIn text: String i: Int64 acc: (List String) -> (List String)
  (if (>= i (stringLength text))
    (listReverse acc)
    (if (and (= (optionOr (stringSlice text i (+ i 1)) "") ":") (or (= i 0) (not (keyChars? (optionOr (stringSlice text (- i 1) i) "")))))
      (let [(j (keyEnd text (+ i 1)))]
        (keysIn text j (cons (optionOr (stringSlice text (+ i 1) j) "") acc)))
      (keysIn text (+ i 1) acc)))

fn keyEnd text: String j: Int64 -> Int64
  (if (and (< j (stringLength text)) (keyChars? (optionOr (stringSlice text j (+ j 1)) ""))) (keyEnd text (+ j 1)) j)

fn declared? o: t/ToolOp k: String -> Bool
  (or (stringContains? o.paramsRaw (str "(:" k " ")) (listContains? o.accepts k))

fn missingFromForm o: t/ToolOp -> (List String)
  (let [(ks (optionOr (listTail (keysIn (optionOr (listHead (stringSplit o.form " | ")) "") 0 (list))) (list)))]
    (filter (fn [(k String)] -> Bool (not (declared? o k))) ks))

fn ! testFormKeysDeclared -> Bool
  (match (t/loadRegistry! (ctx!))
    ((none) (do (assert false "catalogue loads") false))
    ((some reg)
      (let [(bad (filter (fn [(row String)] -> Bool (not (stringEmpty? row)))
                   (map (fn [(n String)] -> String
                          (let [(o (optionOr (mapGet reg.ops n) (t/ToolOp :name n :scope "" :public "" :doc "" :form "" :paramsRaw "" :paramsCompact "" :paramsSummary "" :examples (list) :errors (list) :related (list) :accepts (list))))
                                (m (if (stringEmpty? o.paramsRaw) (list) (missingFromForm o)))]
                            (if (listEmpty? m) "" (str n ":" (stringJoin m ",")))))
                        reg.order)))]
        (do (assert (listEmpty? bad) (str "keys in :form but not in :params: " (stringJoin bad " ")))
            true))))

fn handlerKeys -> (List (Pair String String))
  (list (pair "observe" "symbol") (pair "observe" "module") (pair "observe" "path") (pair "observe" "spec") (pair "observe" "id")
        (pair "lens" "path") (pair "lens" "text") (pair "lens" "lens")
        (pair "edit" "path") (pair "edit" "pick")
        (pair "check" "path") (pair "diff" "path") (pair "flush" "path") (pair "discard" "path") (pair "fix" "path")
        (pair "note" "fact") (pair "note" "id")
        (pair "audit" "full") (pair "audit" "path")
        (pair "tree" "ws"))

fn ! testHandlerKeysDeclared -> Bool
  (match (t/loadRegistry! (ctx!))
    ((none) (do (assert false "catalogue loads") false))
    ((some reg)
      (let [(bad (filter (fn [(p (Pair String String))] -> Bool
                           (match (mapGet reg.ops (pairFirst p)) ((none) true) ((some o) (not (declared? o (pairSecond p))))))
                         (handlerKeys)))]
        (do (assert (listEmpty? bad) (str "handler-read keys missing from :params: " (stringJoin (map (fn [(p (Pair String String))] -> String (str (pairFirst p) ":" (pairSecond p))) bad) " ")))
            true))))

fn ! testObserveExampleAccepted -> Bool
  (let [(l (optionOr (listHead (ops/runStep! (root!) 1 "(:observe :dim callers :symbol runStep!)").lines) ""))]
    (do (assert (not (stringContains? l "ERR_UNKNOWN_KEY")) (str "documented observe form is not rejected: " l))
        true))

fn ! runTests -> Bool
  (do (assert (testFormKeysDeclared) "every key in an op's :form is declared in its :params")
      (assert (testHandlerKeysDeclared) "keys read by handlers are declared")
      (assert (testObserveExampleAccepted) "(:observe :dim callers :symbol S) is accepted")
      true)
