#!/usr/bin/env asl
fn shout s: String -> String
  (str (stringUpper s) "!")

(println (shout (argStr args 0 "world")))
(let [(text String (fileReadString (argStr args 1 "/nonexistent")))])
(println (str "read " (stringLength text)))
(println "after")
