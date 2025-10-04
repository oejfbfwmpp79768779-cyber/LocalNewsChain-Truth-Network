;; fact-checking-coordination
;; Coordinate community fact-checking efforts for local news stories and claims verification

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-NOT-FOUND (err u201))
(define-constant ERR-ALREADY-EXISTS (err u202))
(define-constant ERR-INVALID-STATUS (err u203))
(define-constant ERR-ALREADY-VOTED (err u204))
(define-constant ERR-INSUFFICIENT-CHECKERS (err u205))
(define-constant ERR-VERIFICATION-CLOSED (err u206))
(define-constant ERR-INVALID-SCORE (err u207))

;; Minimum number of fact-checkers required for consensus
(define-constant MIN-FACT-CHECKERS u3)
(define-constant MAX-EVIDENCE-ITEMS u10)
(define-constant CONSENSUS-THRESHOLD u66) ;; 66% agreement required

;; Data Variables
(define-data-var story-counter uint u0)
(define-data-var total-verifications uint u0)
(define-data-var active-verifications uint u0)

;; Verification statuses: 0=pending, 1=in-progress, 2=verified-true, 3=verified-false, 4=inconclusive
(define-map story-verifications
  { story-id: uint }
  {
    title: (string-ascii 200),
    content: (string-ascii 1000),
    submitted-by: principal,
    submitted-at: uint,
    status: uint,
    total-votes: uint,
    true-votes: uint,
    false-votes: uint,
    inconclusive-votes: uint,
    evidence-count: uint,
    final-verdict: (optional bool),
    completed-at: (optional uint)
  }
)

;; Track fact-checker participation
(define-map fact-checker-votes
  { checker: principal, story-id: uint }
  {
    vote: uint, ;; 1=true, 2=false, 3=inconclusive
    reasoning: (string-ascii 500),
    voted-at: uint,
    credibility-weight: uint
  }
)

;; Store evidence for each story
(define-map story-evidence
  { story-id: uint, evidence-id: uint }
  {
    evidence-type: (string-ascii 50), ;; source, document, witness, etc.
    description: (string-ascii 500),
    source-url: (string-ascii 200),
    credibility-score: uint,
    submitted-by: principal,
    submitted-at: uint
  }
)

;; Track fact-checker reputation
(define-map fact-checker-stats
  { checker: principal }
  {
    total-checks: uint,
    accurate-checks: uint,
    reputation-score: uint,
    joined-at: uint,
    specialization: (string-ascii 100)
  }
)

;; Store verification workflows
(define-map verification-workflows
  { story-id: uint, step: uint }
  {
    step-name: (string-ascii 100),
    description: (string-ascii 300),
    completed: bool,
    completed-by: (optional principal),
    completed-at: (optional uint)
  }
)

;; Private Functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

(define-private (calculate-consensus (true-votes uint) (false-votes uint) (total-votes uint))
  (if (> total-votes u0)
    (let (
      (true-percentage (* (/ true-votes total-votes) u100))
      (false-percentage (* (/ false-votes total-votes) u100))
    )
      (if (>= true-percentage CONSENSUS-THRESHOLD)
        u2 ;; verified-true
        (if (>= false-percentage CONSENSUS-THRESHOLD)
          u3 ;; verified-false
          u4 ;; inconclusive
        )
      )
    )
    u0 ;; pending
  )
)

(define-private (update-fact-checker-stats (checker principal) (accuracy-bonus uint))
  (let (
    (existing-stats (default-to 
                      { total-checks: u0, accurate-checks: u0, reputation-score: u50, joined-at: burn-block-height, specialization: "general" }
                      (map-get? fact-checker-stats { checker: checker })
                    ))
  )
    (map-set fact-checker-stats
      { checker: checker }
      {
        total-checks: (+ (get total-checks existing-stats) u1),
        accurate-checks: (+ (get accurate-checks existing-stats) accuracy-bonus),
        reputation-score: (if (< (+ (get reputation-score existing-stats) accuracy-bonus) u100)
                            (+ (get reputation-score existing-stats) accuracy-bonus)
                            u100),
        joined-at: (get joined-at existing-stats),
        specialization: (get specialization existing-stats)
      }
    )
  )
)

(define-private (get-checker-weight (checker principal))
  (let (
    (stats (map-get? fact-checker-stats { checker: checker }))
  )
    (match stats
      checker-stats (if (> (/ (get reputation-score checker-stats) u10) u1)
                      (/ (get reputation-score checker-stats) u10)
                      u1)
      u1
    )
  )
)

;; Read-only Functions
(define-read-only (get-story-verification (story-id uint))
  (map-get? story-verifications { story-id: story-id })
)

(define-read-only (get-fact-checker-vote (checker principal) (story-id uint))
  (map-get? fact-checker-votes { checker: checker, story-id: story-id })
)

(define-read-only (get-story-evidence (story-id uint) (evidence-id uint))
  (map-get? story-evidence { story-id: story-id, evidence-id: evidence-id })
)

(define-read-only (get-fact-checker-stats (checker principal))
  (map-get? fact-checker-stats { checker: checker })
)

(define-read-only (get-verification-stats)
  {
    total-verifications: (var-get total-verifications),
    active-verifications: (var-get active-verifications),
    completed-verifications: (- (var-get total-verifications) (var-get active-verifications))
  }
)

(define-read-only (has-voted (checker principal) (story-id uint))
  (is-some (map-get? fact-checker-votes { checker: checker, story-id: story-id }))
)

(define-read-only (get-workflow-step (story-id uint) (step uint))
  (map-get? verification-workflows { story-id: story-id, step: step })
)

(define-read-only (is-verification-complete (story-id uint))
  (match (map-get? story-verifications { story-id: story-id })
    story (or (is-eq (get status story) u2) 
              (is-eq (get status story) u3) 
              (is-eq (get status story) u4))
    false
  )
)

;; Public Functions
(define-public (submit-for-verification (title (string-ascii 200)) (content (string-ascii 1000)))
  (let (
    (story-id (+ (var-get story-counter) u1))
  )
    (map-set story-verifications
      { story-id: story-id }
      {
        title: title,
        content: content,
        submitted-by: tx-sender,
        submitted-at: burn-block-height,
        status: u0, ;; pending
        total-votes: u0,
        true-votes: u0,
        false-votes: u0,
        inconclusive-votes: u0,
        evidence-count: u0,
        final-verdict: none,
        completed-at: none
      }
    )
    
    ;; Initialize workflow steps
    (map-set verification-workflows
      { story-id: story-id, step: u1 }
      { step-name: "Evidence Collection", description: "Gather supporting evidence", completed: false, completed-by: none, completed-at: none }
    )
    (map-set verification-workflows
      { story-id: story-id, step: u2 }
      { step-name: "Fact-Checker Review", description: "Expert fact-checker analysis", completed: false, completed-by: none, completed-at: none }
    )
    (map-set verification-workflows
      { story-id: story-id, step: u3 }
      { step-name: "Community Consensus", description: "Final community verification", completed: false, completed-by: none, completed-at: none }
    )
    
    (var-set story-counter story-id)
    (var-set total-verifications (+ (var-get total-verifications) u1))
    (var-set active-verifications (+ (var-get active-verifications) u1))
    
    (ok story-id)
  )
)

(define-public (submit-evidence (story-id uint) (evidence-type (string-ascii 50)) (description (string-ascii 500)) (source-url (string-ascii 200)))
  (let (
    (story (unwrap! (map-get? story-verifications { story-id: story-id }) ERR-NOT-FOUND))
    (evidence-id (+ (get evidence-count story) u1))
  )
    (asserts! (< (get evidence-count story) MAX-EVIDENCE-ITEMS) ERR-INVALID-STATUS)
    (asserts! (< (get status story) u2) ERR-VERIFICATION-CLOSED)
    
    (map-set story-evidence
      { story-id: story-id, evidence-id: evidence-id }
      {
        evidence-type: evidence-type,
        description: description,
        source-url: source-url,
        credibility-score: u50, ;; default score
        submitted-by: tx-sender,
        submitted-at: burn-block-height
      }
    )
    
    (map-set story-verifications
      { story-id: story-id }
      (merge story { evidence-count: evidence-id })
    )
    
    (ok evidence-id)
  )
)

(define-public (cast-fact-check-vote (story-id uint) (vote uint) (reasoning (string-ascii 500)))
  (let (
    (story (unwrap! (map-get? story-verifications { story-id: story-id }) ERR-NOT-FOUND))
    (existing-vote (map-get? fact-checker-votes { checker: tx-sender, story-id: story-id }))
    (checker-weight (get-checker-weight tx-sender))
  )
    (asserts! (is-none existing-vote) ERR-ALREADY-VOTED)
    (asserts! (and (>= vote u1) (<= vote u3)) ERR-INVALID-STATUS)
    (asserts! (< (get status story) u2) ERR-VERIFICATION-CLOSED)
    
    (map-set fact-checker-votes
      { checker: tx-sender, story-id: story-id }
      {
        vote: vote,
        reasoning: reasoning,
        voted-at: burn-block-height,
        credibility-weight: checker-weight
      }
    )
    
    ;; Update story vote counts
    (let (
      (new-total (+ (get total-votes story) checker-weight))
      (new-true (if (is-eq vote u1) (+ (get true-votes story) checker-weight) (get true-votes story)))
      (new-false (if (is-eq vote u2) (+ (get false-votes story) checker-weight) (get false-votes story)))
      (new-inconclusive (if (is-eq vote u3) (+ (get inconclusive-votes story) checker-weight) (get inconclusive-votes story)))
    )
      (map-set story-verifications
        { story-id: story-id }
        (merge story {
          total-votes: new-total,
          true-votes: new-true,
          false-votes: new-false,
          inconclusive-votes: new-inconclusive,
          status: (if (>= new-total MIN-FACT-CHECKERS)
                    (calculate-consensus new-true new-false new-total)
                    u1) ;; in-progress
        })
      )
      
      ;; Update fact-checker stats
      (update-fact-checker-stats tx-sender u1)
      
      (ok true)
    )
  )
)

(define-public (finalize-verification (story-id uint))
  (let (
    (story (unwrap! (map-get? story-verifications { story-id: story-id }) ERR-NOT-FOUND))
  )
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (>= (get total-votes story) MIN-FACT-CHECKERS) ERR-INSUFFICIENT-CHECKERS)
    (asserts! (< (get status story) u2) ERR-VERIFICATION-CLOSED)
    
    (let (
      (final-status (calculate-consensus (get true-votes story) (get false-votes story) (get total-votes story)))
      (verdict (if (is-eq final-status u2) 
                 (some true) 
                 (if (is-eq final-status u3) 
                   (some false) 
                   none)))
    )
      (map-set story-verifications
        { story-id: story-id }
        (merge story {
          status: final-status,
          final-verdict: verdict,
          completed-at: (some burn-block-height)
        })
      )
      
      ;; Mark workflow as complete
      (map-set verification-workflows
        { story-id: story-id, step: u3 }
        { step-name: "Community Consensus", description: "Final community verification", completed: true, completed-by: (some tx-sender), completed-at: (some burn-block-height) }
      )
      
      (var-set active-verifications (- (var-get active-verifications) u1))
      (ok final-status)
    )
  )
)

(define-public (register-fact-checker (specialization (string-ascii 100)))
  (let (
    (existing-stats (map-get? fact-checker-stats { checker: tx-sender }))
  )
    (asserts! (is-none existing-stats) ERR-ALREADY-EXISTS)
    
    (map-set fact-checker-stats
      { checker: tx-sender }
      {
        total-checks: u0,
        accurate-checks: u0,
        reputation-score: u50,
        joined-at: burn-block-height,
        specialization: specialization
      }
    )
    
    (ok true)
  )
)

(define-public (rate-evidence-credibility (story-id uint) (evidence-id uint) (credibility-score uint))
  (let (
    (evidence (unwrap! (map-get? story-evidence { story-id: story-id, evidence-id: evidence-id }) ERR-NOT-FOUND))
    (story (unwrap! (map-get? story-verifications { story-id: story-id }) ERR-NOT-FOUND))
  )
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (<= credibility-score u100) ERR-INVALID-SCORE)
    
    (map-set story-evidence
      { story-id: story-id, evidence-id: evidence-id }
      (merge evidence { credibility-score: credibility-score })
    )
    
    (ok true)
  )
)

(define-public (update-workflow-step (story-id uint) (step uint))
  (let (
    (workflow (unwrap! (map-get? verification-workflows { story-id: story-id, step: step }) ERR-NOT-FOUND))
  )
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (not (get completed workflow)) ERR-INVALID-STATUS)
    
    (map-set verification-workflows
      { story-id: story-id, step: step }
      (merge workflow {
        completed: true,
        completed-by: (some tx-sender),
        completed-at: (some burn-block-height)
      })
    )
    
    (ok true)
  )
)

