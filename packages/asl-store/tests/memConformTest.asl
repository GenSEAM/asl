(module asl-store/tests/memConformTest
  :x [runTests]
  :i [(asl-store/types :a ty) (asl-store/mem :a mem) (asl-store/wire :a w) (asl-store/kv :a kv) (asl-store/conform :a cf) (asl-store/tests/loadSupport :a ld)])

fn scriptsDir -> String
  "asl/packages/asl-store/conform"

fn contractIds -> (List String)
  (list "kvCasCreateOnce" "kvCasStale" "kvDelStale" "kvKeyInvalid" "kvRoundTrip" "kvScanOrderLimitCursor" "kvTooLarge" "kvTtlExpiry" "logAppendMonotonic" "logConsumerCursor" "logReadFromOffset")

fn ! scripts! -> (List cf/Script)
  (match (ld/loadScripts! (scriptsDir))
    ((ok xs) xs)
    ((err e) (do (eprintln e) (list))))

fn runAll scripts: (List cf/Script) step: (fn [mem/MemState ty/Op] -> (Pair mem/MemState ty/Reply)) -> (List cf/ScriptRun)
  (map (fn [(s cf/Script)] -> cf/ScriptRun (cf/runPure s step)) scripts)

fn failing runs: (List cf/ScriptRun) -> (List String)
  (map (fn [(r cf/ScriptRun)] -> String r.id) (filter (fn [(r cf/ScriptRun)] -> Bool (not (listEmpty? r.failures))) runs))

fn countOf runs: (List cf/ScriptRun) -> Int64
  (fold (fn [(a Int64) (r cf/ScriptRun)] -> Int64 (+ a r.executed)) 0 runs)

fn declaredOf runs: (List cf/ScriptRun) -> Int64
  (fold (fn [(a Int64) (r cf/ScriptRun)] -> Int64 (+ a r.declared)) 0 runs)

fn firstFailure runs: (List cf/ScriptRun) -> String
  (optionOr (listHead (fold (fn [(a (List String)) (r cf/ScriptRun)] -> (List String) (listAppend a r.failures)) (list) runs)) "")

; (:m :ref VS-CORE :do "mutant adapters wrap memStep and break one rule each; the gate needs every one to fail at least one script, which proves the scripts constrain the rule and not just the reference")
fn mutStaleCas st: mem/MemState op: ty/Op -> (Pair mem/MemState ty/Reply)
  (match op
    ((ty/opCas k e v ttl now)
      (let [(cur (pairSecond (mem/memStep st (ty/opGet k now))))
            (rev (match cur ((ty/rValue r _ _) r) (_ 0)))]
        (mem/memStep st (ty/opCas k (if (= e 0) 0 rev) v ttl now))))
    (_ (mem/memStep st op)))

fn mutTtlIgnored st: mem/MemState op: ty/Op -> (Pair mem/MemState ty/Reply)
  (match op
    ((ty/opGet k _) (mem/memStep st (ty/opGet k 0)))
    ((ty/opScan c p a l _) (mem/memStep st (ty/opScan c p a l 0)))
    (_ (mem/memStep st op)))

fn mutScanUnordered st: mem/MemState op: ty/Op -> (Pair mem/MemState ty/Reply)
  (let [(r (mem/memStep st op))]
    (match (pairSecond r)
      ((ty/rPage rows next) (pair (pairFirst r) (ty/rPage (listReverse rows) next)))
      (_ r)))

fn mutLimitIgnored st: mem/MemState op: ty/Op -> (Pair mem/MemState ty/Reply)
  (match op
    ((ty/opScan c p a _ n) (mem/memStep st (ty/opScan c p a 1000 n)))
    (_ (mem/memStep st op)))

fn ! runTests -> Bool
  (let [(scripts (scripts!))
        (base (runAll scripts mem/memStep))
        (stale (failing (runAll scripts mutStaleCas)))
        (ttl (failing (runAll scripts mutTtlIgnored)))
        (unordered (failing (runAll scripts mutScanUnordered)))
        (limit (failing (runAll scripts mutLimitIgnored)))
        (badCount (cf/parseScript "(:script :id x :checks 2)\n(:step (:get a b 1) (:absent))"))
        (bigRows (map (fn [(i Int64)] -> ty/ScanRow (ty/ScanRow :id (str "r" (stringFromInt64 i)) :rev 1 :value "" :expiresAt 0)) (range 0 1005)))
        (bigPage (kv/scanPage bigRows "" "" 1001))
        (bigRead (kv/readPage (map (fn [(i Int64)] -> ty/LogRow (ty/LogRow :offset i :value "" :at 0)) (range 0 1005)) 0 1001))
        (wildcard (cf/parseScript "(:script :id x :checks 1)\n(:step (:get a b 1) _)"))
        (headless (cf/parseScript "(:script :id x :checks 1)\n(:step (:get a b 1) (_ 1))"))
        (wireIn "(:put notes k \"a \\\"q\\\" \\\\ \\n \\t é\" 5 9) ; trailing comment\n(:get notes k 1)")
        (wireForms (resultOr (w/sxRead wireIn) (list)))]
    (do (assert (= (map (fn [(s cf/Script)] -> String s.id) scripts) (contractIds)) "the script directory holds exactly the scripts the D-VAULT-STORE contract names")
        (assert (listEmpty? (failing base)) (str "memStep passes every script: " (firstFailure base)))
        (assert (and (> (countOf base) 0) (= (countOf base) (declaredOf base))) "executed checks equal declared checks and are not zero")
        (assert (listContains? stale "kvCasStale") "a stale-CAS-accepting adapter fails kvCasStale")
        (assert (listContains? ttl "kvTtlExpiry") "a TTL-ignoring adapter fails kvTtlExpiry")
        (assert (listContains? unordered "kvScanOrderLimitCursor") "an unordered-scan adapter fails kvScanOrderLimitCursor")
        (assert (listContains? limit "kvScanOrderLimitCursor") "a limit-ignoring scan adapter fails kvScanOrderLimitCursor")
        (assert (err? badCount) "a script whose :checks differs from its :step count is refused at parse time")
        (assert (and (= (ty/capLimit 1001) 1000) (and (= (ty/capLimit 1000) 1000) (and (= (ty/capLimit 0) 1000) (= (ty/capLimit 999) 999)))) "capLimit caps at 1000, treats 0 as the cap and keeps smaller limits")
        (assert (match bigPage ((ty/rPage rows next) (and (= (listLength rows) 1000) (not (stringEmpty? next)))) (_ false)) "a scan with limit 1001 over 1005 rows returns 1000 and a next cursor")
        (assert (match bigRead ((ty/rRecords rows next) (and (= (listLength rows) 1000) (= next 1000))) (_ false)) "a log read with limit 1001 returns 1000 records")
        (assert (and (err? wildcard) (err? headless)) "an expected reply of _ or without a literal head is refused at parse time")
        (assert (= (listLength wireForms) 2) "the wire reader yields both forms and skips the comment")
        (assert (match (w/opParse (optionOr (listHead wireForms) (w/sxList (list)))) ((ok op) (match op ((ty/opPut k v ttl now) (and (= v "a \"q\" \\ \n \t é") (and (= ttl 5) (= now 9)))) (_ false))) ((err _) false)) "opParse decodes escapes and unicode in a put")
        (assert (= (w/sxShow (w/sxStr "a \"q\" \\ \n")) "\"a \\\"q\\\" \\\\ \\n\"") "sxShow escapes quote, backslash and newline")
        (assert (err? (w/opParse (w/sxList (list (w/sxAtom ":get") (w/sxAtom "c") (w/sxAtom "i") (w/sxAtom "x"))))) "a non-integer now is a parse error")
        true))
