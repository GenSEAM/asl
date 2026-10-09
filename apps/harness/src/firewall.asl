(module aslHarness/firewall :x [FirewallPolicy FirewallVerdict defaultFirewallPolicy evaluatePathBoundary evaluateCommandSafety auditAction] :i [])

(schema FirewallPolicy (:f allowedRoots (List Str)) (:f allowWrite Bool) (:f allowExec Bool) (:f maxFileBytes I64))

(schema FirewallVerdict (:f allowed Bool) (:f reason Str) (:f sanitizedTarget Str))

fn defaultFirewallPolicy -> FirewallPolicy
  (FirewallPolicy :allowedRoots (list ".") :allowWrite true :allowExec false :maxFileBytes 1048576)

fn pathInRoots? roots: (List Str) path: Str -> Bool
  (fold (fn [(matched Bool) (r Str)] -> Bool (or matched (if (= r ".") (and (not (stringStartsWith? path "/")) (not (stringStartsWith? path "~"))) (or (= path r) (stringStartsWith? path (str r "/")))))) false roots)

fn evaluatePathBoundary policy: FirewallPolicy path: Str -> FirewallVerdict
  (let [(clean (stringTrim path))] (cond ((stringEmpty? clean) (FirewallVerdict :allowed false :reason "Path validation failed: path cannot be empty" :sanitizedTarget "")) ((stringContains? clean "..") (FirewallVerdict :allowed false :reason "Path traversal detected: directory traversal sequences disallowed" :sanitizedTarget "")) ((or (stringStartsWith? clean "/etc") (stringContains? clean "/etc/")) (FirewallVerdict :allowed false :reason "Restricted path: access to system directory /etc disallowed" :sanitizedTarget "")) ((or (stringStartsWith? clean "~") (stringContains? clean ".ssh")) (FirewallVerdict :allowed false :reason "Restricted path: access to credentials and home directory disallowed" :sanitizedTarget "")) ((or (stringStartsWith? clean "/dev") (or (stringStartsWith? clean "/proc") (or (stringStartsWith? clean "/sys") (stringStartsWith? clean "/root")))) (FirewallVerdict :allowed false :reason "Restricted path: access to system root disallowed" :sanitizedTarget "")) ((not (pathInRoots? policy.allowedRoots clean)) (FirewallVerdict :allowed false :reason "Path out of boundary: path resides outside permitted workspace roots" :sanitizedTarget "")) (else (FirewallVerdict :allowed true :reason "Path verified within allowed sandbox boundary" :sanitizedTarget clean))))

fn detectDangerousPattern cmd: Str -> (Option Str)
  (let [(c (stringTrim cmd))] (cond ((or (stringContains? c "rm -rf") (or (stringContains? c "rm -fr") (or (stringContains? c "rm -r -f") (stringContains? c "rm -f -r")))) (some "rm -rf")) ((or (stringContains? c "curl | sh") (or (stringContains? c "curl|sh") (or (stringContains? c "curl | bash") (or (stringContains? c "curl|bash") (or (stringContains? c "| sh") (or (stringContains? c "|sh") (or (stringContains? c "| bash") (or (stringContains? c "|bash") (or (stringContains? c "wget | sh") (stringContains? c "wget|sh")))))))))) (some "curl | sh")) ((or (= c "eval") (or (stringStartsWith? c "eval ") (or (stringContains? c " eval") (or (stringContains? c "eval(") (stringContains? c ";eval"))))) (some "eval")) ((or (stringContains? c "dd if=") (stringContains? c "dd if =")) (some "dd if=")) ((stringContains? c "mkfs") (some "mkfs")) ((stringContains? c ":(){ :|:& };:") (some "fork bomb")) ((or (stringContains? c "> /dev/sd") (stringContains? c "> /dev/nvme")) (some "raw block device write")) (else (none))))

fn evaluateCommandSafety policy: FirewallPolicy cmd: Str -> FirewallVerdict
  (let [(trimmed (stringTrim cmd)) (danger (detectDangerousPattern trimmed))] (mt danger ((some pat) (FirewallVerdict :allowed false :reason (str "Dangerous command blocked: blacklisted token '" pat "' detected") :sanitizedTarget "")) ((none) (FirewallVerdict :allowed true :reason "Command verified safe for execution" :sanitizedTarget trimmed))))

fn isReadAction? action: Str -> Bool
  (or (= action "read") (or (= action "fs-read") (or (= action "read-file") (= action "fileRead"))))

fn isWriteAction? action: Str -> Bool
  (or (= action "write") (or (= action "fs-write") (or (= action "write-file") (or (= action "fileWrite") (or (= action "delete") (= action "remove"))))))

fn isExecAction? action: Str -> Bool
  (or (= action "exec") (or (= action "shell") (or (= action "bash") (or (= action "sh") (or (= action "cmd") (or (= action "run") (= action "execute")))))))

fn auditAction policy: FirewallPolicy actionKind: Str target: Str -> FirewallVerdict
  (cond ((isReadAction? actionKind) (evaluatePathBoundary policy target)) ((isWriteAction? actionKind) (if (not policy.allowWrite) (FirewallVerdict :allowed false :reason "Action blocked: file writing is disabled by firewall policy" :sanitizedTarget "") (evaluatePathBoundary policy target))) ((isExecAction? actionKind) (let [(safety (evaluateCommandSafety policy target))] (if (not safety.allowed) safety (if (not policy.allowExec) (FirewallVerdict :allowed false :reason "Action blocked: shell execution is disabled by firewall policy" :sanitizedTarget "") safety)))) (else (FirewallVerdict :allowed false :reason (str "Action blocked: unrecognized action kind '" actionKind "'") :sanitizedTarget "")))
