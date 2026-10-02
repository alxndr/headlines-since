#lang racket/base
(require racket/set)
(require racket/vector)
(require net/url)
(require racket/date)
(require racket/string)

(provide score-story rank-stories)

(define authority
  (set "apnews.com" "reuters.com" "bbc.co.uk" "bbc.com" "theguardian.com"
       "nytimes.com" "wsj.com" "washingtonpost.com" "npr.org" "ft.com"
       "aljazeera.com" "cnn.com"))

(define impact-terms
  (list
   "dead" "killed" "deaths" "injured" "attack" "attacks" "war" "ceasefire" "bomb" "bombing"
   "earthquake" "hurricane" "storm" "flood" "flooding" "election" "elections" "vote" "court"
   "ruling" "supreme court" "law" "bill" "passed" "sanction" "sanctions" "market" "crash"
   "recession" "inflation" "rate hike" "strike" "unrest" "protest" "protests" "mass shooting"
   "tornado" "tsunami" "outbreak" "pandemic"))

(define (score-story story [cluster-size 1] [now (current-date)])
  (define score 0)
  (define pub (hash-ref story "publishedAt" #f))
  (when pub
    (define diff (- (date->seconds now) (date->seconds pub)))
    (define hours (max 0 (/ diff 3600)))
    (define recency (exp (/ (- hours) (* 24 3))))
    (set! score (+ score (* recency 0.3))))
  (define cov (min (/ cluster-size 10) 1))
  (set! score (+ score (* cov 0.4)))
  (define t (string-downcase (hash-ref story "title" "")))
  (define imp 0)
  (for ([term (in-list impact-terms)])
    (when (string-contains? t term)
      (set! imp (+ imp 1))))
  (set! score (+ score (* (min (/ imp 4) 1) 0.2)))
  (define auth 0)
  (define url (hash-ref story "url" ""))
  (with-handlers ([exn:fail? (lambda (_) #t)])
    (define host (regexp-replace #rx"^www\\." (url-host (string->url url)) ""))
    (when (set-member? authority host)
      (set! auth 1)))
  (set! score (+ score (* auth 0.1)))
  score)

(define (rank-stories stories clusters count)
  (define vec (if (vector? stories) stories (list->vector stories)))
  (define by-idx (make-hash))
  (for ([c (in-vector (if (vector? clusters) clusters (list->vector clusters)))])
    (define members (hash-ref c "members"))
    (define sz (hash-ref c "size"))
    (for ([m (in-vector (if (vector? members) members (list->vector members)))])
      (define idx (hash-ref m "idx" #f))
      (when idx (hash-set! by-idx idx sz))))
  (define scored (for/vector ([i (in-range (vector-length vec))])
    (define s (vector-ref vec i))
    (define cs (hash-ref by-idx i #f))
    (define copy (hash-copy s))
    (hash-set! copy "score" (score-story s (if cs cs 1) (current-date)))
    copy))
  (define sorted (vector-sort scored (lambda (a b) (> (hash-ref a "score") (hash-ref b "score")))))
  (define seen (mutable-set))
  (define out-list '())
  (let loop ([i 0])
    (when (< i (vector-length sorted))
      (when (< (length out-list) count)
        (define s (vector-ref sorted i))
        (define key (or (hash-ref s "url" #f) (hash-ref s "rawTitleNorm" #f)))
        (when key
          (unless (set-member? seen key)
            (set-add! seen key)
            (set! out-list (cons (hash-copy s) out-list))))
        (loop (add1 i)))))
  (list->vector (reverse out-list)))
