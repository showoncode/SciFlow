;; Academic Reputation Token System
;; A comprehensive system for tracking and rewarding academic contributions

;; Define the fungible token for reputation points
(define-fungible-token reputation-token)

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_BALANCE (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_ALREADY_REVIEWED (err u103))
(define-constant ERR_INSUFFICIENT_STAKE (err u104))
(define-constant ERR_REVIEW_NOT_FOUND (err u105))
(define-constant ERR_INVALID_RATING (err u106))

;; Minimum stake required for review moderation
(define-constant MIN_REVIEW_STAKE u1000)

;; Reward amounts for different contribution types
(define-constant PEER_REVIEW_REWARD u100)
(define-constant CITATION_REWARD u50)
(define-constant FEEDBACK_REWARD u25)
(define-constant PUBLICATION_REWARD u200)
(define-constant COLLABORATION_REWARD u75)

;; Data Variables
(define-data-var total-contributions uint u0)
(define-data-var review-counter uint u0)

;; Data Maps
(define-map user-contributions 
  principal 
  {
    peer-reviews: uint,
    citations: uint,
    feedback-given: uint,
    publications: uint,
    collaborations: uint,
    total-reputation: uint
  }
)

(define-map publication-reviews
  uint ;; publication-id
  {
    reviewer: principal,
    rating: uint, ;; 1-5 scale
    stake-amount: uint,
    review-text: (string-ascii 500),
    timestamp: uint,
    validated: bool
  }
)

(define-map user-stakes
  principal
  uint ;; staked amount
)

(define-map review-validations
  uint ;; review-id
  {
    validators: (list 10 principal),
    validation-count: uint,
    consensus-reached: bool
  }
)

;; Initialize user contribution record
(define-private (init-user-contributions (user principal))
  (default-to 
    {
      peer-reviews: u0,
      citations: u0,
      feedback-given: u0,
      publications: u0,
      collaborations: u0,
      total-reputation: u0
    }
    (map-get? user-contributions user)
  )
)

;; Mint initial reputation tokens (only contract owner)
(define-public (mint-reputation (recipient principal) (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (ft-mint? reputation-token amount recipient))
    (ok amount)
  )
)

;; Reward peer review contribution
(define-public (reward-peer-review (reviewer principal) (publication-id uint))
  (let (
    (current-contributions (init-user-contributions reviewer))
    (new-peer-reviews (+ (get peer-reviews current-contributions) u1))
    (new-total-reputation (+ (get total-reputation current-contributions) PEER_REVIEW_REWARD))
  )
    (try! (ft-mint? reputation-token PEER_REVIEW_REWARD reviewer))
    (map-set user-contributions reviewer
      (merge current-contributions {
        peer-reviews: new-peer-reviews,
        total-reputation: new-total-reputation
      })
    )
    (var-set total-contributions (+ (var-get total-contributions) u1))
    (ok PEER_REVIEW_REWARD)
  )
)

;; Reward citation
(define-public (reward-citation (author principal) (citing-paper-id uint))
  (let (
    (current-contributions (init-user-contributions author))
    (new-citations (+ (get citations current-contributions) u1))
    (new-total-reputation (+ (get total-reputation current-contributions) CITATION_REWARD))
  )
    (try! (ft-mint? reputation-token CITATION_REWARD author))
    (map-set user-contributions author
      (merge current-contributions {
        citations: new-citations,
        total-reputation: new-total-reputation
      })
    )
    (var-set total-contributions (+ (var-get total-contributions) u1))
    (ok CITATION_REWARD)
  )
)

;; Reward feedback contribution
(define-public (reward-feedback (contributor principal) (feedback-id uint))
  (let (
    (current-contributions (init-user-contributions contributor))
    (new-feedback (+ (get feedback-given current-contributions) u1))
    (new-total-reputation (+ (get total-reputation current-contributions) FEEDBACK_REWARD))
  )
    (try! (ft-mint? reputation-token FEEDBACK_REWARD contributor))
    (map-set user-contributions contributor
      (merge current-contributions {
        feedback-given: new-feedback,
        total-reputation: new-total-reputation
      })
    )
    (var-set total-contributions (+ (var-get total-contributions) u1))
    (ok FEEDBACK_REWARD)
  )
)

;; Reward publication
(define-public (reward-publication (author principal) (publication-id uint))
  (let (
    (current-contributions (init-user-contributions author))
    (new-publications (+ (get publications current-contributions) u1))
    (new-total-reputation (+ (get total-reputation current-contributions) PUBLICATION_REWARD))
  )
    (try! (ft-mint? reputation-token PUBLICATION_REWARD author))
    (map-set user-contributions author
      (merge current-contributions {
        publications: new-publications,
        total-reputation: new-total-reputation
      })
    )
    (var-set total-contributions (+ (var-get total-contributions) u1))
    (ok PUBLICATION_REWARD)
  )
)

;; Reward collaboration
(define-public (reward-collaboration (collaborator principal) (project-id uint))
  (let (
    (current-contributions (init-user-contributions collaborator))
    (new-collaborations (+ (get collaborations current-contributions) u1))
    (new-total-reputation (+ (get total-reputation current-contributions) COLLABORATION_REWARD))
  )
    (try! (ft-mint? reputation-token COLLABORATION_REWARD collaborator))
    (map-set user-contributions collaborator
      (merge current-contributions {
        collaborations: new-collaborations,
        total-reputation: new-total-reputation
      })
    )
    (var-set total-contributions (+ (var-get total-contributions) u1))
    (ok COLLABORATION_REWARD)
  )
)

;; Stake tokens for review moderation
(define-public (stake-for-review (amount uint))
  (begin
    (asserts! (>= amount MIN_REVIEW_STAKE) ERR_INSUFFICIENT_STAKE)
    (asserts! (>= (ft-get-balance reputation-token tx-sender) amount) ERR_INSUFFICIENT_BALANCE)
    
    (try! (ft-transfer? reputation-token amount tx-sender (as-contract tx-sender)))
    (map-set user-stakes tx-sender 
      (+ (default-to u0 (map-get? user-stakes tx-sender)) amount)
    )
    (ok amount)
  )
)

;; Submit a staked review
(define-public (submit-staked-review 
  (publication-id uint) 
  (rating uint) 
  (review-text (string-ascii 500))
  (stake-amount uint)
)
  (let (
    (review-id (+ (var-get review-counter) u1))
    (user-stake (default-to u0 (map-get? user-stakes tx-sender)))
  )
    (asserts! (and (>= rating u1) (<= rating u5)) ERR_INVALID_RATING)
    (asserts! (>= user-stake stake-amount) ERR_INSUFFICIENT_STAKE)
    (asserts! (>= stake-amount MIN_REVIEW_STAKE) ERR_INSUFFICIENT_STAKE)
    
    ;; Check if user already reviewed this publication
    (asserts! (is-none (map-get? publication-reviews publication-id)) ERR_ALREADY_REVIEWED)
    
    (map-set publication-reviews review-id {
      reviewer: tx-sender,
      rating: rating,
      stake-amount: stake-amount,
      review-text: review-text,
      timestamp: stacks-block-height,
      validated: false
    })
    
    (var-set review-counter review-id)
    (ok review-id)
  )
)

;; Validate a review (requires stake)
(define-public (validate-review (review-id uint) (is-valid bool))
  (let (
    (review (unwrap! (map-get? publication-reviews review-id) ERR_REVIEW_NOT_FOUND))
    (user-stake (default-to u0 (map-get? user-stakes tx-sender)))
    (validation-data (default-to 
      { validators: (list), validation-count: u0, consensus-reached: false }
      (map-get? review-validations review-id)
    ))
  )
    (asserts! (>= user-stake MIN_REVIEW_STAKE) ERR_INSUFFICIENT_STAKE)
    (asserts! (not (get consensus-reached validation-data)) ERR_UNAUTHORIZED)
    
    ;; Add validator to the list if not already present
    (let (
      (new-validators (unwrap! (as-max-len? 
        (append (get validators validation-data) tx-sender) u10) ERR_UNAUTHORIZED))
      (new-count (+ (get validation-count validation-data) u1))
    )
      (map-set review-validations review-id {
        validators: new-validators,
        validation-count: new-count,
        consensus-reached: (>= new-count u3) ;; Consensus with 3+ validators
      })
      
      ;; If consensus reached and review is valid, reward the reviewer
      (if (and (>= new-count u3) is-valid)
        (begin
          (try! (reward-peer-review (get reviewer review) review-id))
          (ok u1)
        )
        (ok u1)
      )
    )
  )
)

;; Unstake tokens
(define-public (unstake (amount uint))
  (let (
    (user-stake (default-to u0 (map-get? user-stakes tx-sender)))
  )
    (asserts! (>= user-stake amount) ERR_INSUFFICIENT_BALANCE)
    (try! (as-contract (ft-transfer? reputation-token amount tx-sender tx-sender)))
    (map-set user-stakes tx-sender (- user-stake amount))
    (ok amount)
  )
)

;; Read-only functions

;; Get user's reputation balance
(define-read-only (get-reputation-balance (user principal))
  (ft-get-balance reputation-token user)
)

;; Get user's contribution statistics
(define-read-only (get-user-contributions (user principal))
  (init-user-contributions user)
)

;; Get user's stake amount
(define-read-only (get-user-stake (user principal))
  (default-to u0 (map-get? user-stakes user))
)

;; Get review details
(define-read-only (get-review (review-id uint))
  (map-get? publication-reviews review-id)
)

;; Get review validation status
(define-read-only (get-review-validation (review-id uint))
  (map-get? review-validations review-id)
)

;; Get total system statistics
(define-read-only (get-system-stats)
  {
    total-contributions: (var-get total-contributions),
    total-reviews: (var-get review-counter),
    total-supply: (ft-get-supply reputation-token)
  }
)

;; Calculate reputation score based on contributions
(define-read-only (calculate-reputation-score (user principal))
  (let (
    (contributions (init-user-contributions user))
  )
    (+
      (* (get peer-reviews contributions) PEER_REVIEW_REWARD)
      (* (get citations contributions) CITATION_REWARD)
      (* (get feedback-given contributions) FEEDBACK_REWARD)
      (* (get publications contributions) PUBLICATION_REWARD)
      (* (get collaborations contributions) COLLABORATION_REWARD)
    )
  )
)

;; Get top contributors (simplified version - returns contribution count)
(define-read-only (get-contributor-rank (user principal))
  (let (
    (contributions (init-user-contributions user))
  )
    (+
      (get peer-reviews contributions)
      (get citations contributions)
      (get feedback-given contributions)
      (get publications contributions)
      (get collaborations contributions)
    )
  )
)
