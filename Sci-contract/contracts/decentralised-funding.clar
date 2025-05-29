;; Decentralized Funding Models Contract

;; Define constants
(define-constant contract-owner tx-sender)
(define-constant err-not-authorized (err u100))
(define-constant err-project-exists (err u101))
(define-constant err-project-not-found (err u102))
(define-constant err-nft-exists (err u103))
(define-constant err-nft-not-found (err u104))
(define-constant err-proposal-exists (err u105))
(define-constant err-proposal-not-found (err u106))
(define-constant err-invalid-amount (err u107))
(define-constant err-already-voted (err u108))
(define-constant err-voting-closed (err u109))
(define-constant err-proposal-not-approved (err u110))
(define-constant err-insufficient-funds (err u111))
(define-constant err-not-owner (err u112))
(define-constant err-nft-not-for-sale (err u113))

;; Define data maps
(define-map research-projects
  { id: uint }
  {
    researcher: principal,
    title: (string-ascii 64),
    description: (string-ascii 256),
    funding-goal: uint,
    current-funding: uint,
    status: (string-ascii 16),
    created-at: uint
  }
)

(define-map research-nfts
  { id: uint }
  {
    project-id: uint,
    owner: principal,
    title: (string-ascii 64),
    metadata: (string-ascii 256),
    price: uint,
    for-sale: bool,
    created-at: uint
  }
)

(define-map funding-proposals
  { id: uint }
  {
    project-id: uint,
    proposer: principal,
    amount: uint,
    description: (string-ascii 256),
    yes-votes: uint,
    no-votes: uint,
    status: (string-ascii 16),
    voting-end-block: uint,
    created-at: uint
  }
)

(define-map votes
  { proposal-id: uint, voter: principal }
  {
    vote: bool,
    weight: uint
  }
)

(define-map dao-members
  { address: principal }
  {
    tokens: uint,
    voting-power: uint,
    joined-at: uint
  }
)

;; Define variables
(define-data-var project-counter uint u0)
(define-data-var nft-counter uint u0)
(define-data-var proposal-counter uint u0)
(define-data-var dao-treasury uint u0)
(define-data-var total-dao-tokens uint u0)
(define-data-var proposal-threshold uint u10) ;; Minimum percentage of yes votes needed (10%)
(define-data-var voting-period uint u144) ;; Voting period in blocks (approximately 1 day)

;; Register a new research project
(define-public (register-project (title (string-ascii 64)) (description (string-ascii 256)) (funding-goal uint))
  (let
    (
      (project-id (+ (var-get project-counter) u1))
    )
    (asserts! (> funding-goal u0) (err err-invalid-amount))
    
    (map-set research-projects
      { id: project-id }
      {
        researcher: tx-sender,
        title: title,
        description: description,
        funding-goal: funding-goal,
        current-funding: u0,
        status: "active",
        created-at: stacks-block-height
      }
    )
    
    (var-set project-counter project-id)
    (ok project-id)
  )
)

;; Create an NFT for a research project
(define-public (create-nft (project-id uint) (title (string-ascii 64)) (metadata (string-ascii 256)) (price uint))
  (let
    (
      (project (unwrap! (map-get? research-projects { id: project-id }) (err err-project-not-found)))
      (nft-id (+ (var-get nft-counter) u1))
    )
    (asserts! (is-eq tx-sender (get researcher project)) (err err-not-authorized))
    (asserts! (> price u0) (err err-invalid-amount))
    
    (map-set research-nfts
      { id: nft-id }
      {
        project-id: project-id,
        owner: tx-sender,
        title: title,
        metadata: metadata,
        price: price,
        for-sale: true,
        created-at: stacks-block-height
      }
    )
    
    (var-set nft-counter nft-id)
    (ok nft-id)
  )
)

;; Buy an NFT
(define-public (buy-nft (nft-id uint))
  (let
    (
      (nft (unwrap! (map-get? research-nfts { id: nft-id }) (err err-nft-not-found)))
      (project (unwrap! (map-get? research-projects { id: (get project-id nft) }) (err err-project-not-found)))
    )
    (asserts! (not (is-eq tx-sender (get owner nft))) (err err-not-authorized))
    (asserts! (get for-sale nft) (err err-nft-not-for-sale))
    
    ;; Transfer STX from buyer to NFT owner
    (unwrap! (stx-transfer? (get price nft) tx-sender (get owner nft)) (err err-insufficient-funds))
    
    ;; Update project funding
    (map-set research-projects
      { id: (get project-id nft) }
      (merge project {
        current-funding: (+ (get current-funding project) (get price nft))
      })
    )
    
    ;; Update NFT ownership
    (map-set research-nfts
      { id: nft-id }
      (merge nft {
        owner: tx-sender,
        for-sale: false
      })
    )
    
    (ok true)
  )
)