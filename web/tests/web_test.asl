(module asl-web/web-test
  :d "Unit test suite for AgentScript Web Package"
  :x [test-web-app test-web-catalog run-tests]
  :i [(api/packages :a pkg)
      (api/version :a ver)
      (app :a app)])

(df test-web-app [] -> Bool
  :d "Verifies app rendering and route definitions"
  (and (not (string-empty? (app/render-app)))
       (> (list-length (app/app-routes)) 0)))

(df test-web-catalog [] -> Bool
  :d "Verifies package catalog and version info"
  (let [(pkgs (pkg/package-catalog))
        (v (ver/version-info))]
    (and (>= (list-length pkgs) 10)
         (= (.-channel v) "stable"))))

(df run-tests [] -> Bool
  :d "Executes web tests"
  (and (test-web-app)
       (test-web-catalog)))
