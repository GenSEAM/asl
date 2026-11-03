(module aslAgent/tests/gatewayLinkDriver
  :x [main]
  :i [(aslAgent/providers :a pv) (asl-json/json :a j)])

fn quoted s: String -> String
  (str "\"" (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\"")

fn pairsText xs: (Option (List (Pair String String))) -> String
  (match xs ((none) "none") ((some ps) (str "(" (stringJoin (map (fn [(p (Pair String String))] -> String (str ":" (pairFirst p) " " (quoted (pairSecond p)))) ps) " ") ")")))

fn usageText xs: (Option (List (Pair String j/Json))) -> String
  (match xs ((none) "none") ((some ps) (str "(" (stringJoin (map (fn [(p (Pair String j/Json))] -> String (str ":" (pairFirst p) " " (j/jsonEmit (pairSecond p)))) ps) " ") ")")))

fn receipt t: pv/Turn -> String
  (str "(:receipt :reply "
       (match t.reply ((ok r) (match r ((some x) (quoted x)) ((none) "none"))) ((err e) (str "(:error " (pv/errorCode e) " " (quoted (pv/errorMessage e)) ")")))
       " :usage " (usageText t.meta.usage)
       " :served " (pairsText t.meta.served)
       " :finish " (match t.meta.finish ((some f) (quoted f)) ((none) "none"))
       " :timing " (match t.meta.timing ((some _) "present") ((none) "none")) ")")

fn linkText p: pv/Provider -> String
  (match p
    ((pv/vendorProvider cfg)
      (match cfg.link
        ((none) "(:link none)")
        ((some l) (match l.wiring.ledger
                    ((none) "(:link :ledger none)")
                    ((some ledger) (str "(:link :spent " (stringFromInt64 (fold (fn [(acc Int64) (b Int64)] -> Int64 (+ acc b)) 0 (map (fn [b] b.amount) ledger.buckets))) ")"))))))
    (_ "(:link none)"))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(root (optionOr (listHead args) "."))]
    (match (pv/makeProvider! "agy" "scout" root "mA" 60 "sLink" 30 false (pv/providerEnv! root) "auto")
      ((err e) (do (println (str "(:receipt :reply (:error " (pv/errorCode e) " " (quoted (pv/errorMessage e)) "))")) (ok 1)))
      ((ok p)
        (let [(t (pv/nextTurn! p "You are Leon." "hello gateway"))]
          (do (println (receipt t)) (println (linkText t.provider)) (ok 0))))))
