;; misinformation-prevention-system
;; Simple misinformation prevention and flagging system

(define-constant ERR-NOT-FOUND (err u301))
(define-constant ERR-ALREADY-FLAGGED (err u302))

(define-map flagged-content
  { content-id: uint }
  { title: (string-ascii 200), flags: uint, status: uint }
)

(define-map user-flags
  { user: principal, content-id: uint }
  { flagged: bool }
)

(define-data-var content-counter uint u0)

(define-public (flag-content (title (string-ascii 200)))
  (let ((id (+ (var-get content-counter) u1)))
    (asserts! (is-none (map-get? user-flags { user: tx-sender, content-id: id })) ERR-ALREADY-FLAGGED)
    (map-set flagged-content { content-id: id } { title: title, flags: u1, status: u1 })
    (map-set user-flags { user: tx-sender, content-id: id } { flagged: true })
    (var-set content-counter id)
    (ok id)
  )
)

(define-read-only (get-flagged-content (id uint))
  (map-get? flagged-content { content-id: id })
)

(define-public (add-flag (id uint))
  (match (map-get? flagged-content { content-id: id })
    content (let ((new-flags (+ (get flags content) u1)))
      (asserts! (is-none (map-get? user-flags { user: tx-sender, content-id: id })) ERR-ALREADY-FLAGGED)
      (map-set flagged-content { content-id: id } (merge content { flags: new-flags }))
      (map-set user-flags { user: tx-sender, content-id: id } { flagged: true })
      (ok new-flags)
    )
    ERR-NOT-FOUND
  )
)

(define-public (resolve-content (id uint) (is-misinformation bool))
  (match (map-get? flagged-content { content-id: id })
    content (let ((new-status (if is-misinformation u3 u2)))
      (map-set flagged-content { content-id: id } (merge content { status: new-status }))
      (ok new-status)
    )
    ERR-NOT-FOUND
  )
)