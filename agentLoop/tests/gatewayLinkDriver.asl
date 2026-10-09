(module asl/agentLoop/tests/gatewayLinkDriver
  :x [main]
  :i [(asl/agentLoop/providers :a pv) (asl-json/json :a j)])

fn quoted s: String -> String
  (str "\"" (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\"")

fn pairsText xs: (Option (List (Pair String String))) -> String
  (mt xs ((none) "none") ((some ps) (str "(" (stringJoin (map (fn [(p (Pair String String))] -> String (str ":" (pairFirst p) " " (quoted (pairSecond p)))) ps) " ") ")")))

fn usageText xs: (Option (List (Pair String j/Json))) -> String
  (mt xs ((none) "none") ((some ps) (str "(" (stringJoin (map (fn [(p (Pair String j/Json))] -> String (str ":" (pairFirst p) " " (j/jsonEmit (pairSecond p)))) ps) " ") ")")))

fn receipt t: pv/Turn -> String
  (str "(:receipt :reply "
       (mt t.reply ((ok r) (mt r ((some x) (quoted x)) ((none) "none"))) ((err e) (str "(:error " (pv/errorCode e) " " (quoted (pv/errorMessage e)) ")")))
       " :usage " (usageText t.meta.usage)
       " :served " (pairsText t.meta.served)
       " :finish " (mt t.meta.finish ((some f) (quoted f)) ((none) "none"))
       " :timing " (mt t.meta.timing ((some _) "present") ((none) "none")) ")")

fn linkText p: pv/Provider -> String
  (mt p
    ((pv/vendorProvider cfg)
      (mt cfg.link
        ((none) "(:link none)")
        ((some l) (mt l.wiring.ledger
                    ((none) "(:link :ledger none)")
                    ((some ledger) (str "(:link :spent " (stringFromInt64 (fold (fn [(acc Int64) (b Int64)] -> Int64 (+ acc b)) 0 (map (fn [b] b.amount) ledger.buckets))) ")"))))))
    (_ "(:link none)"))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(root (optionOr (listHead args) "."))]
    (mt (pv/makeProvider! "agy" "scout" root "mA" 60 "sLink" 30 false (pv/providerEnv!))
      ((err e) (do (println (str "(:receipt :reply (:error " (pv/errorCode e) " " (quoted (pv/errorMessage e)) "))")) (ok 1)))
      ((ok p)
        (let [(t (pv/nextTurn! p "You are Leon." "hello gateway"))]
          (do (println (receipt t)) (println (linkText t.provider)) (ok 0))))))
