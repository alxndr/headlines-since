#lang racketscript

(require "./fetchers.rkt")
(require "./cluster.rkt")
(require "./ranker.rkt")
(require "./utils.rkt")

(provide init)

(define (init)
  (define form ($ "#hs-form"))
  (define date-input ($ "#start-date"))
  (define count-input ($ "#count"))
  (define status ($ "#hs-status"))
  (define results ($ "#hs-results"))

  (when date-input
    (define d (days-ago 14))
    (date-input.value (format-date-iso d)))

  (when form
    (form.addEventListener
     "submit"
     (lambda (e)
       (.preventDefault e)
       (main date-input count-input status results)))))

(define ($ sel)
  (document.querySelector sel))

(define (clear el)
  (set! el.innerHTML ""))

(define (set-status el msg)
  (set! el.textContent msg))

(define (error-msg el msg)
  (clear el)
  (define div (document.createElement "div"))
  (set! div.className "error")
  (set! div.textContent msg)
  (el.appendChild div))

(define (show-results el stories)
  (clear el)
  (for ([s (in-array stories)])
    (define card (document.createElement "article"))
    (set! card.className "story")
    (define h3 (document.createElement "h3"))
    (define a (document.createElement "a"))
    (set! a.href (or (ref s "url") "#"))
    (set! a.target "_blank")
    (set! a.rel "noopener noreferrer")
    (set! a.textContent (or (ref s "title") ""))
    (h3.appendChild a)
    (card.appendChild h3)
    (define meta (document.createElement "div"))
    (set! meta.className "story-meta")
    (define src (or (ref s "sourceName") ""))
    (define pub (ref s "publishedAt"))
    (define when-str (if pub (.toLocaleString pub) ""))
    (set! meta.textContent (string-append src (if (and (> (string-length src) 0) (> (string-length when-str) 0)) " • " "") when-str))
    (card.appendChild meta)
    (el.appendChild card)))

(define (main date-input count-input status results)
  (clear results)
  (set-status status "Fetching headlines...")
  (define start-str (if date-input (date-input.value) ""))
  (define count (if count-input (parseInt (count-input.value) 10) 10))
  (if (not start-str)
      (error-msg results "Please pick a start date.")
      (try
       (define start (new Date start-str))
       (define all (await (fetch-all-rss)))
       (define filtered (array))
       (for ([s (in-array all)])
         (define p (ref s "publishedAt"))
         (when (and p (>= p.getTime start.getTime))
           (filtered.push s)))
       (define clusters (cluster-stories filtered))
       (define top (rank-stories filtered clusters count))
       (if (= (top.length) 0)
           (set-status status "No stories found for this range.")
           (begin
             (set-status status (string-append "Found " (number->string (top.length)) " biggest stories"))
             (show-results results top))))
       (catch (lambda (e)
                (error-msg results (string-append "Error: " (or (ref e "message") "unknown"))))))))