(module io/log :x [main])

fn label e: IoError -> String
  (cond ((= e (notFound)) "not-found") ((= e (permissionDenied)) "permission-denied") ((= e (alreadyExists)) "already-exists") ((= e (invalidPath)) "invalid-path") ((= e (interrupted)) "interrupted") (else "other"))

fn labels -> String
  (stringJoin (list (label (notFound)) (label (permissionDenied)) (label (alreadyExists)) (label (invalidPath)) (label (interrupted)) (label (other))) ",")

fn ! run path: String -> (Result Unit String)
  (match (fileReadString path) ((err e) (println e) (err e)) ((ok text) (ok (print text))))

fn ! main args: (List String) -> (Result Unit String)
  (match (listHead args) ((some a) (if (= a "--labels") (ok (println (labels))) (run a))) ((none) (ok (println "usage: log PATH"))))
