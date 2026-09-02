# @genseam/asl-sh

**Native AgentScript System & Process Automation Toolkit** (@pcp:d-446d).

## Why AgentScript for System Scripting?

1. **Zero Shell Injection Vulnerabilities**: Commands are represented as typed vectors (`(ProcessCmd :bin "git" :args ["status" "-s"])`). Arguments are passed directly to `execve`/`posix_spawn`, completely eliminating string concatenation injection bugs common in Bash and Python `os.system`.
2. **Deterministic Pipelines**: Multi-stage process pipelines stream `stdout` directly into `stdin` without intermediate `/bin/sh -c` subshells.
3. **Structured Outputs**: Returns typed `(Result ProcessOutput ProcessError)` containing `exit-code`, `stdout`, `stderr`, and `duration-ms`.
4. **Jailed Execution**: Integrates with AgentScript's directory jailing to prevent unauthorized host filesystem traversal.

## Quick Start

```lisp
(module admin/deploy
  (:import [asl-sh :as sh]))

(defun ! main [(args (List String))] -> (Result Unit String)
  ;; Execute safe vector command
  (match (sh/exec! (sh/cmd "git" ["status" "--short"]))
    ((ok out)
     (if (= (.-exit-code out) 0)
         (sh/info! "deploy" (concat "Git status clean: " (.-stdout out)))
         (sh/err!  "deploy" (concat "Git error: " (.-stderr out))))
     (ok (unit)))
    ((err e) (err "Command execution failed"))))
```
