;; misinformation-prevention-system
;; Identify and flag local misinformation with community verification and correction processes

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-NOT-FOUND (err u301))
(define-constant ERR-ALREADY-FLAGGED (err u302))
(define-constant ERR-INVALID-SEVERITY (err u303))
(define-constant ERR-ALREADY-CORRECTED (err u304))
(define-constant ERR-INVALID-STATUS (err u305))
(define-constant ERR-INSUFFICIENT-FLAGS (err u306))
(define-constant ERR-INVALID-CATEGORY (err u307))

;; Severity levels and thresholds
(define-constant SEVERITY-LOW u1)
(define-constant SEVERITY-MEDIUM u2)
(define-constant SEVERITY-HIGH u3)
(define-constant SEVERITY-CRITICAL u4)

(define-constant MIN-FLAGS-FOR-REVIEW u3)
(define-constant AUTO-REMOVE-THRESHOLD u10)
(define-constant CORRECTION-APPROVAL-THRESHOLD u5)

;; Data Variables
(define-data-var content-counter uint u0)
(define-data-var total-flags uint u0)
(define-data-var active-misinformation uint u0)
(define-data-var corrections-issued uint u0)

;; Content status: 0=active, 1=flagged, 2=under-review, 3=confirmed-misinformation, 4=cleared, 5=corrected
(define-map flagged-content
  { content-id: uint }
  {
    content-hash: (string-ascii 64),
    title: (string-ascii 200),
    description: (string-ascii 1000),
    source-url: (string-ascii 300),
    category: (string-ascii 50),
    submitted-by: principal,
    submitted-at: uint,
    status: uint,
    severity-level: uint,
    flag-count: uint,
    verification-score: uint,
    correction-id: (optional uint)
  }
)

;; Track individual flags from community members
(define-map community-flags
  { flagger: principal, content-id: uint }
  {
    reason: (string-ascii 500),
    severity: uint,
    flagged-at: uint,
    evidence-provided: bool,
    flagger-reputation: uint
  }
)

;; Store corrections and updates
(define-map content-corrections
  { correction-id: uint }
  {
    original-content-id: uint,
    corrected-title: (string-ascii 200),
    corrected-content: (string-ascii 1000),
    correction-explanation: (string-ascii 800),
    corrected-by: principal,
    corrected-at: uint,
    approval-count: uint,
    status: uint, ;; 0=pending, 1=approved, 2=rejected
    source-links: (string-ascii 500)
  }
)

;; Track pattern analysis for misinformation detection
(define-map misinformation-patterns
  { pattern-id: uint }
  {
    pattern-type: (string-ascii 50),
    description: (string-ascii 300),
    keywords: (string-ascii 200),
    detection-count: uint,
    accuracy-rate: uint,
    created-by: principal,
    created-at: uint
  }
)

;; Store community member reputation for flagging accuracy
(define-map flagger-reputation
  { flagger: principal }
  {
    total-flags: uint,
    accurate-flags: uint,
    reputation-score: uint,
    joined-at: uint,
    specialization: (string-ascii 100)
  }
)

;; Track prevention metrics and analytics
(define-map prevention-metrics
  { metric-date: uint }
  {
    total-content-flagged: uint,
    confirmed-misinformation: uint,
    false-positives: uint,
    corrections-issued: uint,
    community-participation: uint
  }
)

;; Store approval votes for corrections
(define-map correction-approvals
  { approver: principal, correction-id: uint }
  {
    approved: bool,
    reasoning: (string-ascii 300),
    approved-at: uint
  }
)

;; Private Functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

(define-private (calculate-verification-score (flag-count uint) (severity uint) (flagger-rep uint))
  (let (
    (base-score (* flag-count u10))
    (severity-multiplier severity)
    (reputation-bonus (/ flagger-rep u10))
  )
    (+ base-score (* base-score severity-multiplier) reputation-bonus)
  )
)

(define-private (update-flagger-reputation (flagger principal) (accuracy-bonus uint))
  (let (
    (existing-rep (default-to 
                    { total-flags: u0, accurate-flags: u0, reputation-score: u50, joined-at: burn-block-height, specialization: "general" }
                    (map-get? flagger-reputation { flagger: flagger })
                  ))
  )
    (map-set flagger-reputation
      { flagger: flagger }
      {
        total-flags: (+ (get total-flags existing-rep) u1),
        accurate-flags: (+ (get accurate-flags existing-rep) accuracy-bonus),
        reputation-score: (if (< (+ (get reputation-score existing-rep) (* accuracy-bonus u5)) u100)
                            (+ (get reputation-score existing-rep) (* accuracy-bonus u5))
                            u100),
        joined-at: (get joined-at existing-rep),
        specialization: (get specialization existing-rep)
      }
    )
  )
)

(define-private (get-flagger-weight (flagger principal))
  (let (
    (reputation (map-get? flagger-reputation { flagger: flagger }))
  )
    (match reputation
      rep (if (> (/ (get reputation-score rep) u20) u1)
            (/ (get reputation-score rep) u20)
            u1)
      u1
    )
  )
)

(define-private (auto-escalate-if-needed (content-id uint) (new-flag-count uint) (severity uint))
  (let (
    (content (unwrap-panic (map-get? flagged-content { content-id: content-id })))
  )
    (if (or 
          (>= new-flag-count AUTO-REMOVE-THRESHOLD)
          (and (>= severity SEVERITY-CRITICAL) (>= new-flag-count u5))
        )
      (map-set flagged-content
        { content-id: content-id }
        (merge content { status: u3 }) ;; confirmed-misinformation
      )
      (if (>= new-flag-count MIN-FLAGS-FOR-REVIEW)
        (map-set flagged-content
          { content-id: content-id }
          (merge content { status: u2 }) ;; under-review
        )
        true
      )
    )
  )
)

;; Read-only Functions
(define-read-only (get-flagged-content (content-id uint))
  (map-get? flagged-content { content-id: content-id })
)

(define-read-only (get-community-flag (flagger principal) (content-id uint))
  (map-get? community-flags { flagger: flagger, content-id: content-id })
)

(define-read-only (get-content-correction (correction-id uint))
  (map-get? content-corrections { correction-id: correction-id })
)

(define-read-only (get-misinformation-pattern (pattern-id uint))
  (map-get? misinformation-patterns { pattern-id: pattern-id })
)

(define-read-only (get-flagger-reputation (flagger principal))
  (map-get? flagger-reputation { flagger: flagger })
)

(define-read-only (get-prevention-metrics (metric-date uint))
  (map-get? prevention-metrics { metric-date: metric-date })
)

(define-read-only (get-system-stats)
  {
    total-flags: (var-get total-flags),
    active-misinformation: (var-get active-misinformation),
    corrections-issued: (var-get corrections-issued),
    content-flagged: (var-get content-counter)
  }
)

(define-read-only (has-flagged-content (flagger principal) (content-id uint))
  (is-some (map-get? community-flags { flagger: flagger, content-id: content-id }))
)

(define-read-only (is-content-misinformation (content-id uint))
  (match (map-get? flagged-content { content-id: content-id })
    content (is-eq (get status content) u3)
    false
  )
)

(define-read-only (get-correction-approval (approver principal) (correction-id uint))
  (map-get? correction-approvals { approver: approver, correction-id: correction-id })
)

;; Public Functions
(define-public (flag-content 
                (content-hash (string-ascii 64))
                (title (string-ascii 200))
                (description (string-ascii 1000))
                (source-url (string-ascii 300))
                (category (string-ascii 50))
                (reason (string-ascii 500))
                (severity uint))
  (let (
    (content-id (+ (var-get content-counter) u1))
    (flagger-weight (get-flagger-weight tx-sender))
  )
    (asserts! (and (>= severity SEVERITY-LOW) (<= severity SEVERITY-CRITICAL)) ERR-INVALID-SEVERITY)
    
    (map-set flagged-content
      { content-id: content-id }
      {
        content-hash: content-hash,
        title: title,
        description: description,
        source-url: source-url,
        category: category,
        submitted-by: tx-sender,
        submitted-at: burn-block-height,
        status: u1, ;; flagged
        severity-level: severity,
        flag-count: flagger-weight,
        verification-score: (calculate-verification-score flagger-weight severity u50),
        correction-id: none
      }
    )
    
    (map-set community-flags
      { flagger: tx-sender, content-id: content-id }
      {
        reason: reason,
        severity: severity,
        flagged-at: burn-block-height,
        evidence-provided: true,
        flagger-reputation: (get-flagger-weight tx-sender)
      }
    )
    
    (var-set content-counter content-id)
    (var-set total-flags (+ (var-get total-flags) u1))
    (var-set active-misinformation (+ (var-get active-misinformation) u1))
    
    (auto-escalate-if-needed content-id flagger-weight severity)
    
    (ok content-id)
  )
)

(define-public (add-flag-to-existing (content-id uint) (reason (string-ascii 500)) (severity uint))
  (let (
    (content (unwrap! (map-get? flagged-content { content-id: content-id }) ERR-NOT-FOUND))
    (existing-flag (map-get? community-flags { flagger: tx-sender, content-id: content-id }))
    (flagger-weight (get-flagger-weight tx-sender))
  )
    (asserts! (is-none existing-flag) ERR-ALREADY-FLAGGED)
    (asserts! (and (>= severity SEVERITY-LOW) (<= severity SEVERITY-CRITICAL)) ERR-INVALID-SEVERITY)
    (asserts! (< (get status content) u3) ERR-ALREADY-CORRECTED)
    
    (map-set community-flags
      { flagger: tx-sender, content-id: content-id }
      {
        reason: reason,
        severity: severity,
        flagged-at: burn-block-height,
        evidence-provided: true,
        flagger-reputation: flagger-weight
      }
    )
    
    (let (
      (new-flag-count (+ (get flag-count content) flagger-weight))
      (new-verification-score (calculate-verification-score new-flag-count severity flagger-weight))
    )
      (map-set flagged-content
        { content-id: content-id }
        (merge content {
          flag-count: new-flag-count,
          verification-score: new-verification-score,
          severity-level: (max (get severity-level content) severity)
        })
      )
      
      (var-set total-flags (+ (var-get total-flags) u1))
      (auto-escalate-if-needed content-id new-flag-count severity)
      (ok true)
    )
  )
)

(define-public (submit-correction 
                (content-id uint)
                (corrected-title (string-ascii 200))
                (corrected-content (string-ascii 1000))
                (correction-explanation (string-ascii 800))
                (source-links (string-ascii 500)))
  (let (
    (content (unwrap! (map-get? flagged-content { content-id: content-id }) ERR-NOT-FOUND))
    (correction-id (+ (var-get corrections-issued) u1))
  )
    (asserts! (>= (get status content) u2) ERR-INVALID-STATUS)
    
    (map-set content-corrections
      { correction-id: correction-id }
      {
        original-content-id: content-id,
        corrected-title: corrected-title,
        corrected-content: corrected-content,
        correction-explanation: correction-explanation,
        corrected-by: tx-sender,
        corrected-at: burn-block-height,
        approval-count: u0,
        status: u0, ;; pending
        source-links: source-links
      }
    )
    
    (map-set flagged-content
      { content-id: content-id }
      (merge content { correction-id: (some correction-id) })
    )
    
    (var-set corrections-issued correction-id)
    (ok correction-id)
  )
)

(define-public (approve-correction (correction-id uint) (reasoning (string-ascii 300)))
  (let (
    (correction (unwrap! (map-get? content-corrections { correction-id: correction-id }) ERR-NOT-FOUND))
    (existing-approval (map-get? correction-approvals { approver: tx-sender, correction-id: correction-id }))
  )
    (asserts! (is-none existing-approval) ERR-ALREADY-FLAGGED)
    (asserts! (is-eq (get status correction) u0) ERR-INVALID-STATUS)
    
    (map-set correction-approvals
      { approver: tx-sender, correction-id: correction-id }
      {
        approved: true,
        reasoning: reasoning,
        approved-at: burn-block-height
      }
    )
    
    (let (
      (new-approval-count (+ (get approval-count correction) u1))
    )
      (map-set content-corrections
        { correction-id: correction-id }
        (merge correction { approval-count: new-approval-count })
      )
      
      ;; Auto-approve if threshold reached
      (if (>= new-approval-count CORRECTION-APPROVAL-THRESHOLD)
        (map-set content-corrections
          { correction-id: correction-id }
          (merge correction { 
            approval-count: new-approval-count,
            status: u1 ;; approved
          })
        )
        true
      )
      
      (ok true)
    )
  )
)

(define-public (verify-content-accuracy (content-id uint) (is-misinformation bool))
  (let (
    (content (unwrap! (map-get? flagged-content { content-id: content-id }) ERR-NOT-FOUND))
  )
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status content) u2) ERR-INVALID-STATUS)
    
    (let (
      (new-status (if is-misinformation u3 u4)) ;; confirmed-misinformation or cleared
    )
      (map-set flagged-content
        { content-id: content-id }
        (merge content { status: new-status })
      )
      
      ;; Update flagger reputations based on accuracy
      ;; This would require iterating through all flags, simplified here
      (if is-misinformation
        (var-set active-misinformation (+ (var-get active-misinformation) u1))
        (var-set active-misinformation (- (var-get active-misinformation) u1))
      )
      
      (ok new-status)
    )
  )
)

(define-public (create-misinformation-pattern 
                (pattern-type (string-ascii 50))
                (description (string-ascii 300))
                (keywords (string-ascii 200)))
  (let (
    (pattern-id (+ burn-block-height (to-uint (len pattern-type))))
  )
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    
    (map-set misinformation-patterns
      { pattern-id: pattern-id }
      {
        pattern-type: pattern-type,
        description: description,
        keywords: keywords,
        detection-count: u0,
        accuracy-rate: u0,
        created-by: tx-sender,
        created-at: burn-block-height
      }
    )
    
    (ok pattern-id)
  )
)

(define-public (register-prevention-specialist (specialization (string-ascii 100)))
  (let (
    (existing-rep (map-get? flagger-reputation { flagger: tx-sender }))
  )
    (asserts! (is-none existing-rep) ERR-ALREADY-FLAGGED)
    
    (map-set flagger-reputation
      { flagger: tx-sender }
      {
        total-flags: u0,
        accurate-flags: u0,
        reputation-score: u60, ;; specialists start with higher score
        joined-at: burn-block-height,
        specialization: specialization
      }
    )
    
    (ok true)
  )
)

(define-public (update-prevention-metrics (metric-date uint))
  (let (
    (existing-metrics (map-get? prevention-metrics { metric-date: metric-date }))
  )
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    
    (map-set prevention-metrics
      { metric-date: metric-date }
      {
        total-content-flagged: (var-get content-counter),
        confirmed-misinformation: (var-get active-misinformation),
        false-positives: u0, ;; Would be calculated based on verification results
        corrections-issued: (var-get corrections-issued),
        community-participation: (var-get total-flags)
      }
    )
    
    (ok true)
  )
)

