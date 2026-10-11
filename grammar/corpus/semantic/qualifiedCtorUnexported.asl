(module text/crack :x [make] :i [(core/private :a p)])

fn make -> p/Vault
  (p/Vault :x 1)
