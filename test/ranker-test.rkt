#lang racket/base
(require rackunit)
(require racket/date)
(require "../src/ranker.rkt")

(test-case "score-story basic"
  (define s (hash "title" "Major earthquake kills dozens" "url" "https://example.com/1" "sourceName" "AP" "publishedAt" (current-date)))
  (define sc (score-story s 5 (current-date)))
  (check > sc 0))

(test-case "rank-stories returns top"
  (define now (current-date))
  (define stories
    (vector (hash "title" "Small thing" "url" "u1" "sourceName" "x" "publishedAt" now "rawTitleNorm" "small thing")
            (hash "title" "Big earthquake kills many" "url" "u2" "sourceName" "AP" "publishedAt" now "rawTitleNorm" "big earthquake kills many")))
  (define clusters
    (vector (hash "members" (vector (vector-ref stories 1)) "size" 1)
            (hash "members" (vector (vector-ref stories 0)) "size" 1)))
  (define top (rank-stories stories clusters 1))
  (check = (vector-length top) 1)
  (check-equal? (hash-ref (vector-ref top 0) "url") "u2"))
