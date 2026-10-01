#lang racketscript

(provide score-story rank-stories)

(define authority
  (new Set
       (list "apnews.com" "reuters.com" "bbc.co.uk" "bbc.com" "theguardian.com"
             "nytimes.com" "wsj.com" "washingtonpost.com" "npr.org" "ft.com"
             "aljazeera.com" "cnn.com")))

(define impact-terms
  (list
   "dead" "killed" "deaths" "injured" "attack" "attacks" "war" "ceasefire" "bomb" "bombing"
   "earthquake" "hurricane" "storm" "flood" "flooding" "election" "elections" "vote" "court"
   "ruling" "supreme court" "law" "bill" "passed" "sanction" "sanctions" "market" "crash"
   "recession" "inflation" "rate hike" "strike" "unrest" "protest" "protests" "mass shooting"
   "tornado" "tsunami" "outbreak" "pandemic"))

(define (score-story story [cluster-size 1] [now (new Date)])
  (define score 0)
  (define pub (ref story "publishedAt"))
  (if pub
      (let* ([diff (- (now.getTime) (pub.getTime))]
             [hours (max 0 (/ diff (* 1000 60 60)))]
             [recency (Math.exp (/ (- hours) (* 24 3)))])
        (set! score (+ score (* recency 0.3)))))
  (let ([cov (min (/ cluster-size 10) 1)])
    (set! score (+ score (* cov 0.4))))
  (define t (string-downcase (or (ref story "title") "")))
  (define imp 0)
  (for ([term (in-list impact-terms)])
    (when (t.includes term)
      (set! imp (+ imp 1))))
  (set! score (+ score (* (min (/ imp 4) 1) 0.2)))
  (define auth 0)
  (try
   (let* ([url (ref story "url")]
          [host (.replace (.hostname (new URL url)) #rx"^www\\." "")])
     (when (.has authority host)
       (set! auth 1)))
   (catch (lambda (_) #t)))
  (set! score (+ score (* auth 0.1)))
  score)

(define (rank-stories stories clusters count)
  (define by-idx (new Map))
  (for ([c (in-array clusters)])
    (define members (ref c "members"))
    (define sz (ref c "size"))
    (for ([m (in-array members)])
      (.set by-idx (ref m "idx") sz)))
  (define scored (array))
  (for ([i (in-range (stories.length))])
    (define s (stories i))
    (define cs (.get by-idx i))
    (if (not cs) (set! cs 1))
    (scored.push (object
                  "title" (ref s "title")
                  "url" (ref s "url")
                  "sourceName" (ref s "sourceName")
                  "publishedAt" (ref s "publishedAt")
                  "description" (ref s "description")
                  "rawTitleNorm" (ref s "rawTitleNorm")
                  "score" (score-story s cs (new Date))))))
  (scored.sort (lambda (a b) (- (ref b "score") (ref a "score"))))
  (define seen (new Set))
  (define out (array))
  (for ([s (in-array scored)])
    (define key (or (ref s "url") (ref s "rawTitleNorm")))
    (when key
      (when (not (.has seen key))
        (.add seen key)
        (out.push s)
        (when (>= (out.length) count) (break)))))
  out)