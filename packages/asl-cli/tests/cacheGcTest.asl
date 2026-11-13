(module asl-cli/tests/cacheGcTest
  :x [runTests]
  :i [(asl/packages/asl-cli/src/cacheGc :a cg) (asl/packages/asl-cli/src/nativeCli :a ncli) (asl/packages/asl-cli/src/system :a sys) (asl-tools/fleet/run :a fr)])

; (:m :ref DS-NATIVECACHEGC :do "part one: size and age words and the argument parse; part two: the pure plan on stamped entries (dead origin and older-than first, then oldest until the cap, a leased or fresh entry never); part three: asl cache gc on a scratch store with old mtimes shows a mirror of a deleted root removed without cap pressure, a leased slot kept over the cap, unleased entries dropped until the cap holds, and the sweep lock released; the store lives under TMPDIR, never ~/.asl")
fn ! words -> Bool
  (do (assert (= (cg/sizeValue "2G") (some 2147483648)) "2G")
      (assert (= (cg/sizeValue "10K") (some 10240)) "10K")
      (assert (= (cg/sizeValue "512") (some 512)) "plain bytes")
      (assert (= (cg/sizeValue "lots") (none)) "a word is no size")
      (assert (= (cg/ageValue "7d") (some 604800000000000)) "7d")
      (assert (= (cg/ageValue "90m") (some 5400000000000)) "90m")
      (assert (= (cg/ageValue "5") (none)) "an age needs a unit")
      (let [(a (cg/parseArgs "/r" (list) 99))
            (b (cg/parseArgs "/r" (list "--dir" "/s" "--cap" "1M" "--older-than" "2h" "--dry-run") 99))
            (c (cg/parseArgs "/r" (list "--cap" "huge") 99))
            (d (cg/parseArgs "/r" (list "--bogus") 99))
            (up (cg/parseArgs "/r" (list "--release" "..") 99))
            (sl (cg/parseArgs "/r" (list "--release" "v1/../..") 99))
            (rel (cg/parseArgs "/r" (list "--release" "v0.0.5") 99))]
        (do (assert (and (= a.dir "/r/.asl/cache/nativeTest") (= a.capBytes 99)) "the default is the tree's own cache and the configured cap")
            (assert (and (= b.dir "/s") (and (= b.capBytes 1048576) (and (= b.olderNs 7200000000000) b.dryRun))) "every flag parsed")
            (assert (stringContains? c.error "--cap") "a bad cap is a usage error")
            (assert (stringContains? d.error "--bogus") "an unknown flag is a usage error")
            (assert (and (stringContains? up.error "--release") (stringContains? sl.error "--release")) "a --release of .. or with a slash is a usage error")
            (assert (and (stringEmpty? rel.error) (stringEndsWith? rel.dir "/.asl/releases/v0.0.5/.asl/cache/nativeTest")) "a plain version names its release cache")
            true)))

fn entry name: String stamp: Int64 bytes: Int64 pinned: Bool -> ncli/StoreEntry
  (ncli/StoreEntry :paths (list name) :stamp stamp :bytes bytes :pinned pinned)

fn names es: (List ncli/StoreEntry) -> (List String)
  (listSort (map (fn [(e ncli/StoreEntry)] -> String (optionOr (listHead e.paths) "")) es))

fn ! plans -> Bool
  (let [(now 100000000000000)
        (hour 3600000000000)
        (tagged (list (pair (entry "a" (- now (* 5 hour)) 100 false) false)
                      (pair (entry "b" (- now (* 4 hour)) 200 false) false)
                      (pair (entry "c" (- now 1000000000) 500 false) false)
                      (pair (entry "d" (- now (* 9 hour)) 300 true) false)
                      (pair (entry "e" (- now (* 2 hour)) 50 false) true)))
        (fresh 600000000000)
        (capped (cg/planGc tagged now 400 4611686018427387904 fresh))
        (aged (cg/planGc tagged now 100000 (* 3 hour) fresh))
        (roomy (cg/planGc tagged now 100000 4611686018427387904 fresh))
        (slow (cg/planGc tagged now 400 4611686018427387904 (* 3 hour)))]
    (do (assert (= (names capped.drop) (list "a" "b" "e")) (str "over the cap: the dead-origin entry and the oldest unprotected ones go, the fresh and the leased stay: " (stringJoin (names capped.drop) " ")))
        (assert (= (ncli/storeBytes capped.keep) 800) "the rest is protected, so the kept bytes may stay over the cap")
        (assert (= (names aged.drop) (list "a" "b" "e")) "older than 3 h goes without cap pressure, the leased old one stays")
        (assert (= (names roomy.drop) (list "e")) "under the cap only the dead-origin entry goes")
        (assert (and (= roomy.deadOrigin 1) (= roomy.pinned 2)) "the plan counts dead-origin and protected entries")
        (assert (= (names slow.drop) (list "a" "b")) (str "a :storeMinAge of 3 h protects the 2 h old dead-origin entry the 600 s default would drop: " (stringJoin (names slow.drop) " ")))
        (assert (stringContains? (cg/receipt (cg/GcArgs :dir "/s" :capBytes 400 :olderNs 0 :dryRun false :error "") capped 3 350) ":freedBytes 350") "the receipt names the freed bytes")
        true))

fn ! sh! argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv "." (list (str "PATH=" (optionOr (envGet "PATH") "/usr/bin:/bin")))) (fr/limits 60 20))

fn hex c: String -> String
  (stringJoin (map (fn [(i Int64)] -> String c) (range 0 64)) "")

fn ! put! path: String bytes: Int64 -> Bool
  (ok? (fileWrite path (stringJoin (map (fn [(i Int64)] -> String "x") (range 0 bytes)) "")))

fn ! store! base: String -> String
  (let [(s (str base "/store"))
        (slotA (str s "/" (hex "a") "/" (hex "1")))
        (slotB (str s "/" (hex "a") "/" (hex "2")))
        (deadPkg (str s "/outsidePkg/" (hex "d")))
        (livePkg (str s "/outsidePkg/" (hex "e")))
        (_ (sh! (list "/bin/mkdir" "-p" slotA slotB deadPkg livePkg (str s "/modules") (str base "/liveRoot"))))
        (_ (put! (str slotA "/bin") 3000))
        (_ (put! (str slotB "/bin") 3000))
        (_ (fileWrite (str slotB "/lock") (stringFromInt64 (procSelf))))
        (_ (put! (str deadPkg "/m.asl") 200))
        (_ (cg/recordOrigin! deadPkg (str base "/goneRoot")))
        (_ (put! (str livePkg "/m.asl") 200))
        (_ (cg/recordOrigin! livePkg (str base "/liveRoot")))
        (_ (put! (str s "/modules/" (hex "f") ".o") 1000))
        (_ (put! (str s "/modules/" (hex "c") ".o") 1000))
        (_ (fileWrite (str s "/modules/" (hex "c") ".o.lock") (stringFromInt64 (procSelf))))
        (_ (sh! (list "/usr/bin/find" s "-exec" "/usr/bin/touch" "-h" "-t" "202601010000" "{}" "+")))]
    s)

fn ! gc! base: String args: (List String) -> Int64
  (cg/cacheCmd! (sys/Context :root base :scriptDir "" :argv0 "" :hostBin "") (cons "gc" args))

fn ! runs base: String -> Bool
  (let [(s (store! base))
        (slotA (str s "/" (hex "a") "/" (hex "1")))
        (slotB (str s "/" (hex "a") "/" (hex "2")))
        (deadPkg (str s "/outsidePkg/" (hex "d")))
        (livePkg (str s "/outsidePkg/" (hex "e")))
        (roomy (gc! base (list "--dir" s "--cap" "1G")))
        (deadGone (not (fileExists? deadPkg)))
        (restKept (and (fileExists? slotA) (fileExists? livePkg)))
        (dry (gc! base (list "--dir" s "--cap" "1" "--dry-run")))
        (dryKept (and (fileExists? slotA) (fileExists? livePkg)))
        (tight (gc! base (list "--dir" s "--cap" "1")))
        (lockFree (not (fileExists? (str s "/sweep.lock"))))
        (busyLock (fileWrite (str s "/sweep.lock") (stringFromInt64 (procSelf))))
        (busy (gc! base (list "--dir" s)))
        (usage (gc! base (list "--cap" "lots")))
        (verb (cg/cacheCmd! (sys/Context :root base :scriptDir "" :argv0 "" :hostBin "") (list "purge")))]
    (do (assert (= roomy 0) "gc under the cap exits 0")
        (assert deadGone "the mirror of a deleted root is removed without cap pressure")
        (assert restKept "nothing else goes under the cap")
        (assert (and (= dry 0) dryKept) "a dry run removes nothing")
        (assert (= tight 0) "gc over the cap exits 0")
        (assert (and (not (fileExists? slotA)) (and (not (fileExists? livePkg)) (not (fileExists? (str s "/modules/" (hex "f") ".o"))))) "over the cap every unleased old entry goes")
        (assert (fileExists? (str slotB "/bin")) "the slot a live run leases stays")
        (assert (fileExists? (str s "/modules/" (hex "c") ".o")) "a module object whose KEY.o.lock a live compile holds stays")
        (assert lockFree "gc releases sweep.lock")
        (assert (and (ok? busyLock) (= busy 1)) "a held sweep.lock is a busy exit 1")
        (assert (= usage 2) "a bad flag is exit 2")
        (assert (= verb 2) "a sub command other than gc is exit 2")
        true))

; (:m :ref DS-NATIVECACHEGC :do "re-stamp: a plan made from old stamps drops both entries, one file is then touched as a concurrent build would, and applyGc! keeps it and removes only the untouched one")
fn ! restamp base: String -> Bool
  (let [(d (str base "/restamp"))
        (_ (sh! (list "/bin/mkdir" "-p" d)))
        (_ (put! (str d "/kept.o") 100))
        (_ (put! (str d "/gone.o") 100))
        (_ (sh! (list "/usr/bin/find" d "-exec" "/usr/bin/touch" "-h" "-t" "202601010000" "{}" "+")))
        (es (map (fn [(n String)] -> ncli/StoreEntry (ncli/storeEntry! (list (str d "/" n)) false)) (list "kept.o" "gone.o")))
        (plan (cg/planGc (map (fn [(e ncli/StoreEntry)] -> (Pair ncli/StoreEntry Bool) (pair e false)) es) (nowNs) 0 4611686018427387904 600000000000))
        (touched (fileUtime (str d "/kept.o") (nowNs)))
        (done (cg/applyGc! plan 600000000000))]
    (do (assert (= (listLength plan.drop) 2) "the plan from old stamps drops both")
        (assert (ok? touched) "one entry is touched after the plan")
        (assert (and (fileExists? (str d "/kept.o")) (not (fileExists? (str d "/gone.o")))) "applyGc! re-stamps: the touched entry stays, the untouched one goes")
        (assert (= (pairFirst done) 1) "one entry removed")
        true))

; (:m :ref DS-NATIVECACHEGC :do "the configured minimum age reaches asl cache gc: a root whose .asl.config.asn sets :native :storeMinAge 48h keeps an entry last touched a day ago even over the cap, which the 60m default and a zero age would remove, and removes the entry from 2026-01-01")
fn ! configuredAge base: String -> Bool
  (let [(r (str base "/ageRoot"))
        (s (str r "/store"))
        (dayOld (str s "/outside/" (hex "1")))
        (old (str s "/outside/" (hex "2")))
        (_ (sh! (list "/bin/mkdir" "-p" (str s "/outside"))))
        (cfg (fileWrite (str r "/.asl.config.asn") "(:aslConfig :native (:storeMinAge 48h))\n"))
        (_ (put! dayOld 100))
        (_ (put! old 100))
        (_ (sh! (list "/usr/bin/touch" "-t" "202601010000" old)))
        (dayTouch (fileUtime dayOld (- (nowNs) 86400000000000)))
        (code (gc! r (list "--dir" s "--cap" "1")))]
    (do (assert (and (ok? cfg) (ok? dayTouch)) "the configured root and the day-old entry were made")
        (assert (= code 0) "gc on the configured store exits 0")
        (assert (fileExists? dayOld) "an entry a day old stays under a configured :storeMinAge of 48h, even over the cap")
        (assert (not (fileExists? old)) "the old entry still goes")
        true))

fn ! runTests -> Bool
  (let [(base0 (optionOr (listHead (filter (fn [(x String)] -> Bool (not (stringEmpty? x))) (list (optionOr (envGet "ASL_RUN_TMP") "") (optionOr (envGet "TMPDIR") "")))) "/tmp"))
        (base (str base0 "/cacheGcTest-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (ok1 (words))
        (ok2 (plans))
        (ok3 (runs base))
        (ok4 (restamp base))
        (ok5 (configuredAge base))
        (_ (sh! (list "/bin/rm" "-rf" "--" base)))]
    (do (assert (not (fileExists? base)) "the scratch store is removed")
        (and ok1 (and ok2 (and ok3 (and ok4 ok5))))))
