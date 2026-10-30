(module asl-target-llvm/tests/recordLayoutRtTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/libc :a libc)
      (asl-tools/fleet/run :a fr)])

; (:m :ref UFRT :do "runtime side of unboxed record fields: a program's boxed Mix twin is copied by the hand-built fixtures/recordLayout/rtRawRec.ll into the descriptor layout (tagged keys word, nb 1, raw Int64/Float64/Bool words); objrt.field, the formatter, valEq and parMap serialization must treat the raw record exactly as its boxed twin")

fn clang -> String
  "/usr/bin/clang -Wno-override-module"

fn lib -> String
  "asl/host/out/libaslrt.a"

fn fixtureLl -> String
  "asl/packages/asl-target-llvm/tests/fixtures/recordLayout/rtRawRec.ll"

fn ! sh cmd: String -> fr/Done
  (fr/runShell! cmd "." (fr/childEnv (list)) (fr/limits 120 8))

fn ! hostTriple -> String
  (let [(k (stringReplace (sh "uname -s").out "\n" ""))
        (m (stringReplace (sh "uname -m").out "\n" ""))]
    (cond
      ((and (= k "Darwin") (= m "arm64")) "darwin-arm64")
      ((and (= k "Linux") (= m "x86_64")) "linux-x86_64")
      ((and (= k "Linux") (or (= m "aarch64") (= m "arm64"))) "linux-aarch64")
      (else "")))

fn ! hostFacts -> libc/TripleFacts
  (match (libc/libcFacts (hostTriple))
    ((some f) f)
    ((none) (do (assert false (str "hostFacts: libc.asl has no row for this host's triple \"" (hostTriple) "\"")) (libc/emptyTripleFacts))))

fn lines xs: (List String) -> String
  (str (stringJoin xs "\n") "\n")

fn diagText ds: (List ty/IrDiag) -> String
  (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.message)) ds) "; ")

fn source -> String
  (lines (list
    "(module ufrtRec :x [main] :i [])"
    ""
    "schema Mix"
    "  a: Int64"
    "  s: String"
    "  f: Float64"
    "  b: Bool"
    ""
    "fn nanWithPayload k: Int64 -> Float64"
    "  (let [(b (bytesAlloc 8))]"
    "    (do (bytesSet b 0 k) (bytesSet b 6 248) (bytesSet b 7 127)"
    "        (bytesGetFloat64 b 0)))"
    ""
    "fn twin a: Int64 f: Float64 b: Bool -> Mix"
    "  (Mix :a a :s (str \"s\" a) :f f :b b)"
    ""
    "fn rawOf m: Mix -> Any"
    "  m"
    ""
    "fn getA x: Any -> Any"
    "  x.a"
    ""
    "fn getS x: Any -> Any"
    "  x.s"
    ""
    "fn getF x: Any -> Any"
    "  x.f"
    ""
    "fn getB x: Any -> Any"
    "  x.b"
    ""
    "fn pick i: Int64 r: Any q: Any -> Any"
    "  (if (= i 0) r q)"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(t (twin 7 -0.0 true)) (r (rawOf t))"
    "        (u (twin -3 1.5 false)) (q (rawOf u))"
    "        (n (twin 1 (nanWithPayload 1) true)) (rn (rawOf n))]"
    "    (do (println \"print\" r q)"
    "        (println \"printTwin\" (= (str r) (str t)) (= (str q) (str u)) (= (str rn) (str n)))"
    "        (println \"eq\" (= r t) (= t r) (= r r) (= q u) (= r (rawOf (twin 7 0.0 true))))"
    "        (println \"ne\" (= r u) (= r q) (!= r t) (= r (rawOf (twin 8 -0.0 true))) (= r (rawOf (twin 7 -0.0 false))))"
    "        (println \"nan\" (= rn n) (= n n) (= rn rn))"
    "        (println \"fields\" (getA r) (getS r) (getF r) (getB r) (getA q) (getF q) (getB q))"
    "        (println \"bool\" (if (getB r) 1 0) (if (getB q) 1 0))"
    "        (println \"par\" (= (parMap (fn [(i Int64)] -> Any (pick i r q)) (list 0 1) 2) (list t u)))"
    "        (println \"parPrint\" (parMap (fn [(i Int64)] -> Any (pick i r q)) (list 0 1) 2))"
    "        (ok 0)))"))

fn expected -> String
  (lines (list
    "print {:a 7 :s \"s7\" :f -0.0 :b true} {:a -3 :s \"s-3\" :f 1.5 :b false}"
    "printTwin true true true"
    "eq true true true true true"
    "ne false false false false false"
    "nan false false false"
    "fields 7 s7 -0.0 true -3 1.5 false"
    "bool 1 0"
    "par true"
    "parPrint ({:a 7 :s \"s7\" :f -0.0 :b true} {:a -3 :s \"s-3\" :f 1.5 :b false})"))

fn header text: String name: String -> (Option Int64)
  (stringIndexOf text (str "define tailcc %Val @" name "("))

fn patched text: String -> (Option String)
  (match (header text "rawOf")
    ((none) (none))
    ((some i)
      (let [(rest (optionOr (stringSlice text i (stringLength text)) ""))]
        (match (stringIndexOf rest "\n}\n")
          ((none) (none))
          ((some j)
            (let [(open (optionOr (stringIndexOf rest "{") 0))
                  (head (optionOr (stringSlice rest 0 (+ open 1)) ""))
                  (before (optionOr (stringSlice text 0 i) ""))
                  (after (optionOr (stringSlice rest (+ j 3) (stringLength rest)) ""))]
              (some (str before head "\nentry:\n  %ufrt.raw = call %Val @ufrtRawMake(%Val %m)\n  ret %Val %ufrt.raw\n}\n" after
                         "declare %Val @ufrtRawMake(%Val)\n"))))))))

fn ! emitted -> String
  (let [(preludeText (resultOr (fileReadString (lk/preludePath)) ""))]
    (do (assert (not (stringEmpty? preludeText)) (str (lk/preludePath) " is readable"))
        (match (lk/lowerSourceWith (source) preludeText)
          ((err ds) (do (assert false (str "lowerSourceWith: " (diagText ds))) ""))
          ((ok m) (match (llvm/emitLlvmProgramFor (hostFacts) m "main")
                    ((err ds) (do (assert false (str "emitLlvmProgramFor: " (diagText ds))) ""))
                    ((ok text) text))))))

fn ! runTests -> Bool
  (let [(text (emitted))
        (made (sh "mktemp -d"))
        (work (stringReplace made.out "\n" ""))]
    (do (assert (= made.exit 0) "mktemp -d makes a work directory")
        (assert (stringContains? text "call tailcc %Val @rawOf(") (str "callers call rawOf, so the patch reaches them"))
        (match (patched text)
          ((none) (do (assert false "rawOf definition is found and patched") false))
          ((some ll)
            (let [(llFile (str work "/ufrtRec.ll")) (bin (str work "/ufrtRec"))]
              (do (assert (ok? (fileWrite llFile ll)) "patched IR written")
                  (let [(link (sh (str (clang) " -x ir " llFile " " (fixtureLl) " -x none " (lib) " -lm -o " bin)))]
                    (do (assert (= link.exit 0) (str "links with the raw-record fixture: " link.out))
                        (let [(out (sh bin))
                              (want (stringSplit (expected) "\n"))
                              (got (stringSplit out.out "\n"))]
                          (do (assert (= out.exit 0) (str "program exits 0; stderr: " out.out))
                              (map (fn [(i Int64)] -> Bool
                                     (do (assert (= (listGet got i) (listGet want i))
                                                 (str "line " i ": got " (optionOr (listGet got i) "<none>") " want " (optionOr (listGet want i) "<none>")))
                                         true))
                                   (range 0 9))
                              (assert (= (listLength got) (listLength want)) (str "line count " (listLength got) "; stdout:\n" out.out))
                              true))))))))
        (assert (= (sh (str "rm -rf " work)).exit 0) "work directory removed")
        true))
