;; truth-journalism-rewards
;; Token rewards for accurate local journalism and community members supporting fact-checking

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-NOT-FOUND (err u401))
(define-constant ERR-INSUFFICIENT-BALANCE (err u402))
(define-constant ERR-ALREADY-CLAIMED (err u403))
(define-constant ERR-INVALID-AMOUNT (err u404))
(define-constant ERR-REWARD-PERIOD-ACTIVE (err u405))
(define-constant ERR-MINIMUM-NOT-MET (err u406))
(define-constant ERR-INVALID-MULTIPLIER (err u407))

;; Reward amounts and thresholds
(define-constant ACCURACY-REWARD u100)
(define-constant FACT-CHECK-REWARD u50)
(define-constant COMMUNITY-REWARD u25)
(define-constant BONUS-MULTIPLIER u150) ;; 1.5x for exceptional work
(define-constant MIN-ACCURACY-SCORE u80)
(define-constant MIN-COMMUNITY-PARTICIPATION u5)

;; Reward periods (in blocks)
(define-constant REWARD-PERIOD-LENGTH u1008) ;; ~1 week
(define-constant CLAIM-WINDOW u144) ;; ~1 day to claim

;; Fungible Token Definition
(define-fungible-token truth-token)

;; Data Variables
(define-data-var total-supply uint u1000000) ;; 1M initial supply
(define-data-var current-reward-period uint u0)
(define-data-var reward-pool-balance uint u100000) ;; 100K reward pool
(define-data-var total-rewards-distributed uint u0)
(define-data-var active-participants uint u0)

;; Track individual reward accounts
(define-map reward-accounts
  { participant: principal }
  {
    total-earned: uint,
    accuracy-rewards: uint,
    fact-check-rewards: uint,
    community-rewards: uint,
    bonus-rewards: uint,
    last-claim-period: uint,
    participation-streak: uint,
    reputation-multiplier: uint
  }
)

;; Track reward claims per period
(define-map period-claims
  { participant: principal, period: uint }
  {
    accuracy-earned: uint,
    fact-check-earned: uint,
    community-earned: uint,
    bonus-earned: uint,
    claimed: bool,
    claimed-at: (optional uint)
  }
)

;; Track journalist performance for rewards
(define-map journalist-performance
  { journalist: principal, period: uint }
  {
    articles-published: uint,
    accuracy-score: uint,
    fact-checks-passed: uint,
    community-engagement: uint,
    ethics-violations: uint,
    performance-rating: uint
  }
)

;; Track community member contributions
(define-map community-contributions
  { contributor: principal, period: uint }
  {
    fact-checks-performed: uint,
    evidence-submitted: uint,
    flags-validated: uint,
    corrections-approved: uint,
    contribution-score: uint
  }
)

;; Track reward pool allocations per period
(define-map period-allocations
  { period: uint }
  {
    total-allocated: uint,
    accuracy-pool: uint,
    fact-check-pool: uint,
    community-pool: uint,
    bonus-pool: uint,
    participants: uint,
    period-start: uint,
    period-end: uint
  }
)

;; Store special achievements that earn bonus rewards
(define-map special-achievements
  { achievement-id: uint }
  {
    name: (string-ascii 100),
    description: (string-ascii 300),
    reward-amount: uint,
    criteria: (string-ascii 200),
    active: bool,
    created-by: principal,
    created-at: uint
  }
)

;; Track achievement earnings
(define-map achievement-earnings
  { participant: principal, achievement-id: uint }
  {
    earned-at: uint,
    reward-claimed: bool,
    period: uint
  }
)

;; Private Functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

(define-private (calculate-accuracy-reward (accuracy-score uint) (articles-count uint))
  (let (
    (base-reward (* ACCURACY-REWARD articles-count))
    (accuracy-multiplier (if (>= accuracy-score u95) u120 u100)) ;; 20% bonus for 95%+ accuracy
  )
    (/ (* base-reward accuracy-multiplier) u100)
  )
)

(define-private (calculate-community-reward (contributions uint) (validation-accuracy uint))
  (let (
    (base-reward (* COMMUNITY-REWARD contributions))
    (accuracy-bonus (if (>= validation-accuracy u90) u110 u100)) ;; 10% bonus for 90%+ accuracy
  )
    (/ (* base-reward accuracy-bonus) u100)
  )
)

(define-private (get-reputation-multiplier (participant principal))
  (let (
    (account (map-get? reward-accounts { participant: participant }))
  )
    (match account
      acc (get reputation-multiplier acc)
      u100 ;; default 1.0x multiplier
    )
  )
)

(define-private (update-participation-streak (participant principal) (current-period uint))
  (let (
    (account (default-to 
               { total-earned: u0, accuracy-rewards: u0, fact-check-rewards: u0, community-rewards: u0, 
                 bonus-rewards: u0, last-claim-period: u0, participation-streak: u0, reputation-multiplier: u100 }
               (map-get? reward-accounts { participant: participant })))
    (last-period (get last-claim-period account))
    (current-streak (get participation-streak account))
  )
    (let (
      (new-streak (if (is-eq (+ last-period u1) current-period)
                    (+ current-streak u1)
                    u1))
      (new-multiplier (if (< (+ u100 (/ new-streak u4)) u150)
                        (+ u100 (/ new-streak u4))
                        u150)) ;; Up to 1.5x for long streaks
    )
      (map-set reward-accounts
        { participant: participant }
        (merge account {
          last-claim-period: current-period,
          participation-streak: new-streak,
          reputation-multiplier: new-multiplier
        })
      )
      new-multiplier
    )
  )
)

(define-private (distribute-reward-to-participant (participant principal) (amount uint))
  (let (
    (current-balance (ft-get-balance truth-token participant))
  )
    (if (> amount u0)
      (begin
        (unwrap-panic (ft-mint? truth-token amount participant))
        (var-set total-rewards-distributed (+ (var-get total-rewards-distributed) amount))
        (ok amount)
      )
      (ok u0)
    )
  )
)

;; Read-only Functions
(define-read-only (get-balance (account principal))
  (ft-get-balance truth-token account)
)

(define-read-only (get-total-supply)
  (ft-get-supply truth-token)
)

(define-read-only (get-reward-account (participant principal))
  (map-get? reward-accounts { participant: participant })
)

(define-read-only (get-period-claim (participant principal) (period uint))
  (map-get? period-claims { participant: participant, period: period })
)

(define-read-only (get-journalist-performance (journalist principal) (period uint))
  (map-get? journalist-performance { journalist: journalist, period: period })
)

(define-read-only (get-community-contributions (contributor principal) (period uint))
  (map-get? community-contributions { contributor: contributor, period: period })
)

(define-read-only (get-period-allocation (period uint))
  (map-get? period-allocations { period: period })
)

(define-read-only (get-current-reward-period)
  (var-get current-reward-period)
)

(define-read-only (get-reward-stats)
  {
    total-supply: (ft-get-supply truth-token),
    reward-pool-balance: (var-get reward-pool-balance),
    total-rewards-distributed: (var-get total-rewards-distributed),
    active-participants: (var-get active-participants),
    current-period: (var-get current-reward-period)
  }
)

(define-read-only (calculate-pending-rewards (participant principal))
  (let (
    (current-period (var-get current-reward-period))
    (journalist-perf (map-get? journalist-performance { journalist: participant, period: current-period }))
    (community-contrib (map-get? community-contributions { contributor: participant, period: current-period }))
    (reputation-mult (get-reputation-multiplier participant))
  )
    (let (
      (accuracy-reward (match journalist-perf
                         perf (calculate-accuracy-reward (get accuracy-score perf) (get articles-published perf))
                         u0))
      (community-reward (match community-contrib
                          contrib (calculate-community-reward (get fact-checks-performed contrib) u85)
                          u0))
      (total-base (+ accuracy-reward community-reward))
      (final-amount (/ (* total-base reputation-mult) u100))
    )
      {
        accuracy-reward: accuracy-reward,
        community-reward: community-reward,
        reputation-multiplier: reputation-mult,
        total-pending: final-amount
      }
    )
  )
)

(define-read-only (get-special-achievement (achievement-id uint))
  (map-get? special-achievements { achievement-id: achievement-id })
)

(define-read-only (has-earned-achievement (participant principal) (achievement-id uint))
  (is-some (map-get? achievement-earnings { participant: participant, achievement-id: achievement-id }))
)

;; Public Functions
(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
  (begin
    (asserts! (is-eq tx-sender sender) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (ft-transfer? truth-token amount sender recipient)
  )
)

(define-public (record-journalist-performance 
                (journalist principal) 
                (articles uint) 
                (accuracy uint) 
                (fact-checks-passed uint)
                (community-engagement uint))
  (let (
    (current-period (var-get current-reward-period))
    (performance-rating (if (< (/ (+ accuracy community-engagement) u2) u100)
                          (/ (+ accuracy community-engagement) u2)
                          u100))
  )
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (<= accuracy u100) ERR-INVALID-AMOUNT)
    
    (map-set journalist-performance
      { journalist: journalist, period: current-period }
      {
        articles-published: articles,
        accuracy-score: accuracy,
        fact-checks-passed: fact-checks-passed,
        community-engagement: community-engagement,
        ethics-violations: u0,
        performance-rating: performance-rating
      }
    )
    
    (ok true)
  )
)

(define-public (record-community-contribution 
                (contributor principal) 
                (fact-checks uint) 
                (evidence uint) 
                (flags-validated uint)
                (corrections uint))
  (let (
    (current-period (var-get current-reward-period))
    (total-contributions (+ fact-checks evidence flags-validated corrections))
    (contribution-score (if (< (* total-contributions u10) u100)
                          (* total-contributions u10)
                          u100))
  )
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    
    (map-set community-contributions
      { contributor: contributor, period: current-period }
      {
        fact-checks-performed: fact-checks,
        evidence-submitted: evidence,
        flags-validated: flags-validated,
        corrections-approved: corrections,
        contribution-score: contribution-score
      }
    )
    
    (ok true)
  )
)

(define-public (claim-accuracy-rewards)
  (let (
    (current-period (var-get current-reward-period))
    (existing-claim (map-get? period-claims { participant: tx-sender, period: current-period }))
    (journalist-perf (map-get? journalist-performance { journalist: tx-sender, period: current-period }))
  )
    (asserts! (is-none existing-claim) ERR-ALREADY-CLAIMED)
    (asserts! (is-some journalist-perf) ERR-NOT-FOUND)
    
    (let (
      (performance (unwrap-panic journalist-perf))
      (accuracy-score (get accuracy-score performance))
      (articles-count (get articles-published performance))
    )
      (asserts! (>= accuracy-score MIN-ACCURACY-SCORE) ERR-MINIMUM-NOT-MET)
      (asserts! (> articles-count u0) ERR-MINIMUM-NOT-MET)
      
      (let (
        (reward-amount (calculate-accuracy-reward accuracy-score articles-count))
        (reputation-mult (update-participation-streak tx-sender current-period))
        (final-amount (/ (* reward-amount reputation-mult) u100))
      )
        (map-set period-claims
          { participant: tx-sender, period: current-period }
          {
            accuracy-earned: final-amount,
            fact-check-earned: u0,
            community-earned: u0,
            bonus-earned: u0,
            claimed: true,
            claimed-at: (some burn-block-height)
          }
        )
        
        (distribute-reward-to-participant tx-sender final-amount)
      )
    )
  )
)

(define-public (claim-community-rewards)
  (let (
    (current-period (var-get current-reward-period))
    (existing-claim (map-get? period-claims { participant: tx-sender, period: current-period }))
    (community-contrib (map-get? community-contributions { contributor: tx-sender, period: current-period }))
  )
    (asserts! (is-none existing-claim) ERR-ALREADY-CLAIMED)
    (asserts! (is-some community-contrib) ERR-NOT-FOUND)
    
    (let (
      (contributions (unwrap-panic community-contrib))
      (total-contributions (+ (get fact-checks-performed contributions) 
                            (get evidence-submitted contributions)
                            (get flags-validated contributions)
                            (get corrections-approved contributions)))
    )
      (asserts! (>= total-contributions MIN-COMMUNITY-PARTICIPATION) ERR-MINIMUM-NOT-MET)
      
      (let (
        (reward-amount (calculate-community-reward total-contributions u85))
        (reputation-mult (update-participation-streak tx-sender current-period))
        (final-amount (/ (* reward-amount reputation-mult) u100))
      )
        (map-set period-claims
          { participant: tx-sender, period: current-period }
          {
            accuracy-earned: u0,
            fact-check-earned: u0,
            community-earned: final-amount,
            bonus-earned: u0,
            claimed: true,
            claimed-at: (some burn-block-height)
          }
        )
        
        (distribute-reward-to-participant tx-sender final-amount)
      )
    )
  )
)

(define-public (award-bonus-reward (recipient principal) (amount uint) (reason (string-ascii 200)))
  (let (
    (current-period (var-get current-reward-period))
    (account (default-to 
               { total-earned: u0, accuracy-rewards: u0, fact-check-rewards: u0, community-rewards: u0, 
                 bonus-rewards: u0, last-claim-period: u0, participation-streak: u0, reputation-multiplier: u100 }
               (map-get? reward-accounts { participant: recipient })))
  )
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (<= amount (* ACCURACY-REWARD u10)) ERR-INVALID-AMOUNT) ;; Max 10x accuracy reward
    
    (map-set reward-accounts
      { participant: recipient }
      (merge account {
        bonus-rewards: (+ (get bonus-rewards account) amount),
        total-earned: (+ (get total-earned account) amount)
      })
    )
    
    (distribute-reward-to-participant recipient amount)
  )
)

(define-public (create-special-achievement 
                (name (string-ascii 100))
                (description (string-ascii 300))
                (reward-amount uint)
                (criteria (string-ascii 200)))
  (let (
    (achievement-id (+ burn-block-height (to-uint (len name))))
  )
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (> reward-amount u0) ERR-INVALID-AMOUNT)
    
    (map-set special-achievements
      { achievement-id: achievement-id }
      {
        name: name,
        description: description,
        reward-amount: reward-amount,
        criteria: criteria,
        active: true,
        created-by: tx-sender,
        created-at: burn-block-height
      }
    )
    
    (ok achievement-id)
  )
)

(define-public (award-achievement (participant principal) (achievement-id uint))
  (let (
    (achievement (unwrap! (map-get? special-achievements { achievement-id: achievement-id }) ERR-NOT-FOUND))
    (existing-earning (map-get? achievement-earnings { participant: participant, achievement-id: achievement-id }))
    (current-period (var-get current-reward-period))
  )
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (get active achievement) ERR-INVALID-AMOUNT)
    (asserts! (is-none existing-earning) ERR-ALREADY-CLAIMED)
    
    (map-set achievement-earnings
      { participant: participant, achievement-id: achievement-id }
      {
        earned-at: burn-block-height,
        reward-claimed: false,
        period: current-period
      }
    )
    
    (distribute-reward-to-participant participant (get reward-amount achievement))
  )
)

(define-public (start-new-reward-period)
  (let (
    (current-period (var-get current-reward-period))
    (new-period (+ current-period u1))
  )
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    
    ;; Record period allocation
    (map-set period-allocations
      { period: current-period }
      {
        total-allocated: (var-get total-rewards-distributed),
        accuracy-pool: (/ (var-get reward-pool-balance) u4),
        fact-check-pool: (/ (var-get reward-pool-balance) u4),
        community-pool: (/ (var-get reward-pool-balance) u4),
        bonus-pool: (/ (var-get reward-pool-balance) u4),
        participants: (var-get active-participants),
        period-start: (- burn-block-height REWARD-PERIOD-LENGTH),
        period-end: burn-block-height
      }
    )
    
    (var-set current-reward-period new-period)
    (ok new-period)
  )
)

(define-public (fund-reward-pool (amount uint))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    (var-set reward-pool-balance (+ (var-get reward-pool-balance) amount))
    (ft-mint? truth-token amount CONTRACT-OWNER)
  )
)

