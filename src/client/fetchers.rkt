#lang racketscript

(require "./utils.rkt")

(provide fetch-with-proxy parse-rss fetch-all-rss)

(define proxies
  (list
   (lambda (u) (string-append "https://api.allorigins.win/raw?url=" (encodeURIComponent u)))
   (lambda (u) (string-append "https://corsproxy.io/?url=" (encodeURIComponent u)))))

(define rss-sources
  (list
   "https://news.google.com/rss"
   "https://apnews.com/rss"
   "https://www.reuters.com/rss"
   "https://feeds.bbci.co.uk/news/rss.xml"
   "https://www.theguardian.com/rss"))

(define (fetch-with-proxy url)
  (define (try-proxy ps last-err)
    (if (null? ps)
        (throw last-err)
        (let ([mk (car ps)])
          (define res (await ($/fetch (mk url) (object "cache" "no-store"))))
          (if (not (.ok res))
              (try-proxy (cdr ps) (new Error (string-append "HTTP " (number->string (.status res)))))
              (await (.text res))))))
  (try-proxy proxies (new Error "All proxies failed")))

(define (guess-source-from-url u)
  (try
   (let ([host (.hostname (new URL u))])
     (host.replace #rx"^www\\." ""))
   (catch (lambda (_) ""))))

(define (parse-rss xml)
  (let ([parser (new DOMParser)]
        [doc (.parseFromString parser xml "application/xml")])
    (define items (Array.from (.querySelectorAll doc "item")))
    (items.map
     (lambda (it)
       (define title (let ([n (.querySelector it "title")]) (if n (or (.textContent n) "") "")))
       (define link (let ([n (.querySelector it "link")]) (if n (or (.textContent n) "") "")))
       (define pub1 (let ([n (.querySelector it "pubDate")]) (if n (or (.textContent n) "") "")))
       (define pub2 (let ([n (.querySelector it "pubdate")]) (if n (or (.textContent n) "") "")))
       (define pub (if (> (string-length pub1) 0) pub1 pub2))
       (define srcn (let ([n (.querySelector it "source")]) (if n (or (.textContent n) (.getAttribute n "url")) "")))
       (define desc (let ([n (.querySelector it "description")]) (if n (or (.textContent n) "") "")))
       (object
        "title" (.trim (title.replace #rx"<[^>]+>" ""))
        "url" (.trim link)
        "sourceName" (if (> (string-length (.trim srcn)) 0) (.trim srcn) (guess-source-from-url link))
        "publishedAt" (parse-rss-date pub)
        "description" (.trim (desc.replace #rx"<[^>]+>" ""))
        "rawTitleNorm" (normalize-title title))))))

(define (fetch-all-rss)
  (define results (array))
  (for-each
   (lambda (url)
     (try
      (let ([xml (await (fetch-with-proxy url))])
        (results.push.apply results (parse-rss xml)))
      (catch (lambda (_) #t))))
   rss-sources)
  results)