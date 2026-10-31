(module aslGateway/tests/ledgerFnsTest
  :x [runTests]
  :i [(usageLedger :a ul)
      (balancer :a bal)])

; (:m :ref COVERAGE-RATCHET-RED :do "direct cases for the ledger rotation and window functions: the default keep, rotateWith! below, at and past the size limit with rising generation numbers, pruning to keep and a held rotate lock, windowReadNewest! naming its window by the newest call, and ledgerSinceMs as the earliest window start of every budget")
fn rowAt atMs: Int64 -> ul/CallRow
  (ul/CallRow :atMs atMs :profile "p" :intent "construct" :alias "a" :provider "pv" :model "m" :inTokens 10 :cachedTokens 0 :outTokens 2
    :reasoningTokens 0 :ttftMs none :ms none :outcome "ok" :charge 0 :tag none :temperature none :topP none :maxTokens none :effort none
    :api "chat" :stream false :toolCount 0 :promptBytes 0 :sysHash "" :session none :turn none :consumer none :cacheWriteTokens none :status 0 :reason none)

fn ! scratch! tag: String -> String
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/ledgerFnsTest." tag "." (stringFromInt64 (procSelf))))
        (_ (pathRemove dir))
        (_ (dirCreate dir))]
    dir)

fn ! exists? p: String -> Bool
  (ok? (fileStat p))

fn ! testRotate -> Bool
  (let [(dir (scratch! "rot"))
        (path (str dir "/calls.asn"))
        (body "0123456789012345678901234567890123456789")
        (absent (ul/rotateWith! path 10 3))
        (_ (fileWrite path "short"))
        (below (ul/rotateWith! path 10 3))
        (stayed (exists? path))
        (_ (fileWrite path body))
        (first (ul/rotateWith! path 10 3))
        (movedFirst (and (not (exists? path)) (exists? (str path ".1"))))
        (_ (fileWrite path body))
        (second (ul/rotateWith! path 10 3))
        (kept (and (exists? (str path ".1")) (exists? (str path ".2"))))
        (_ (fileWrite path body))
        (third (ul/rotateWith! path 10 2))
        (pruned (and (not (exists? (str path ".1"))) (exists? (str path ".2")) (exists? (str path ".3"))))
        (_ (fileWrite path body))
        (held (fileLock (str path ".rotate") true))
        (busy (ul/rotateWith! path 10 2))
        (untouched (and (exists? path) (not (exists? (str path ".4")))))
        (_ (match held ((ok fd) (fdClose fd)) ((err _) (ok ()))))
        (freed (ul/rotateWith! path 10 2))
        (_ (fileWrite path "0123456789"))
        (atLimit (ul/rotateWith! path 10 2))
        (_ (pathRemove dir))]
    (do (assert (= (ul/defaultLedgerKeep) 8) "the default keeps eight generations")
        (assert (= absent (ok false)) "no ledger file is nothing to rotate")
        (assert (and (= below (ok false)) stayed) "a file under the limit stays")
        (assert (and (= first (ok true)) movedFirst) "a full file moves to generation 1")
        (assert (and (= second (ok true)) kept) "the next shift takes generation 2 and keeps generation 1")
        (assert (and (= third (ok true)) pruned) "keep 2 prunes the oldest generation after the shift")
        (assert (ok? held) "the test took the rotate lock")
        (assert (and (= busy (ok false)) untouched) "a held rotate lock skips the shift and leaves the file")
        (assert (= freed (ok true)) "with the lock released the shift happens")
        (assert (= atLimit (ok true)) "a file exactly at the limit is shifted")
        true))

fn ! atList rows: (List ul/CallRow) -> (List Int64)
  (listSort (map (fn [(r ul/CallRow)] -> Int64 r.atMs) rows))

fn ! appendAll! path: String from: Int64 to: Int64 maxBytes: Int64 keep: Int64 -> Bool
  (listAll? (fn [(i Int64)] -> Bool (ok? (ul/appendCallRowWith! path (rowAt i) maxBytes keep))) (range from to))

fn ! testNewest -> Bool
  (let [(dir (scratch! "new"))
        (path (str dir "/calls.asn"))
        (maxBytes (* 3 (stringLength (ul/callRowLine (rowAt 1000)))))
        (wrote (appendAll! path 1000 1012 maxBytes 8))
        (back5 (resultOr (ul/windowReadNewest! path (fn [(n Int64)] -> Int64 (- n 5))) (pair (list) (list))))
        (named (resultOr (ul/windowReadNewest! path (fn [(n Int64)] -> Int64 (if (= n 1011) 1010 0))) (pair (list) (list))))
        (shifted (ul/rotateWith! path 1 8))
        (after (resultOr (ul/windowReadNewest! path (fn [(n Int64)] -> Int64 (- n 1))) (pair (list) (list))))
        (_ (pathRemove dir))]
    (do (assert wrote "twelve rows were written across generations")
        (assert (= (atList (pairSecond back5)) (range 1006 1012)) "a window back 5 from the newest call keeps 1006 to 1011 across generations")
        (assert (> (listLength (pairFirst back5)) 1) "the window opened older files than the live one")
        (assert (= (atList (pairSecond named)) (list 1010 1011)) "sinceOf receives the newest call time")
        (assert (= shifted (ok true)) "the live file was shifted whole")
        (assert (= (atList (pairSecond after)) (list 1010 1011)) "right after a shift the newest generation with rows still names the window")
        true))

fn budget id: String windowMs: Int64 anchorMs: Int64 -> bal/Budget
  (bal/Budget :id id :windowMs windowMs :anchorMs anchorMs :unit "req" :size 100 :softPct 80 :hardPct 100 :useOrLose false :source "test" :headerWindowMs 0)

fn pool budgets: (List bal/Budget) -> bal/Balancer
  (bal/makeBalancer (list) budgets (list) (bal/defaultPolicy))

fn testSince -> Bool
  (let [(now 10000000)]
    (do (assert (= (bal/ledgerSinceMs (pool (list)) now) now) "no budget needs no history")
        (assert (= (bal/ledgerSinceMs (pool (list (budget "hour" 3600000 0))) now) 7200000) "an hourly budget counts from the start of its current hour")
        (assert (= (bal/ledgerSinceMs (pool (list (budget "life" 0 5000))) now) 5000) "a lifetime budget counts from its anchor")
        (assert (= (bal/ledgerSinceMs (pool (list (budget "hour" 3600000 0) (budget "day" 86400000 0))) now) 0) "the earliest window start of all budgets wins")
        (assert (= (bal/ledgerSinceMs (pool (list (budget "hour" 3600000 0) (budget "short" 60000 0))) now) 7200000) "a shorter window does not pull the start later than the longest one")
        true))

fn ! runTests -> Bool
  (do (testRotate) (testNewest) (testSince) true)
