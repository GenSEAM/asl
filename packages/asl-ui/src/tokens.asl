(module asl-ui/tokens :x [gridStep isValidGridStep? TypographyToken makeTypographyToken getTypographyToken isMonospaceRole?])

(schema TypographyToken (:f role String) (:f fontSize Int64) (:f lineHeight Int64) (:f fontWeight Int64) (:f isMono Bool))

fn makeTypographyToken role: String fontSize: Int64 lineHeight: Int64 fontWeight: Int64 isMono: Bool -> TypographyToken
  (TypographyToken :role role :fontSize fontSize :lineHeight lineHeight :fontWeight fontWeight :isMono isMono)

fn gridStep step: Int64 -> Int64
  (if (<= step 0) 0 (* step 4))

fn isValidGridStep? pixels: Int64 -> Bool
  (if (<= pixels 0) false (= (mod pixels 4) 0))

fn isMonospaceRole? role: String -> Bool
  (or (= role "code") (or (= role "symbol") (= role "asn")))

fn getTypographyToken role: String -> TypographyToken
  (cond ((= role "micro") (TypographyToken :role "micro" :fontSize 10 :lineHeight 14 :fontWeight 400 :isMono false)) ((= role "caption") (TypographyToken :role "caption" :fontSize 12 :lineHeight 16 :fontWeight 400 :isMono false)) ((= role "body") (TypographyToken :role "body" :fontSize 14 :lineHeight 20 :fontWeight 400 :isMono false)) ((= role "subhead") (TypographyToken :role "subhead" :fontSize 16 :lineHeight 24 :fontWeight 500 :isMono false)) ((= role "title") (TypographyToken :role "title" :fontSize 20 :lineHeight 28 :fontWeight 600 :isMono false)) ((= role "display") (TypographyToken :role "display" :fontSize 28 :lineHeight 36 :fontWeight 700 :isMono false)) ((or (= role "code") (or (= role "symbol") (= role "asn"))) (TypographyToken :role role :fontSize 13 :lineHeight 18 :fontWeight 400 :isMono true)) (else (TypographyToken :role "body" :fontSize 14 :lineHeight 20 :fontWeight 400 :isMono false)))
