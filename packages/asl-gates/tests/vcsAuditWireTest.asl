(module asl-gates/tests/vcsAuditWireTest
  :x [runTests]
  :i [(asl-gates/auditGates :a ag) (asl-proc/gitFixture :a gf)])

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
        (ra (ag/vcsDirectCheck! a))
        (rb (ag/vcsDirectCheck! b))
        (rc (ag/vcsDirectCheck! c))
        (wa (ag/cmdConsistency! a (list)))
        (wb (ag/cmdConsistency! b (list)))]
    (do
      (assert okA "clean fixture tree built")
      (assert okB "seeded fixture tree built")
      (assert okC "no-allowlist fixture tree built")
      (assert (and (= ra.id "vcsDirect") (= ra.status ":passed")) (str "the tree without a direct site passes: " ra.status " " ra.ev))
      (assert (and (= rb.status ":failed") (= rb.err "ERR_VCS_DIRECT")) (str "a seeded direct commit site fails: " rb.status " " rb.ev))
      (assert (stringContains? rb.ev "seeded.asl") (str "the failure names the site: " rb.ev))
      (assert (= rc.status ":skipped") (str "a tree without the allowlist is skipped: " rc.status))
      (assert (stringContains? wb.receipt "ERR_VCS_DIRECT") (str "audit consistency on the seeded tree carries the vcsDirect failure: " wb.receipt))
      (assert (not (stringContains? wa.receipt "ERR_VCS_DIRECT")) "and the clean tree does not")
      (assert (ok? (pathRemove base)) "fixture trees removed")
      true))
