"A file reader, and the whole IoError surface it can reach. The six cases are"

"ordinary nullary constructors, so `--labels` executes every one of them and"

"pins its spelling; the host mapping from errno to case is what only a real"

"failing call reaches. The host has no file-append, fileExists?, read-line or"

"read-all, so the log appender this fixture once was is now a reader."

(module io/log :x [main])

fn label e: IoError -> String
  (cond ((= e (notFound)) "not-found") ((= e (permissionDenied)) "permission-denied") ((= e (alreadyExists)) "already-exists") ((= e (invalidPath)) "invalid-path") ((= e (interrupted)) "interrupted") (else "other"))

fn labels -> String
  (stringJoin (list (label (notFound)) (label (permissionDenied)) (label (alreadyExists)) (label (invalidPath)) (label (interrupted)) (label (other))) ",")

fn ! run path: String -> (Result Unit IoError)
  (match (fileRead path) ((err e) (println (label e)) (err e)) ((ok text) (ok (print text))))

fn ! main args: (List String) -> (Result Unit IoError)
  (match (listHead args) ((some a) (if (= a "--labels") (ok (println (labels))) (run a))) ((none) (ok (println "usage: log PATH"))))
