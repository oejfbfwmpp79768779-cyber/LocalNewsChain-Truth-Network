;; local-journalist-registry
;; Simple journalist registry with basic verification

(define-constant ERR-NOT-FOUND (err u101))

(define-map journalists
  { journalist-id: uint }
  { name: (string-ascii 100), verified: bool }
)

(define-data-var counter uint u0)

(define-public (register-journalist (name (string-ascii 100)))
  (let ((id (+ (var-get counter) u1)))
    (map-set journalists { journalist-id: id } { name: name, verified: false })
    (var-set counter id)
    (ok id)
  )
)

(define-read-only (get-journalist (id uint))
  (map-get? journalists { journalist-id: id })
)

(define-public (verify-journalist (id uint))
  (match (map-get? journalists { journalist-id: id })
    journalist (begin
      (map-set journalists { journalist-id: id } (merge journalist { verified: true }))
      (ok true)
    )
    ERR-NOT-FOUND
  )
)