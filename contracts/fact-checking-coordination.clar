;; fact-checking-coordination
;; Simple fact-checking coordination system

(define-constant ERR-NOT-FOUND (err u201))

(define-map stories
  { story-id: uint }
  { title: (string-ascii 200), verified: bool, votes: uint }
)

(define-data-var story-counter uint u0)

(define-public (submit-story (title (string-ascii 200)))
  (let ((id (+ (var-get story-counter) u1)))
    (map-set stories { story-id: id } { title: title, verified: false, votes: u0 })
    (var-set story-counter id)
    (ok id)
  )
)

(define-read-only (get-story (id uint))
  (map-get? stories { story-id: id })
)

(define-public (vote-on-story (id uint))
  (match (map-get? stories { story-id: id })
    story (let ((new-votes (+ (get votes story) u1)))
      (map-set stories { story-id: id } (merge story { votes: new-votes }))
      (ok new-votes)
    )
    ERR-NOT-FOUND
  )
)

(define-public (verify-story (id uint))
  (match (map-get? stories { story-id: id })
    story (begin
      (map-set stories { story-id: id } (merge story { verified: true }))
      (ok true)
    )
    ERR-NOT-FOUND
  )
)