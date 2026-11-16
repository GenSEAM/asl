(module asl-checker/tests/moduleStampTest
  :x [runTests]
  :i [(asl-checker/checkCached :a cc) (asl-checker/types :a ty) (asl-tools/fleet/run :a fr)])

; (:m :ref TRAIN-SUITE-FRONTEND-SHARE :do "a body checked clean under one root is stamped on its own and summarised under another root whose closure differs; an edit to a dependency re-keys every module that imports it, so an importer made ill-typed by the edit is checked again and reported, and a dirty body is never stamped")
fn leafSrc body: String ret: String -> String
  (str "(module lib/leaf :x [base] :i [])\n\nfn base -> " ret "\n  " body "\n")

fn midSrc -> String
  "(module lib/mid :x [twice] :i [(lib/leaf :a l)])\n\nfn twice -> Int64\n  (l/base)\n"

fn otherSrc -> String
  "(module lib/other :x [one] :i [])\n\nfn one -> Int64\n  1\n"

fn ! verdictOf! path: String stamps: String -> cc/Verdict
  (resultOr (pairFirst (cc/checkFileCached! path (list) (cc/stampCacheAt stamps "cli-0000000000000000000000000000000000000000000000000000000000000003")))
            (cc/Verdict :diags (list) :checked -1 :summarised -1))

fn ! setup! ws: String -> Bool
  (and (ok? (dirCreate (str ws "/lib")))
       (and (ok? (fileWrite (str ws "/.asl.config.asn") "(:asl-config :workspace \"moduleStamp\" :version \"1.0.0\")\n"))
            (and (ok? (fileWrite (str ws "/lib/leaf.asl") (leafSrc "7" "Int64")))
                 (and (ok? (fileWrite (str ws "/lib/mid.asl") (midSrc)))
                      (and (ok? (fileWrite (str ws "/lib/other.asl") (otherSrc)))
                           (and (ok? (fileWrite (str ws "/a.asl") "(module a :x [main] :i [(lib/mid :a m)])\n\nfn main -> Int64\n  (m/twice)\n"))
                                (ok? (fileWrite (str ws "/b.asl") "(module b :x [main] :i [(lib/mid :a m) (lib/other :a o)])\n\nfn main -> Int64\n  (+ (m/twice) (o/one))\n"))))))))

fn ! verdictFiles dir: String -> Int64
  (listLength (filter (fn [(n String)] -> Bool (stringEndsWith? n ".verdict")) (resultOr (dirList dir) (list))))

fn inMid v: cc/Verdict -> Int64
  (listLength (filter (fn [(d ty/Diagnostic)] -> Bool (stringEndsWith? d.path "/lib/mid.asl")) v.diags))

fn ! testShareAndRekey ws: String stamps: String -> Bool
  (let [(first (verdictOf! (str ws "/a.asl") stamps))
        (modStamps (verdictFiles (str stamps "/modules")))
        (closureStamps (verdictFiles stamps))
        (second (verdictOf! (str ws "/b.asl") stamps))
        (otherId (verdictOfId! (str ws "/b.asl") stamps "cli-0000000000000000000000000000000000000000000000000000000000000004"))
        (edited (fileWrite (str ws "/lib/leaf.asl") (leafSrc "\"7\"" "String")))
        (afterEdit (verdictOf! (str ws "/a.asl") stamps))
        (again (verdictOf! (str ws "/a.asl") stamps))]
    (do (assert (listEmpty? first.diags) "the clean closure of a checks clean")
        (assert (= (cc/countsText first) "(:checked 3 :summarised 0)") (str "the first root checks a, mid and leaf: " (cc/countsText first)))
        (assert (= modStamps 2) (str "mid and leaf are stamped on their own: " (stringFromInt64 modStamps)))
        (assert (= closureStamps 1) (str "the closure stamps stay apart from the module stamps: " (stringFromInt64 closureStamps)))
        (assert (listEmpty? second.diags) "the closure of b checks clean")
        (assert (= (cc/countsText second) "(:checked 2 :summarised 2)") (str "a second root with another closure checks only b and other, mid and leaf are summarised from their stamps: " (cc/countsText second)))
        (assert (= (cc/countsText otherId) "(:checked 4 :summarised 0)") (str "another checker build trusts no module stamp: " (cc/countsText otherId)))
        (assert (ok? edited) "leaf is edited to return a String")
        (assert (> (inMid afterEdit) 0) (str "mid, made ill-typed by the edit to leaf, is checked again and reported: " (stringFromInt64 (listLength afterEdit.diags)) " diagnostics"))
        (assert (= (cc/countsText afterEdit) "(:checked 3 :summarised 0)") (str "the edit re-keys leaf and its importer mid: " (cc/countsText afterEdit)))
        (assert (> (inMid again) 0) "a dirty body is never stamped, so the next run reports mid again")
        (assert (= (cc/countsText again) "(:checked 2 :summarised 1)") (str "the re-keyed clean leaf is summarised from its new stamp and the dirty mid is checked again: " (cc/countsText again)))
        true))

fn ! verdictOfId! path: String stamps: String id: String -> cc/Verdict
  (resultOr (pairFirst (cc/checkFileCached! path (list) (cc/stampCacheAt stamps id)))
            (cc/Verdict :diags (list) :checked -1 :summarised -1))

fn manifestSrc pure: Bool -> String
  (str "(:package p :version \"0.1.0\"" (if pure " :pure true" "") ")\n")

fn ! setupPure! ws: String -> Bool
  (and (ok? (dirCreate (str ws "/p")))
       (and (ok? (dirCreate (str ws "/q")))
            (and (ok? (fileWrite (str ws "/.asl.config.asn") "(:asl-config :workspace \"moduleStampPure\" :version \"1.0.0\")\n"))
                 (and (ok? (fileWrite (str ws "/p/manifest.asn") (manifestSrc false)))
                      (and (ok? (fileWrite (str ws "/p/eff.asl") "(module p/eff :x [say] :i [])\n\nfn say -> Int64\n  (do (println \"x\") 1)\n"))
                           (and (ok? (fileWrite (str ws "/q/one.asl") "(module q/one :x [one] :i [])\n\nfn one -> Int64\n  1\n"))
                                (and (ok? (fileWrite (str ws "/a.asl") "(module a :x [main] :i [(p/eff :a e)])\n\nfn main -> Int64\n  (e/say)\n"))
                                     (ok? (fileWrite (str ws "/b.asl") "(module b :x [main] :i [(p/eff :a e) (q/one :a o)])\n\nfn main -> Int64\n  (+ (e/say) (o/one))\n")))))))))

fn inEff v: cc/Verdict -> Int64
  (listLength (filter (fn [(d ty/Diagnostic)] -> Bool (stringEndsWith? d.path "/p/eff.asl")) v.diags))

; (:m :ref TRAIN-SUITE-FRONTEND-SHARE :do "the :pure flag of the nearest manifest.asn changes a body verdict (rule 12), so turning it on re-keys the module and closure stamps: a body stamped clean while impure is checked again and reported, under a new root and under the root that stamped it")
fn ! testPureFlag ws: String stamps: String -> Bool
  (let [(impure (verdictOf! (str ws "/a.asl") stamps))
        (flipped (fileWrite (str ws "/p/manifest.asn") (manifestSrc true)))
        (direct (verdictOf! (str ws "/p/eff.asl") (str stamps "-direct")))
        (other (verdictOf! (str ws "/b.asl") stamps))
        (same (verdictOf! (str ws "/a.asl") stamps))]
    (do (assert (listEmpty? impure.diags) (str "an effect in an impure package checks clean: " (stringFromInt64 (listLength impure.diags)) " diagnostics"))
        (assert (ok? flipped) "the package manifest is set :pure true")
        (assert (> (listLength direct.diags) 0) "checked on its own, the effect in a pure package is reported")
        (assert (> (inEff other) 0) (str "a new root does not take the impure stamp of p/eff: " (cc/countsText other)))
        (assert (> (inEff same) 0) (str "the root that stamped the closure while impure does not take that stamp either: " (cc/countsText same)))
        true))

fn ! runTests -> Bool
  (let [(work (str "/tmp/aslModuleStamp." (stringFromInt64 (procSelf))))
        (ws (str work "/ws"))
        (stamps (str work "/stamps"))
        (made (setup! ws))
        (shared (if made (testShareAndRekey ws stamps) false))
        (wsPure (str work "/pure"))
        (madePure (setupPure! wsPure))
        (pure (if madePure (testPureFlag wsPure (str work "/pureStamps")) false))
        (cleaned (fr/runGuarded (list "/bin/rm" "-rf" work) "/" (fr/childEnv (list)) (fr/limits 60 4)))]
    (do (assert made (str "the scratch workspace under " work " is created"))
        (assert shared "module stamps are shared across roots and re-keyed by a dependency edit")
        (assert madePure "the pure-flag workspace is created")
        (assert pure "the manifest :pure flag is part of every stamp key")
        (assert (= cleaned.exitCode 0) "the scratch workspace is removed")
        true))
