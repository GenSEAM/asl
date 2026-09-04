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
  :d "Report on the working tree using the typed process toolkit."
  :x [main]
  :i [(core/process :a proc)
      (core/log :a log)])

(df ! main [(args (List Str))] -> (Result Unit IoError)
  :d "Run `git status --short` and log the outcome."
  (mt (proc/exec! (proc/cmd "git" (list "status" "--short")))
    ((ok out)
     (if (= (.-exit-code out) 0)
       (log/info! "deploy" (str "git status clean: " (.-stdout out)))
       (log/err! "deploy" (str "git failed: " (.-stderr out)))))
    ((err e) (log/err! "deploy" "command execution failed")))
  (ok ()))
```
