(module aslSite/tools/posts
  :x [unquote loadPosts newestFirst]
  :i [(asl-parser/reader :a rd) (aslSite/app/blog :a blog)])

fn unquote atom: String -> String
  (let [(inner (optionOr (stringSlice atom 1 (- (stringLength atom) 1)) ""))
        (held (stringReplace inner "\\\\" "\u{1}"))]
    (if (and (stringStartsWith? atom "\"") (stringEndsWith? atom "\""))
      (stringReplace (stringReplace (stringReplace (stringReplace held "\\n" "\n") "\\t" "\t") "\\\"" "\"") "\u{1}" "\\")
      atom))

fn field items: (List rd/SExpr) key: String -> String
  (mt (listIndexOf (map (fn [(x rd/SExpr)] -> String (mt x ((rd/sexprAtom v) v) (_ ""))) items) key)
    ((none) "")
    ((some at) (mt (listGet items (+ at 1)) ((some x) (mt x ((rd/sexprAtom v) (unquote v)) (_ ""))) ((none) ""))))

fn postOf e: rd/SExpr -> (Option blog/Post)
  (mt e
    ((rd/sexprList items)
      (if (= (field items ":status") "published")
        (some (blog/Post :slug (field items ":slug") :title (field items ":title") :date (field items ":date") :author (field items ":author") :category (field items ":category") :readTime (field items ":readTime") :excerpt (field items ":excerpt") :content (field items ":content")))
        (none)))
    (_ (none)))

fn newestFirst posts: (List blog/Post) -> (List blog/Post)
  (listReverse (listSortBy (fn [(p blog/Post)] -> String p.date) posts))

fn loadPosts src: String -> (List blog/Post)
  (newestFirst (fold (fn [(acc (List blog/Post)) (e rd/SExpr)] -> (List blog/Post) (mt (postOf e) ((some p) (cons p acc)) ((none) acc))) [] (rd/sexprToList (rd/parseSexpr src))))
