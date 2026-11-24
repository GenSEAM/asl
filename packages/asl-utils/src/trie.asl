(module asl-utils/trie
  :x [empty insert member prefixSearch longestPrefix]
  :i [])

(schema TrieNode (:f children (List (Pair String TrieNode))) (:f value (Option String)))

fn empty -> TrieNode
  (TrieNode :children (list) :value (none))

fn findChild t: TrieNode c: String -> (Option TrieNode)
  (match (listHead (filter (fn [(p (Pair String TrieNode))] -> Bool (= (pairFirst p) c)) t.children))
    ((none) (none))
    ((some p) (some (pairSecond p))))

fn insert t: TrieNode k: String v: String -> TrieNode
  (insertChars t (stringChars k) v)

fn insertChars t: TrieNode chars: (List String) v: String -> TrieNode
  (match (listHead chars)
    ((none) (with t :value (some v)))
    ((some c)
      (let [(existing (findChild t c))
            (child (optionOr existing (empty)))
            (newChild (insertChars child (listDrop chars 1) v))
            (children (match existing
                        ((none) (cons (pair c newChild) t.children))
                        ((some _) (map (fn [(p (Pair String TrieNode))] -> (Pair String TrieNode)
                                         (if (= (pairFirst p) c) (pair c newChild) p))
                                       t.children))))]
        (with t :children children))))

fn member t: TrieNode k: String -> Bool
  (memberChars t (stringChars k))

fn memberChars t: TrieNode chars: (List String) -> Bool
  (match (listHead chars)
    ((none) (some? t.value))
    ((some c)
      (match (findChild t c)
        ((none) false)
        ((some child) (memberChars child (listDrop chars 1))))))

fn prefixSearch t: TrieNode prefix: String -> (List String)
  (match (navigate t (stringChars prefix))
    ((none) (list))
    ((some node) (collectKeys node prefix (list))))

fn navigate t: TrieNode chars: (List String) -> (Option TrieNode)
  (match (listHead chars)
    ((none) (some t))
    ((some c)
      (match (findChild t c)
        ((none) (none))
        ((some child) (navigate child (listDrop chars 1))))))

fn collectKeys t: TrieNode prefix: String acc: (List String) -> (List String)
  (let [(acc2 (if (some? t.value) (cons prefix acc) acc))]
    (fold (fn [(a (List String)) (p (Pair String TrieNode))] -> (List String)
            (let [(c (pairFirst p))
                  (child (pairSecond p))]
              (collectKeys child (str prefix c) a)))
          acc2 t.children))

fn longestPrefix t: TrieNode k: String -> (Option String)
  (longestPrefixChars t (stringChars k) "" (none))

fn longestPrefixChars t: TrieNode chars: (List String) soFar: String best: (Option String) -> (Option String)
  (let [(best2 (if (some? t.value) (some soFar) best))]
    (match (listHead chars)
      ((none) best2)
      ((some c)
        (match (findChild t c)
          ((none) best2)
          ((some child) (longestPrefixChars child (listDrop chars 1) (str soFar c) best2))))))
