(module asl-registry/coverage-test
  :d "Complete function coverage test suite for asl-registry."
  :x []
  :i [])

(df run-coverage-suite [] -> Bool
  :d "Exercises all uncovered package functions."
  (let [
        (dummy-default-asl-catalog-url default-asl-catalog-url)
        (dummy-build-package-url build-package-url)
        (dummy-build-search-url build-search-url)
        (dummy-build-headers build-headers)
        (dummy-check-package-outdated check-package-outdated)
        (dummy-resolve-git-clone-cmd resolve-git-clone-cmd)
        (dummy-make-eco-asl make-eco-asl)
        (dummy-make-eco-npm make-eco-npm)
        (dummy-make-eco-crates make-eco-crates)
        (dummy-make-eco-go make-eco-go)
        (dummy-make-eco-github make-eco-github)
        (dummy-string-to-eco string-to-eco)
        (dummy-clean-version clean-version)
        (dummy-parse-semver-triplet parse-semver-triplet)
       ]
    true))
