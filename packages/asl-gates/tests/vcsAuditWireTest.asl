(module asl-gates/tests/vcsAuditWireTest
  :x [runTests]
  :i [(asl-gates/auditGates :a ag) (asl-proc/gitFixture :a gf) (asl-tools/coord/mergeCheck :a mc)])

; (:m :ref VCS-AUDIT-WIRE :do "fixture trees are real repos on main: the same tree without a direct git commit site passes the wired vcsDirect check, with the site seeded it fails naming the site, and a tree with no allowlist skips; verb words are assembled so this file holds no literal site itself")
fn v a: String b: String -> String
  (str a b)

fn ! g root: String args: (List String) -> Bool
  (ok? (gf/gitWrite! root (listAppend (list "-c" "user.name=t" "-c" "user.email=t@example.invalid" "-c" "commit.gpgsign=false") args) (none)))

fn allowText -> String
  "(:vcsDirectAllow :v 2 :src \"VCS-AUDIT-WIRE\" :date \"2026-11-05\" :rule \"fixture\")\n"

fn cleanSrc -> String
  "(module fx/clean\n  :x [f]\n  :i [])\n\nfn f -> Int64\n  1\n"

fn seededSrc -> String
  (str "(module fx/seeded\n  :x [f]\n  :i [])\n\nfn ! f! dir: String -> Bool\n  (ok? (run (list \"/usr/bin/" (v "gi" "t") "\" \"-C\" dir \"" (v "com" "mit") "\" \"-m\" \"x\")))\n")

fn ! tree root: String withAllow: Bool -> Bool
  (and (ok? (gf/initContained! root))
    (and (g root (list (v "check" "out") "-q" "-b" "main"))
      (and (ok? (dirCreate (str root "/.asl/mem")))
        (and (if withAllow (ok? (fileWrite (str root "/.asl/mem/vcsDirectAllow.asn") (stringToBytes (allowText)))) true)
          (and (ok? (fileWrite (str root "/clean.asl") (stringToBytes (cleanSrc))))
            (and (g root (list (v "ad" "d") "-A"))
                 (g root (list (v "com" "mit") "-q" "-m" "base"))))))))

fn ! seed root: String -> Bool
  (and (ok? (fileWrite (str root "/seeded.asl") (stringToBytes (seededSrc))))
       (g root (list (v "ad" "d") "seeded.asl")))

fn ! runTests -> Bool
  (let [(base (str (optionOr (envGet "TMPDIR") "/tmp") "/vcsAuditWireTest-" (stringFromInt64 (procSelf))))
        (a (str base "/clean"))
        (b (str base "/seeded"))
        (c (str base "/noAllow"))
        (okA (and (ok? (dirCreate base)) (tree a true)))
        (okB (and (tree b true) (seed b)))
        (okC (tree c false))
        (ra (ag/vcsDirectCheck! a true))
        (rb (ag/vcsDirectCheck! b true))
        (rc (ag/vcsDirectCheck! c true))
        (d (str base "/deleted"))
        (okD (and (tree d true) (seed d) (g d (list (v "r" "m") "-q" ".asl/mem/vcsDirectAllow.asn"))))
        (rd (ag/vcsDirectCheck! d true))
        (f (str base "/committedDelete"))
        (okF (and (tree f true) (g f (list (v "check" "out") "-q" "-b" "feat")) (g f (list (v "r" "m") "-q" ".asl/mem/vcsDirectAllow.asn")) (seed f) (g f (list (v "com" "mit") "-q" "-m" "del"))))
        (rf (ag/vcsDirectCheck! f true))
        (h (str base "/noMainNoAllow"))
        (okH (and (tree h false) (g h (list (v "bran" "ch") "-m" "dev"))))
        (rh (ag/vcsDirectCheck! h true))
        (j (str base "/unreadable"))
        (okJ (and (tree j true) (ok? (pathRemove (str j "/clean.asl")))))
        (rj (ag/vcsDirectCheck! j true))
        (k (str base "/notGit"))
        (okK (ok? (dirCreate k)))
        (rk (ag/vcsDirectCheck! k true))
        (m (str base "/trackedCache"))
        (okM (and (tree m true) (ok? (dirCreate (str m "/.asl/cache"))) (ok? (fileWrite (str m "/.asl/cache/vcsDirectAudit.v1") (stringToBytes "row"))) (g m (list (v "ad" "d") "-f" ".asl/cache/vcsDirectAudit.v1"))))
        (rm (ag/vcsDirectCheck! m true))
        (e (str base "/noMain"))
        (okE (and (tree e true) (g e (list (v "bran" "ch") "-m" "dev"))))
        (re (ag/vcsDirectCheck! e true))
        (wa (ag/cmdConsistency! a (list "--no-cache")))
        (wb (ag/cmdConsistency! b (list "--no-cache")))
        (store (str base "/store"))
        (warm (ag/cmdConsistency! b (list "--cache-dir" store)))
        (text (resultOr (fileReadString (str store "/vcsDirectAudit.v1")) ""))
        (forged (stringJoin (map (fn [(l String)] -> String (str (optionOr (listGet (stringSplit l "\t") 0) "") "\t")) (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringSplit text "\n"))) "\n"))
        (okForge (ok? (fileWrite (str store "/vcsDirectAudit.v1") (stringToBytes forged))))
        (hid (ag/cmdConsistency! b (list "--cache-dir" store)))
        (shown (ag/cmdConsistency! b (list "--no-cache" "--cache-dir" store)))]
    (do
      (assert okA "clean fixture tree built")
      (assert okB "seeded fixture tree built")
      (assert okC "no-allowlist fixture tree built")
      (assert (and (= ra.id "vcsDirect") (= ra.status ":passed")) (str "the tree without a direct site passes: " ra.status " " ra.ev))
      (assert (and (= rb.status ":failed") (= rb.err "ERR_VCS_DIRECT")) (str "a seeded direct commit site fails: " rb.status " " rb.ev))
      (assert (stringContains? rb.ev "seeded.asl") (str "the failure names the site: " rb.ev))
      (assert okD "deleted-allowlist fixture tree built")
      (assert (and (= rd.status ":failed") (= rd.err "ERR_VCS_ALLOW_DELETED")) (str "a seeded site plus a deleted allowlist stays red: " rd.status " " rd.err))
      (assert okF "committed-delete fixture tree built")
      (assert (and (= rf.status ":failed") (= rf.err "ERR_VCS_ALLOW_DELETED")) (str "a committed delete of the allowlist beside a seeded site is red: " rf.status " " rf.err))
      (assert okH "no-main no-allowlist fixture tree built")
      (assert (and (= rh.status ":failed") (= rh.err "ERR_VCS_NO_MAIN")) (str "an absent allowlist with an unresolvable merge base fails closed: " rh.status " " rh.err))
      (assert okJ "unreadable-file fixture tree built")
      (assert (and (= rj.status ":failed") (= rj.err "ERR_VCS_DIRECT_AUDIT")) (str "a tracked file that cannot be read is an audit error and red: " rj.status " " rj.err))
      (assert okM "tracked-cache fixture tree built")
      (assert (and (= rm.status ":failed") (= rm.err "ERR_VCS_CACHE_TRACKED")) (str "a tracked scan cache is red with its own code: " rm.status " " rm.err))
      (assert (= (mc/cachePaths (list "a.asl" ".asl/cache/x" "t/.asl/cache/y" ".asl/mem/z")) (list ".asl/cache/x" "t/.asl/cache/y")) "mergeCheck names cache paths in a diff")
      (assert (= (mc/auditArgv "bin/asl" "consistency") (list "bin/asl" "audit" "consistency" "--no-cache")) "merge-time consistency runs with the cache off")
      (assert (= (mc/auditArgv "bin/asl" "gates") (list "bin/asl" "audit" "gates")) "other audits are unchanged")
      (assert okK "non-git dir built")
      (assert (and (= rk.status ":failed") (= rk.err "ERR_VCS_NO_MAIN")) (str "a non-git dir names the missing main: " rk.status " " rk.err))
      (assert okE "no-main fixture tree built")
      (assert (and (= re.status ":failed") (= re.err "ERR_VCS_NO_MAIN")) (str "an audit error (base does not resolve) is red: " re.status " " re.err))
      (assert (= rc.status ":skipped") (str "a tree without the allowlist is skipped: " rc.status))
      (assert (stringContains? wb.receipt "ERR_VCS_DIRECT") (str "audit consistency on the seeded tree carries the vcsDirect failure: " wb.receipt))
      (assert (not (stringContains? wa.receipt "ERR_VCS_DIRECT")) "and the clean tree does not")
      (assert (stringContains? warm.receipt "seeded.asl") (str "the warm run names the site: " warm.receipt))
      (assert (and okForge (stringContains? text "commit f!") (not (stringContains? forged "commit"))) "the store holds a row for the site, forged empty")
      (assert (not (stringContains? hid.receipt "ERR_VCS_DIRECT")) (str "with the store read, a forged row hides the site: " hid.receipt))
      (assert (and (stringContains? shown.receipt "ERR_VCS_DIRECT") (stringContains? shown.receipt "seeded.asl")) (str "--no-cache ignores the planted store row and names the site: " shown.receipt))
      (assert (ok? (pathRemove base)) "fixture trees removed")
      true))
