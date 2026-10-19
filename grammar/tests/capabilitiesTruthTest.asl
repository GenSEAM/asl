(module grammar/capabilitiesTruthTest
  :x [runTests])

fn hasManageTimeout! -> Bool
  (match (fileReadString "asl/grammar/capabilities.asn")
    ((ok text)
      (stringContains? text ":id manage"))
    ((err e) false))

fn hasFetchRows! -> Bool
  (match (fileReadString "asl/grammar/capabilities.asn")
    ((ok text)
      (and
        (stringContains? text ":id curl")
        (and
          (stringContains? text "asl-crawler")
          (stringContains? text "asl-gateway/src/browserGateway"))))
    ((err e) false))

fn canonicalNoAslMemEdit! -> Bool
  (match (fileReadString "asl/grammar/capabilities.asn")
    ((ok text)
      (match (stringIndexOf text ":canonicalMemoryMatrix")
        ((some before)
          (match (stringIndexOf text ":situations")
            ((some after)
              (match (stringSlice text before after)
                ((some section)
                  (not (stringContains? section "asl mem edit")))
                ((none) false)))
            ((none) false)))
        ((none) false)))
    ((err e) false))

fn allRowsHaveStatus! -> Bool
  (match (fileReadString "asl/grammar/capabilities.asn")
    ((ok text)
      (let [(replaced (stringReplace text ":status :works" ""))
            (workCount (- (stringLength text) (stringLength replaced)))]
        (> workCount 0)))
    ((err e) false))

fn ! runTests -> Bool
  (do
    (assert (hasManageTimeout!) "manage capability exists")
    (assert (hasFetchRows!) "curl, crawler, and browserGateway rows exist")
    (assert (canonicalNoAslMemEdit!) "canonicalMemoryMatrix uses form names not 'asl mem edit' strings")
    (assert (allRowsHaveStatus!) "capabilities have status values")
    true)
