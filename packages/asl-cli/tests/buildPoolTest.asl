(module asl-cli/tests/buildPoolTest
  :x [runTests]
  :i [(asl/packages/asl-cli/src/nativeBuild :a nb)
      (asl-tools/fleet/run :a run)])

; (:m :ref WT-SHARED-CLI-BUILD :do "gate for the node build pool: with the pool's one token held by a live fixture holder, nb/linkParts! compiles no part and links nothing until the holder has released it, so the link returns only after the holder's release mark exists; the link still builds the program through two parts, holds no token or ticket afterwards, and the pool size follows the :native :buildTokens row")
fn program -> String
  (stringJoin (list
    "@str.1 = private unnamed_addr constant [11 x i8] c\"pool %lld\\0A\\00\""
    ""
    "declare i32 @printf(ptr, ...)"
    ""
    "define i64 @twice(i64 %x) {"
    "entry:"
    "  %y = mul i64 %x, 2"
    "  ret i64 %y"
    "}"
    ""
    "define i32 @main() {"
    "entry:"
    "  %v = call i64 @twice(i64 21)"
    "  %p = call i32 (ptr, ...) @printf(ptr @str.1, i64 %v)"
    "  ret i32 0"
    "}"
    "") "\n")

fn ! entries dir: String -> Int64
  (listLength (resultOr (dirList dir) (list)))

fn ! removeAll! path: String -> (Result Unit String)
  (if (fileExists? path)
    (match (dirList path)
      ((ok names) (do (map (fn [(n String)] -> (Result Unit String) (removeAll! (str path "/" n))) names) (pathRemove path)))
      ((err _) (pathRemove path)))
    (ok ()))

fn ! waitHolder! g: run/Guarded -> run/ProcOut
  (let [(st (run/guardAdvance! g))]
    (match st.out
      ((some o) o)
      ((none) (do (sleepMs 20) (waitHolder! st.guard)))))

fn ! ownerPid! path: String tries: Int64 -> Int64
  (match (stringToInt64 (stringTrim (resultOr (fileReadString path) "")))
    ((some p) p)
    ((none) (if (<= tries 0) 0 (do (sleepMs 20) (ownerPid! path (- tries 1))))))

fn ! testConfig work: String -> Bool
  (let [(dir (str work "/cfg"))
        (_ (dirCreate dir))
        (_ (fileWrite (str dir "/.asl.config.asn") (str "(:aslConfig :native (:buildPool \"" dir "/pool\" :buildTokens 3))\n")))
        (pool (nb/buildPoolFor! dir))
        (odd (str work "/odd"))
        (_ (dirCreate odd))
        (_ (fileWrite (str odd "/.asl.config.asn") (str "(:aslConfig :native (:buildPool \"" odd "/pool\" :buildTokens 99))\n")))
        (oddPool (nb/buildPoolFor! odd))]
    (do (assert (= pool (str dir "/pool")) (str "the :buildPool row names the pool root: " pool))
        (assert (= (resultOr (fileReadString (str pool "/config.asn")) "") "(:jobserver :tokens 3)\n") "the :buildTokens row sets the pool's token count")
        (assert (= (resultOr (fileReadString (str oddPool "/config.asn")) "") "(:jobserver :tokens 2)\n") "an out-of-range :buildTokens falls back to 2 tokens")
        (assert (= (nb/buildTokensValue "64") (some 64)) "64 tokens is accepted")
        (assert (= (nb/buildTokensValue "0") (none)) "0 tokens is rejected")
        true))

fn ! testHeld root: String work: String -> Bool
  (let [(dir (str work "/held"))
        (pool (str dir "/pool"))
        (_ (dirCreate dir))
        (_ (fileWrite (str dir "/.asl.config.asn") (str "(:aslConfig :native (:buildPool \"" pool "\" :buildTokens 1))\n")))
        (_ (nb/buildPoolFor! dir))
        (_ (dirCreate (str pool "/tokens")))
        (ll (str dir "/program.ll"))
        (_ (fileWrite ll (program)))
        (tok (str pool "/tokens/tok0"))
        (released (str dir "/released"))
        (ownerFile (str dir "/owner"))
        (b (nb/Build :root dir :cache dir :tmp dir :lib (str root "/asl/host/out/libaslrt.a") :base "" :clangVersion "" :owner ""
                     :deadlineNs (+ (monotonicNs) 120000000000) :maxDesc 16))
        (started (run/guardStart! (list "/bin/sh" "-c" "sleep \"$0\" & echo $! > \"$3\"; wait; : > \"$1\"; rm -f \"$2\"" "6" released tok ownerFile) "/" (run/childEnv (list)) (run/limits 60 4)))]
    (match started
      ((err _) (do (assert false "the token holder started") false))
      ((ok g) (let [(owner (ownerPid! ownerFile 500))
                    (_ (fileWrite tok (str "(:tok :ownerPid " (stringFromInt64 owner) " :ownerStart \"\" :childPid 0 :startNs 0 :class \"writer\")\n")))
                    (linked (nb/linkParts! b "clang" (list "-O1") ll (str dir "/program.bin") 2))
                    (afterRelease (fileExists? released))
                    (holder (waitHolder! g))
                    (ran (run/runOneLimited (run/job (list (str dir "/program.bin")) dir (list)) (run/limits 30 4)))]
                (do (assert (> owner 1) "the holder's sleep pid owns the token")
                    (assert (= holder.exitCode 0) (str "the holder ran to its release: " holder.stderr))
                    (assert afterRelease "with the pool's only token held, the link returns only after the holder has released it")
                    (assert (match linked ((ok shape) (= (pairFirst shape) 2)) ((err e) (do (eprintln e) false))) "the held link still builds through two parts")
                    (assert (= (stringTrim ran.out) "pool 42") (str "the linked program runs: " ran.out))
                    (assert (= (entries (str pool "/tokens")) 0) "the link holds no pool token afterwards")
                    (assert (= (entries (str pool "/wait")) 0) "the link leaves no waiting ticket")
                    true)))))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (work (str root "/.asl/cache/buildPoolTest." (stringFromInt64 (procSelf))))
        (_ (dirCreate (str root "/.asl/cache")))
        (made (dirCreate work))
        (config (if (ok? made) (testConfig work) false))
        (held (if (ok? made) (testHeld root work) false))
        (cleaned (removeAll! work))]
    (do (assert (ok? made) (str "the work directory " work " was created"))
        (assert config "the pool rows are read")
        (assert held "the held pool orders the link after the release")
        (assert (ok? cleaned) "the work directory was removed")
        true))
