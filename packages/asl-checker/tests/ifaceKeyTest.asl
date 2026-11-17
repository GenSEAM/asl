(module asl-checker/tests/ifaceKeyTest
  :x [runTests]
  :i [(asl-checker/checkCached :a cc) (asl-checker/types :a ty) (asl-tools/fleet/run :a fr)])

; (:m :ref CHECKER-IFACE-KEY :do "fixture t <- lib/c <- pb/b <- lib/a, pb a :pure package: every edit of lib/a is checked twice, against the module stamps and with no cache at all, and the two verdicts must be equal; a body-only edit, a private helper's signature and a constant's value leave the importers' stamps valid, every edit an importer can observe (signature, record field, enum case, refined effect, a type reached through an import) re-keys them and the error is reported")
fn aBase -> String
  (str "(module lib/a :x [f k limit mkP P Q Shape] :i [])\n\n"
       "(schema P (:f x Int64))\n\n"
       "(schema Q (:f q Int64))\n\n"
       "(enum Shape (:c circle [(r Int64)] \"round\") (:c square [(s Int64)] \"four sides\"))\n\n"
       "fn helper n: Int64 -> Int64\n  (* n 2)\n\n"
       "fn f n: Int64 -> Int64\n  (+ n 1)\n\n"
       "fn k n: Int64\n  (+ n 2)\n\n"
       "fn limit -> Int64\n  3\n\n"
       "fn mkP -> P\n  (P :x (helper 1))\n")

fn bSrc -> String
  (str "(module pb/b :x [g gk lim make mkQ area] :i [(lib/a :a a)])\n\n"
       "fn g -> Int64\n  (a/f 1)\n\n"
       "fn gk -> Int64\n  (+ 1 (a/k 1))\n\n"
       "fn lim -> Bool\n  (= (a/limit) 3)\n\n"
       "fn make -> a/P\n  (a/mkP)\n\n"
       "fn mkQ -> a/Q\n  (a/Q :q 3)\n\n"
       "fn area s: a/Shape -> Int64\n  (match s ((a/circle r) r) ((a/square q) q))\n")

fn cSrc -> String
  "(module lib/c :x [h] :i [(pb/b :a b)])\n\nfn h -> Int64\n  (+ (b/g) (b/make).x)\n"

fn tSrc -> String
  "(module t :x [main] :i [(lib/c :a c)])\n\nfn main -> Int64\n  (c/h)\n"

fn checkerId -> String
  "cli-0000000000000000000000000000000000000000000000000000000000000005"

fn ! setup! ws: String -> Bool
  (and (ok? (dirCreate (str ws "/lib")))
       (and (ok? (dirCreate (str ws "/pb")))
            (and (ok? (fileWrite (str ws "/.asl.config.asn") "(:asl-config :workspace \"ifaceKey\" :version \"1.0.0\")\n"))
                 (and (ok? (fileWrite (str ws "/pb/manifest.asn") "(:package pb :version \"0.1.0\" :pure true)\n"))
                      (and (ok? (fileWrite (str ws "/lib/a.asl") (aBase)))
                           (and (ok? (fileWrite (str ws "/pb/b.asl") (bSrc)))
                                (and (ok? (fileWrite (str ws "/lib/c.asl") (cSrc)))
                                     (ok? (fileWrite (str ws "/t.asl") (tSrc))))))))))

fn none! -> cc/Verdict
  (cc/Verdict :diags (list (ty/Diagnostic :code "probe" :message "no verdict" :msg "no verdict" :line 0 :col 0 :path "")) :checked -1 :summarised -1)

fn ! cached! ws: String stamps: String -> cc/Verdict
  (resultOr (pairFirst (cc/checkFileCached! (str ws "/t.asl") (list) (cc/stampCacheAt stamps (checkerId)))) (none!))

fn ! fresh! ws: String -> cc/Verdict
  (resultOr (pairFirst (cc/checkFileCached! (str ws "/t.asl") (list) (cc/emptyCache))) (none!))

fn diagText d: ty/Diagnostic -> String
  (str d.code " " d.path ":" (stringFromInt64 d.line) ":" (stringFromInt64 d.col) " " d.message)

fn diagsText v: cc/Verdict -> String
  (stringJoin (listSort (map diagText v.diags)) "\n")

fn diagsIn v: cc/Verdict suffix: String -> Int64
  (listLength (filter (fn [(d ty/Diagnostic)] -> Bool (stringEndsWith? d.path suffix)) v.diags))

fn ! modStamps! stamps: String -> Int64
  (listLength (filter (fn [(n String)] -> Bool (stringEndsWith? n ".verdict")) (resultOr (dirList (str stamps "/modules")) (list))))

(schema Probe (:f name String) (:f applied Bool) (:f cached cc/Verdict) (:f fresh cc/Verdict) (:f newStamps Int64))

; (:m :ref CHECKER-IFACE-KEY :do "an edit is a list of replacements on the base text of lib/a, each of which must change it, so a typo in a probe cannot pass as an unchanged module; the base is written back after the probe")
fn applyEdits text: String edits: (List (Pair String String)) -> (Pair String Bool)
  (fold (fn [(acc (Pair String Bool)) (e (Pair String String))] -> (Pair String Bool)
          (let [(next (stringReplace (pairFirst acc) (pairFirst e) (pairSecond e)))]
            (pair next (and (pairSecond acc) (!= next (pairFirst acc))))))
        (pair text true) edits)

fn ! probe! ws: String stamps: String name: String edits: (List (Pair String String)) -> Probe
  (let [(edited (applyEdits (aBase) edits))
        (before (modStamps! stamps))
        (written (ok? (fileWrite (str ws "/lib/a.asl") (pairFirst edited))))
        (c (cached! ws stamps))
        (after (modStamps! stamps))
        (f (fresh! ws))
        (restored (ok? (fileWrite (str ws "/lib/a.asl") (aBase))))]
    (Probe :name name :applied (and (pairSecond edited) (and written restored)) :cached c :fresh f :newStamps (- after before)))

; (:m :ref CHECKER-IFACE-KEY :do "the stamps must never change a verdict: the cached diagnostics equal the uncached ones for every probe")
fn ! sound? p: Probe -> Bool
  (do (assert p.applied (str p.name ": the edit applies to lib/a and the base is written back"))
      (assert (= (diagsText p.cached) (diagsText p.fresh)) (str p.name ": the cached verdict equals the uncached one\ncached:\n" (diagsText p.cached) "\nfresh:\n" (diagsText p.fresh)))
      true)

; (:m :ref CHECKER-IFACE-KEY :do "an edit no importer can observe checks t and lib/a only: pb/b and lib/c are summarised from their stamps and the one new module stamp is lib/a's")
fn ! notRechecked? p: Probe -> Bool
  (do (sound? p)
      (assert (listEmpty? p.cached.diags) (str p.name ": the edit keeps the closure clean: " (diagsText p.cached)))
      (assert (= (cc/countsText p.cached) "(:checked 2 :summarised 2)") (str p.name ": only t and lib/a are checked, pb/b and lib/c hit their stamps: " (cc/countsText p.cached)))
      (assert (= p.newStamps 1) (str p.name ": one new module stamp, lib/a's: " (stringFromInt64 p.newStamps)))
      true)

fn ! reported? p: Probe suffix: String -> Bool
  (do (sound? p)
      (assert (> (diagsIn p.cached suffix) 0) (str p.name ": the importer " suffix " is checked again and its error reported: " (cc/countsText p.cached) "\n" (diagsText p.cached)))
      true)

fn fBody -> String
  "fn f n: Int64 -> Int64\n  (+ n 1)"

fn ! runProbes! ws: String stamps: String -> Bool
  (let [(cold (cached! ws stamps))
        (warm (cached! ws stamps))
        (baseFresh (fresh! ws))]
    (do (assert (listEmpty? cold.diags) (str "the fixture checks clean: " (diagsText cold)))
        (assert (listEmpty? baseFresh.diags) "the fixture checks clean without a cache")
        (assert (= (cc/countsText cold) "(:checked 4 :summarised 0)") (str "the cold run checks every module: " (cc/countsText cold)))
        (assert (= (cc/countsText warm) "(:checked 1 :summarised 3)") (str "the warm run takes the closure stamp: " (cc/countsText warm)))
        (notRechecked? (probe! ws stamps "body-only edit" (list (pair "(+ n 1)" "(+ 1 n)"))))
        (reported? (probe! ws stamps "param type" (list (pair (fBody) "fn f n: String -> Int64\n  (stringLength n)"))) "/pb/b.asl")
        (reported? (probe! ws stamps "return type" (list (pair (fBody) "fn f n: Int64 -> String\n  (stringFromInt64 n)"))) "/pb/b.asl")
        (reported? (probe! ws stamps "arity" (list (pair (fBody) "fn f n: Int64 m: Int64 -> Int64\n  (+ n m)"))) "/pb/b.asl")
        (sound? (probe! ws stamps "omitted return, other body type" (list (pair "(+ n 2)" "(stringFromInt64 n)"))))
        (reported? (probe! ws stamps "record field added" (list (pair "(schema Q (:f q Int64))" "(schema Q (:f q Int64) (:f q2 Int64))"))) "/pb/b.asl")
        (reported? (probe! ws stamps "record field removed" (list (pair "(schema Q (:f q Int64))" "(schema Q (:f q2 Int64))"))) "/pb/b.asl")
        (reported? (probe! ws stamps "record field retyped" (list (pair "(schema Q (:f q Int64))" "(schema Q (:f q String))"))) "/pb/b.asl")
        (reported? (probe! ws stamps "enum case renamed" (list (pair "(:c square [(s Int64)]" "(:c box [(s Int64)]"))) "/pb/b.asl")
        (reported? (probe! ws stamps "enum case field retyped" (list (pair "(:c circle [(r Int64)]" "(:c circle [(r String)]"))) "/pb/b.asl")
        (reported? (probe! ws stamps "inferred effect" (list (pair "(+ n 1)" "(do (println \"x\") (+ n 1))"))) "/pb/b.asl")
        (notRechecked? (probe! ws stamps "private helper signature" (list (pair "fn helper n: Int64 -> Int64\n  (* n 2)" "fn helper n: Int64 m: Int64 -> Int64\n  (* n m)") (pair "(helper 1)" "(helper 1 2)"))))
        (reported? (probe! ws stamps "type reached through pb/b" (list (pair "(schema P (:f x Int64))" "(schema P (:f x String))") (pair "(P :x (helper 1))" "(P :x (stringFromInt64 (helper 1)))"))) "/lib/c.asl")
        (notRechecked? (probe! ws stamps "constant value" (list (pair "fn limit -> Int64\n  3" "fn limit -> Int64\n  4"))))
        true))

fn ! runTests -> Bool
  (let [(work (str "/tmp/aslIfaceKey." (stringFromInt64 (procSelf))))
        (ws (str work "/ws"))
        (made (setup! ws))
        (ran (if made (runProbes! ws (str work "/stamps")) false))
        (cleaned (fr/runGuarded (list "/bin/rm" "-rf" work) "/" (fr/childEnv (list)) (fr/limits 60 4)))]
    (do (assert made (str "the scratch workspace under " work " is created"))
        (assert ran "every probe ran")
        (assert (= cleaned.exitCode 0) "the scratch workspace is removed")
        true))
