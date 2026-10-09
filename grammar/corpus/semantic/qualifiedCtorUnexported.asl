"expect-only: rule-9"

"core/private declares Vault and does not export it. This reaches the checker"

"through the ctor head, a different path from the qualified-name scan; an"

"implementation that only did the latter reports rule-2 here."

(module text/crack :x [make] :i [(core/private :a p)])

fn make -> p/Vault
  (p/Vault :x 1)
