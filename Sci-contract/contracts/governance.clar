;; DAO Governance Smart Contract
;; Implements decentralized voting with governance tokens

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u101))
(define-constant ERR-VOTING-ENDED (err u102))
(define-constant ERR-VOTING-NOT-ENDED (err u103))
(define-constant ERR-ALREADY-VOTED (err u104))
(define-constant ERR-INSUFFICIENT-TOKENS (err u105))
(define-constant ERR-PROPOSAL-ALREADY-EXECUTED (err u106))
(define-constant ERR-PROPOSAL-NOT-PASSED (err u107))
(define-constant ERR-INVALID-PROPOSAL (err u108))

;; Data Variables
(define-data-var proposal-counter uint u0)
(define-data-var governance-token-supply uint u1000000) ;; Total governance tokens
(define-data-var voting-period uint u1440) ;; Voting period in blocks (~10 days)
(define-data-var quorum-threshold uint u20) ;; 20% quorum required
(define-data-var pass-threshold uint u51) ;; 51% to pass

;; Data Maps
(define-map proposals
  { proposal-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    proposer: principal,
    start-block: uint,
    end-block: uint,
    votes-for: uint,
    votes-against: uint,
    total-votes: uint,
    executed: bool,
    proposal-type: (string-ascii 20) ;; "feature", "funding", "parameter"
  }
)

(define-map user-votes
  { proposal-id: uint, voter: principal }
  { vote: bool, tokens: uint } ;; true = for, false = against
)

(define-map governance-tokens
  { holder: principal }
  { balance: uint }
)

(define-map proposal-executions
  { proposal-id: uint }
  { execution-data: (string-ascii 200) }
)

;; Initialize governance tokens for testing
(map-set governance-tokens { holder: CONTRACT-OWNER } { balance: u500000 })

;; Read-only functions
(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals { proposal-id: proposal-id })
)

(define-read-only (get-user-vote (proposal-id uint) (voter principal))
  (map-get? user-votes { proposal-id: proposal-id, voter: voter })
)

(define-read-only (get-governance-balance (holder principal))
  (default-to u0 (get balance (map-get? governance-tokens { holder: holder })))
)

(define-read-only (get-proposal-count)
  (var-get proposal-counter)
)

(define-read-only (get-voting-period)
  (var-get voting-period)
)

(define-read-only (get-quorum-threshold)
  (var-get quorum-threshold)
)

(define-read-only (get-pass-threshold)
  (var-get pass-threshold)
)

(define-read-only (calculate-quorum-required)
  (/ (* (var-get governance-token-supply) (var-get quorum-threshold)) u100)
)

(define-read-only (is-proposal-passed (proposal-id uint))
  (match (get-proposal proposal-id)
    proposal-data
    (let
      (
        (total-votes (get total-votes proposal-data))
        (votes-for (get votes-for proposal-data))
        (quorum-required (calculate-quorum-required))
        (pass-required (/ (* total-votes (var-get pass-threshold)) u100))
      )
      (and
        (>= total-votes quorum-required)
        (>= votes-for pass-required)
        (>= stacks-block-height (get end-block proposal-data))
      )
    )
    false
  )
)

(define-read-only (is-voting-active (proposal-id uint))
  (match (get-proposal proposal-id)
    proposal-data
    (and
      (>= stacks-block-height (get start-block proposal-data))
      (< stacks-block-height (get end-block proposal-data))
    )
    false
  )
)

;; Public functions

;; Create a new proposal
(define-public (create-proposal 
  (title (string-ascii 100))
  (description (string-ascii 500))
  (proposal-type (string-ascii 20))
)
  (let
    (
      (proposal-id (+ (var-get proposal-counter) u1))
      (start-block (+ stacks-block-height u1))
      (end-block (+ stacks-block-height (var-get voting-period)))
    )
    ;; Check if user has governance tokens
    (asserts! (> (get-governance-balance tx-sender) u0) ERR-INSUFFICIENT-TOKENS)
    
    ;; Create the proposal
    (map-set proposals
      { proposal-id: proposal-id }
      {
        title: title,
        description: description,
        proposer: tx-sender,
        start-block: start-block,
        end-block: end-block,
        votes-for: u0,
        votes-against: u0,
        total-votes: u0,
        executed: false,
        proposal-type: proposal-type
      }
    )
    
    ;; Update proposal counter
    (var-set proposal-counter proposal-id)
    
    (ok proposal-id)
  )
)

;; Vote on a proposal
(define-public (vote (proposal-id uint) (vote-for bool))
  (let
    (
      (voter-tokens (get-governance-balance tx-sender))
      (proposal-data (unwrap! (get-proposal proposal-id) ERR-PROPOSAL-NOT-FOUND))
    )
    ;; Validate voting conditions
    (asserts! (> voter-tokens u0) ERR-INSUFFICIENT-TOKENS)
    (asserts! (is-voting-active proposal-id) ERR-VOTING-ENDED)
    (asserts! (is-none (get-user-vote proposal-id tx-sender)) ERR-ALREADY-VOTED)
    
    ;; Record the vote
    (map-set user-votes
      { proposal-id: proposal-id, voter: tx-sender }
      { vote: vote-for, tokens: voter-tokens }
    )
    
    ;; Update proposal vote counts
    (map-set proposals
      { proposal-id: proposal-id }
      (merge proposal-data
        {
          votes-for: (if vote-for 
                      (+ (get votes-for proposal-data) voter-tokens)
                      (get votes-for proposal-data)),
          votes-against: (if vote-for
                          (get votes-against proposal-data)
                          (+ (get votes-against proposal-data) voter-tokens)),
          total-votes: (+ (get total-votes proposal-data) voter-tokens)
        }
      )
    )
    
    (ok true)
  )
)

;; Execute a passed proposal
(define-public (execute-proposal (proposal-id uint) (execution-data (string-ascii 200)))
  (let
    (
      (proposal-data (unwrap! (get-proposal proposal-id) ERR-PROPOSAL-NOT-FOUND))
    )
    ;; Validate execution conditions
    (asserts! (not (get executed proposal-data)) ERR-PROPOSAL-ALREADY-EXECUTED)
    (asserts! (>= stacks-block-height (get end-block proposal-data)) ERR-VOTING-NOT-ENDED)
    (asserts! (is-proposal-passed proposal-id) ERR-PROPOSAL-NOT-PASSED)
    
    ;; Mark proposal as executed
    (map-set proposals
      { proposal-id: proposal-id }
      (merge proposal-data { executed: true })
    )
    
    ;; Store execution data
    (map-set proposal-executions
      { proposal-id: proposal-id }
      { execution-data: execution-data }
    )
    
    (ok true)
  )
)

;; Transfer governance tokens
(define-public (transfer-governance-tokens (recipient principal) (amount uint))
  (let
    (
      (sender-balance (get-governance-balance tx-sender))
    )
    (asserts! (>= sender-balance amount) ERR-INSUFFICIENT-TOKENS)
    
    ;; Update sender balance
    (map-set governance-tokens
      { holder: tx-sender }
      { balance: (- sender-balance amount) }
    )
    
    ;; Update recipient balance
    (map-set governance-tokens
      { holder: recipient }
      { balance: (+ (get-governance-balance recipient) amount) }
    )
    
    (ok true)
  )
)

;; Mint governance tokens (only contract owner)
(define-public (mint-governance-tokens (recipient principal) (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    
    ;; Update recipient balance
    (map-set governance-tokens
      { holder: recipient }
      { balance: (+ (get-governance-balance recipient) amount) }
    )
    
    ;; Update total supply
    (var-set governance-token-supply (+ (var-get governance-token-supply) amount))
    
    (ok true)
  )
)

;; Update governance parameters (only through successful proposals)
(define-public (update-voting-period (new-period uint))
  (begin
    (asserts! (is-eq tx-sender (as-contract tx-sender)) ERR-UNAUTHORIZED)
    (var-set voting-period new-period)
    (ok true)
  )
)

(define-public (update-quorum-threshold (new-threshold uint))
  (begin
    (asserts! (is-eq tx-sender (as-contract tx-sender)) ERR-UNAUTHORIZED)
    (asserts! (<= new-threshold u100) ERR-INVALID-PROPOSAL)
    (var-set quorum-threshold new-threshold)
    (ok true)
  )
)

(define-public (update-pass-threshold (new-threshold uint))
  (begin
    (asserts! (is-eq tx-sender (as-contract tx-sender)) ERR-UNAUTHORIZED)
    (asserts! (and (> new-threshold u50) (<= new-threshold u100)) ERR-INVALID-PROPOSAL)
    (var-set pass-threshold new-threshold)
    (ok true)
  )
)

;; Emergency functions (only contract owner)
(define-public (emergency-pause-proposal (proposal-id uint))
  (let
    (
      (proposal-data (unwrap! (get-proposal proposal-id) ERR-PROPOSAL-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    
    ;; Set end block to current block to effectively pause voting
    (map-set proposals
      { proposal-id: proposal-id }
      (merge proposal-data { end-block: stacks-block-height })
    )
    
    (ok true)
  )
)