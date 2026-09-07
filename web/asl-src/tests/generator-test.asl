(module asl-web/generator-test
  :d "Unit verification test suite for Web API and installer ASL models"
  :x [test-packages-catalog test-plugins-catalog test-skills-catalog test-version-info test-installer-config test-installer-script-generation run-tests]
  :i [(api/packages :a pkg)
      (api/plugins :a plg)
      (api/skills :a skl)
      (api/version :a ver)
      (scripts/installer :a inst)])

(df test-packages-catalog [] -> Bool
  :d "Validates packages catalog structure and count"
  (let [(pkgs (pkg/package-catalog))]
    (and (>= (list-length pkgs) 10)
         true)))

(df test-plugins-catalog [] -> Bool
  :d "Validates plugins catalog structure and count"
  (let [(plugins (plg/plugin-catalog))]
    (and (>= (list-length plugins) 5)
         true)))

(df test-skills-catalog [] -> Bool
  :d "Validates skills catalog structure and count"
  (let [(skills (skl/skill-catalog))]
    (and (>= (list-length skills) 5)
         true)))

(df test-version-info [] -> Bool
  :d "Validates version information and download endpoints"
  (let [(v (ver/version-info))]
    (and (not (string-empty? (.-version v)))
         (= (.-channel v) "stable"))))

(df test-installer-config [] -> Bool
  :d "Validates installer parameters and target binaries"
  (let [(cfg (inst/installer-config))]
    (and (= (.-cli_name cfg) "asl")
         (string-contains? (.-repo_url cfg) "github.com"))))

(df test-installer-script-generation [] -> Bool
  :d "Validates pure ASL generation of POSIX Bash installer with automatic PATH setup"
  (let [(script (inst/generate-install-script))]
    (and (string-contains? script "#!/bin/bash")
         (and (string-contains? script "export PATH=")
              (and (string-contains? script ".local/bin/asl")
                   (and (string-contains? script ".zshrc")
                        (string-contains? script ".bashrc")))))))

(df run-tests [] -> Bool
  :d "Runs all generator model unit tests"
  (and (test-packages-catalog)
       (and (test-plugins-catalog)
            (and (test-skills-catalog)
                 (and (test-version-info)
                      (and (test-installer-config)
                           (test-installer-script-generation)))))))
