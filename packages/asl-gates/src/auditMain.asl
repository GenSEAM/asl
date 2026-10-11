(module asl-gates/auditMain
  :x [runAudit! main]
  :i [(asl-gates/auditGates :a ag)
      (asl-gates/auditForeign :a af)
      (asl-proc/coreProcess :a p)])

fn identLoop bs: Bytes n: Int64 i: Int64 -> Bool
  (if (>= i n)
    true
    (let [(b (bytesGet bs i))]
      (if (or (and (>= b 65) (<= b 90))
              (or (and (>= b 97) (<= b 122))
                  (or (and (>= b 48) (<= b 57))
                      (= b 45))))
        (identLoop bs n (+ i 1))
        false)))

fn isSubcommandIdent? s: String -> Bool
  (let [(n (stringLength s))]
    (if (= n 0)
      false
      (let [(bs (stringToBytes s))
            (b0 (bytesGet bs 0))]
        (if (not (or (and (>= b0 65) (<= b0 90)) (and (>= b0 97) (<= b0 122))))
          false
          (identLoop bs n 1)))))

fn rootArg args: (List String) -> (Option String)
  (mt (listHead args)
    ((none) (none))
    ((some a)
     (if (stringStartsWith? a "--root=")
       (some (optionOr (stringSlice a 7 (stringLength a)) ""))
       (if (= a "--root")
         (listHead (optionOr (listTail args) (list)))
         (rootArg (optionOr (listTail args) (list)))))))

fn stripRootArgs args: (List String) -> (List String)
  (mt (listHead args)
    ((none) (list))
    ((some a)
     (if (= a "--root")
       (stripRootArgs (optionOr (listTail (optionOr (listTail args) (list))) (list)))
       (if (stringStartsWith? a "--root=")
         (stripRootArgs (optionOr (listTail args) (list)))
         (cons a (stripRootArgs (optionOr (listTail args) (list))))))))

fn runAudit! root: String args: (List String) baseEnv: String inRunner: Bool -> ag/AuditRun
  (mt (listHead args)
    ((none)
     (ag/emit "none" (list (ag/failCheck "usage" "ERR_USAGE" "subcommands: build check closure consistency foreign gates steps" (none) (none))) "" "" false))
    ((some sub)
     (if (not (isSubcommandIdent? sub))
       (ag/emit "none" (list (ag/failCheck "usage" "ERR_USAGE" "subcommands: build check closure consistency foreign gates steps" (none) (none))) "" "" false)
       (let [(rest (optionOr (listTail args) (list)))]
         (cond
           ((= sub "consistency") (ag/cmdConsistency! root rest))
           ((= sub "foreign")
            (let [(fr (af/runForeign! root rest baseEnv))]
              (ag/AuditRun :receipt fr.receipt :summary fr.summary :exitCode fr.exitCode)))
           ((= sub "gates") (ag/cmdGatesAt! root rest inRunner))
           ((= sub "closure") (ag/cmdClosure! root rest))
           ((= sub "steps") (ag/cmdSteps! root rest))
           ((= sub "check") (ag/cmdCheck! root rest))
           ((= sub "build") (ag/cmdBuild! root rest))
           (else
            (ag/emit sub (list (ag/coreCheck! root "core" (cons "audit" args))) "" "" false)))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(envRoot (optionOr (envGet "ROOT_DIR") ""))
        (argRoot0 (optionOr (rootArg args) ""))
        (configuredRoot (if (not (stringEmpty? argRoot0)) argRoot0 envRoot))]
  (mt (if (stringEmpty? configuredRoot) (ag/discoverRoot! ".") (ok configuredRoot))
    ((err e)
     (let [(r (ag/emit "none" (list (ag/failCheck "internal" "ERR_AUDIT_INTERNAL" e (none) (none))) "" "" false))]
       (do (eprintln r.summary) (println r.receipt) (ok r.exitCode))))
    ((ok top)
     (let [(r (runAudit! (stringTrim top) (stripRootArgs args) (optionOr (envGet "ASL_FOREIGN_BASE") "") (not (stringEmpty? (optionOr (envGet "ASL_IN_RUNNER") "")))))]
       (do (eprintln r.summary) (println r.receipt) (ok r.exitCode))))))
