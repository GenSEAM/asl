(module asl-cli/heal
  :x [runHealCommand! formatHealHelp healTarget maxAttempts]
  :i [(asl-forms/heal :a heal) (asl/packages/asl-cli/src/verify :a verify)])

; (:m :do "asl heal FILE: runs the one heal pipeline (asl-forms/heal) on an .asl file and writes the repaired text back unless --dry-run; a file that already checks is left byte-identical; exit 0 when nothing is left over or only the rule-13 lint, which asl check does not report")

fn formatHealHelp -> String
  (str "Usage: asl heal [--dry-run] [--max-attempts=<n>] <file.asl>\n\n"
       "Repairs generated ASL with named rules (" (stringJoin (heal/healRuleNames) " ") "); an edit is kept only when it lowers the checker's diagnostics.\n"
       "A file that already checks is never changed. Prints (:heal :file F :written B :repaired (rule ...) :left (diag ...)); exit 1 when diagnostics other than the rule-13 lint are left.\n"
       "  --dry-run            report the repairs without writing the file\n"
       "  --max-attempts=<n>   cap the rule applications (default 24)\n")

fn healTarget args: (List String) -> (Option String)
  (listLast (filter (fn [(a String)] -> Bool (not (stringStartsWith? a "-"))) args))

fn maxAttempts args: (List String) -> Int64
  (match (listHead (filter (fn [(a String)] -> Bool (stringStartsWith? a "--max-attempts=")) args))
    ((none) 24)
    ((some a) (max 0 (optionOr (stringToInt64 (optionOr (stringSlice a 15 (stringLength a)) "")) 24))))

fn quoted s: String -> String
  (str "\"" (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\"")

fn ! preludePath! -> String
  (let [(p (optionOr (envGet "ASL_PRELUDE") ""))]
    (if (stringEmpty? p) "asl/prelude/prelude.asl" p))

fn ! healFile! path: String dryRun: Bool rounds: Int64 -> (Result String String)
  (match (fileReadString path)
    ((err e) (err (str "(:heal :file " (quoted path) " :status :failed :error ERR_IO :message " (quoted e) ")")))
    ((ok text)
      (match (heal/heal! path text (verify/checkRoots) (preludePath!) rounds)
        ((err e) (err (str "(:heal :file " (quoted path) " :status :failed :error ERR_HEAL :message " (quoted e) ")")))
        ((ok res)
          (let [(write (and res.changed (not dryRun)))
                (written (if write (match (fileWrite path res.text) ((ok _) (ok true)) ((err e) (err e))) (ok false)))]
            (match written
              ((err e) (err (str "(:heal :file " (quoted path) " :status :failed :error ERR_IO :message " (quoted e) ")")))
              ((ok w)
                (let [(body (stringReplace res.receipt "(:repaired" (str "(:heal :file " (quoted path) " :written " (if w "true" "false") " :repaired")))]
                  (if (or (listEmpty? res.left) (heal/lintOnly? res.left)) (ok body) (err body))))))))))

fn ! runHealCommand! args: (List String) -> (Result String String)
  (cond
    ((or (listContains? args "-h") (listContains? args "--help")) (ok (formatHealHelp)))
    (else
      (match (healTarget args)
        ((none) (err "(:heal :status :failed :error ERR_MISSING_ARG :message \"Usage: asl heal [--dry-run] [--max-attempts=<n>] <file.asl>\")"))
        ((some path) (healFile! path (listContains? args "--dry-run") (maxAttempts args))))))
