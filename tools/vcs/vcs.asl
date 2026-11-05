(module asl-tools/vcs/vcs
  :x [VcsReceipt head! status! diff! stage! commit! branch! mergeFf! log! isAncestor! receiptOf]
  :i [(asl-tools/vcs/git :a g) (asl-tools/coord/commitGuard :a cg)])

; (:m :ref VCS-LAYER-CORE :do "the backend-neutral version-control API: every op takes a repo root and answers an ASN receipt line; the git backend is vcs/git.asl, the only file that spawns git, so a different backend replaces that one file; commit stages only named paths and refuses when commitGuard blocks or leaves a file unchecked")
(schema VcsReceipt
  (:f code Int64)
  (:f text String))

fn esc s: String -> String
  (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n")

fn receiptOf op: String code: Int64 body: String -> VcsReceipt
  (VcsReceipt :code code :text (str "(:vcs :op :" op " :status :" (if (= code 0) "ok" "failed") body ")"))

fn outReceipt op: String o: g/Out -> VcsReceipt
  (receiptOf op o.exit (str " :exit " (stringFromInt64 o.exit) " :out \"" (esc (g/clean o.out)) "\""))

fn ! head! repo: String -> VcsReceipt
  (outReceipt "head" (g/head! repo))

fn ! status! repo: String paths: (List String) -> VcsReceipt
  (outReceipt "status" (g/changes! repo paths))

fn ! diff! repo: String base: String headRef: String paths: (List String) -> VcsReceipt
  (outReceipt "diff" (g/diff! repo base headRef paths))

fn badPaths paths: (List String) -> (List String)
  (filter (fn [(p String)] -> Bool (not (g/pathOk? p))) paths)

fn refused why: String -> VcsReceipt
  (VcsReceipt :code 1 :text (str "(:vcs :op :stage :status :refused :why \"" (esc why) "\")"))

; (:m :do "stage exactly the named paths; an empty list or a path that could widen the scope is refused and nothing is staged")
fn ! stage! repo: String paths: (List String) -> VcsReceipt
  (cond
    ((listEmpty? paths) (refused "no paths named"))
    ((not (listEmpty? (badPaths paths))) (refused (str "path not accepted: " (stringJoin (badPaths paths) ","))))
    (else (outReceipt "stage" (g/stageNamed! repo paths))))

; (:m :do "commit exactly paths: refuse an empty or widening path list, stage only those paths, run commitGuard judge in process on the staged blobs and the message, refuse on a block or a partial check (mode commit) or record and go on (mode warn), then git commit -- paths; the receipt carries :sha on success and the guard receipt on a refusal")
fn ! commit! repo: String aslRoot: String paths: (List String) msg: String mode: String -> VcsReceipt
  (cond
    ((listEmpty? paths) (VcsReceipt :code 1 :text "(:vcs :op :commit :status :refused :why \"no paths named\")"))
    ((not (listEmpty? (badPaths paths))) (VcsReceipt :code 1 :text (str "(:vcs :op :commit :status :refused :why \"path not accepted: " (esc (stringJoin (badPaths paths) ",")) "\")")))
    (else
      (let [(st (g/stageNamed! repo paths))]
        (if (!= st.exit 0)
          (VcsReceipt :code 1 :text (str "(:vcs :op :commit :status :refused :why \"stage failed: " (esc (g/clean st.out)) "\")"))
          (let [(j (cg/guard! repo aslRoot paths msg (= mode "warn")))]
            (if (= j.code 1)
              (VcsReceipt :code 1 :text (str "(:vcs :op :commit :status :refused :guard " j.text ")"))
              (let [(c (g/commitNamed! repo paths msg))]
                (if (!= c.exit 0)
                  (VcsReceipt :code 1 :text (str "(:vcs :op :commit :status :failed :why \"" (esc (g/clean c.out)) "\")"))
                  (let [(h (g/head! repo))]
                    (VcsReceipt :code 0 :text (str "(:vcs :op :commit :status :done :sha " (g/clean h.out) " :guard " j.text ")")))))))))))

fn ! branch! repo: String name: String base: String -> VcsReceipt
  (outReceipt "branch" (g/branchCreate! repo name base))

fn ! mergeFf! repo: String source: String -> VcsReceipt
  (outReceipt "mergeFf" (g/mergeFf! repo source))

fn ! log! repo: String range: String paths: (List String) fmt: String -> VcsReceipt
  (outReceipt "log" (g/log! repo range paths fmt))

fn ! isAncestor! repo: String a: String b: String -> Bool
  (g/isAncestor! repo a b)
