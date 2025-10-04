;; truth-journalism-rewards
;; Simple token rewards for accurate journalism

(define-constant ERR-NOT-FOUND (err u401))
(define-constant ERR-ALREADY-CLAIMED (err u403))

(define-fungible-token truth-token)

(define-map rewards
  { user: principal, period: uint }
  { earned: uint, claimed: bool }
)

(define-data-var current-period uint u1)

(define-public (earn-reward (amount uint))
  (let ((period (var-get current-period)))
    (match (map-get? rewards { user: tx-sender, period: period })
      existing-reward (begin
        (map-set rewards 
          { user: tx-sender, period: period } 
          { earned: (+ (get earned existing-reward) amount), claimed: (get claimed existing-reward) })
        (ok (+ (get earned existing-reward) amount))
      )
      (begin
        (map-set rewards { user: tx-sender, period: period } { earned: amount, claimed: false })
        (ok amount)
      )
    )
  )
)

(define-public (claim-rewards)
  (let ((period (var-get current-period)))
    (match (map-get? rewards { user: tx-sender, period: period })
      reward (begin
        (asserts! (not (get claimed reward)) ERR-ALREADY-CLAIMED)
        (try! (ft-mint? truth-token (get earned reward) tx-sender))
        (map-set rewards 
          { user: tx-sender, period: period } 
          (merge reward { claimed: true }))
        (ok (get earned reward))
      )
      ERR-NOT-FOUND
    )
  )
)

(define-read-only (get-balance (user principal))
  (ft-get-balance truth-token user)
)

(define-read-only (get-reward-info (user principal) (period uint))
  (map-get? rewards { user: user, period: period })
)

(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
  (begin
    (asserts! (is-eq tx-sender sender) ERR-NOT-FOUND)
    (ft-transfer? truth-token amount sender recipient)
  )
)

(define-read-only (get-current-period)
  (var-get current-period)
)

(define-public (advance-period)
  (begin
    (var-set current-period (+ (var-get current-period) u1))
    (ok (var-get current-period))
  )
)