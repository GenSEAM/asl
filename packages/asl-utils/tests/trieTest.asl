(module asl-utils/tests/trieTest
  :x [runTests]
  :i [(asl-utils/trie :a tr)])

fn oraclePrefixSearch xs: (List String) prefix: String -> (List String)
  (listSort (filter (fn [(s String)] -> Bool (stringStartsWith? s prefix)) xs))

fn testEmpty -> Bool
  (let [(t (tr/empty))]
    (do (assert (not (tr/member t "anything")) "empty: nothing is member")
        (assert (= (listLength (tr/prefixSearch t "a")) 0) "empty: no prefixes")
        (assert (= (tr/longestPrefix t "anything") (none)) "empty: no longest prefix")
        true))

fn testInsertAndMember -> Bool
  (let [(t1 (tr/empty))
        (t2 (tr/insert t1 "hello" "world"))
        (t3 (tr/insert t2 "hell" "there"))]
    (do (assert (tr/member t2 "hello") "hello is member after insert")
        (assert (not (tr/member t1 "hello")) "hello not member in empty trie")
        (assert (tr/member t3 "hell") "hell is member")
        (assert (tr/member t3 "hello") "hello still member")
        (assert (not (tr/member t3 "help")) "help is not member")
        true))

fn testPrefixSearch -> Bool
  (let [(t (tr/empty))
        (t (tr/insert t "hello" "1"))
        (t (tr/insert t "hell" "2"))
        (t (tr/insert t "heaven" "3"))
        (t (tr/insert t "help" "4"))
        (t (tr/insert t "world" "5"))
        (oracle (oraclePrefixSearch (list "hello" "hell" "heaven" "help" "world") "he"))
        (got (tr/prefixSearch t "he"))]
    (do (assert (= (listLength got) 4) "prefix search he returns 4")
        (assert (= (listLength (tr/prefixSearch t "hel")) 3) "prefix search hel returns 3")
        (assert (= (listLength (tr/prefixSearch t "world")) 1) "prefix search world returns 1")
        (assert (= (listLength (tr/prefixSearch t "xyz")) 0) "prefix search xyz returns 0")
        (assert (= (listSort got) oracle) "prefix search matches oracle")
        true))

fn testLongestPrefix -> Bool
  (let [(t (tr/empty))
        (t (tr/insert t "a" "1"))
        (t (tr/insert t "ab" "2"))
        (t (tr/insert t "abc" "3"))
        (t (tr/insert t "abcd" "4"))]
    (do (assert (= (tr/longestPrefix t "abcdef") (some "abcd")) "longest prefix of abcdef")
        (assert (= (tr/longestPrefix t "ab") (some "ab")) "longest prefix of ab")
        (assert (= (tr/longestPrefix t "a") (some "a")) "longest prefix of a")
        (assert (= (tr/longestPrefix t "xyz") (none)) "longest prefix of xyz")
        true))

fn testPersistence -> Bool
  (let [(t1 (tr/empty))
        (t2 (tr/insert t1 "hello" "1"))
        (t3 (tr/insert t2 "hell" "2"))]
    (do (assert (not (tr/member t1 "hello")) "t1 unchanged: no hello")
        (assert (not (tr/member t1 "hell")) "t1 unchanged: no hell")
        (assert (tr/member t2 "hello") "t2 has hello")
        (assert (not (tr/member t2 "hell")) "t2 no hell")
        (assert (tr/member t3 "hello") "t3 has hello")
        (assert (tr/member t3 "hell") "t3 has hell")
        true))

fn runTests -> Bool
  (and (testEmpty) (testInsertAndMember) (testPrefixSearch) (testLongestPrefix) (testPersistence))
