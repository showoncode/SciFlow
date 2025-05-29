;; IP-NFT: Intellectual Property Non-Fungible Token Contract
;; This contract implements SIP-009 compliant NFTs for intellectual property registration

;; Define the NFT trait
(impl-trait 'SP2PABAF9FTAJYNFZH93XENAJ8FVY99RRM50D2JG9.nft-trait.nft-trait)

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_OWNER_ONLY (err u100))
(define-constant ERR_NOT_TOKEN_OWNER (err u101))
(define-constant ERR_NOT_AUTHORIZED (err u102))
(define-constant ERR_TOKEN_NOT_FOUND (err u103))
(define-constant ERR_INVALID_METADATA (err u104))
(define-constant ERR_ALREADY_MINTED (err u105))
(define-constant ERR_TRANSFER_FAILED (err u106))

;; Data Variables
(define-data-var last-token-id uint u0)
(define-data-var contract-uri (string-utf8 256) u"https://ipnft.research.org/metadata/")

;; Maps
;; Token ownership mapping
(define-map token-owner uint principal)

;; Token approval mapping (owner -> spender -> token-id -> approved)
(define-map token-approvals {owner: principal, spender: principal, token-id: uint} bool)

;; Operator approval mapping (owner -> operator -> approved)
(define-map operator-approvals {owner: principal, operator: principal} bool)

;; Intellectual Property metadata mapping
(define-map ip-metadata uint {
    title: (string-utf8 256),
    abstract-hash: (string-ascii 64),
    doi: (optional (string-ascii 128)),
    ip-type: (string-ascii 32), ;; "research-paper", "dataset", "thesis"
    timestamp: uint,
    author: principal,
    institution: (optional (string-utf8 128)),
    keywords: (list 10 (string-utf8 64)),
    license-type: (string-ascii 64),
    peer-reviewed: bool
})

;; Hash to token-id mapping to prevent duplicate minting
(define-map hash-to-token (string-ascii 64) uint)

;; Author statistics
(define-map author-stats principal {
    total-minted: uint,
    papers: uint,
    datasets: uint,
    theses: uint
})

;; SIP-009 Required Functions

;; Get last token ID
(define-read-only (get-last-token-id)
    (ok (var-get last-token-id))
)

;; Get token URI
(define-read-only (get-token-uri (token-id uint))
    (ok (some (concat (var-get contract-uri) (uint-to-ascii token-id))))
)

;; Get token owner
(define-read-only (get-owner (token-id uint))
    (ok (map-get? token-owner token-id))
)

;; Transfer function
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
    (let ((owner (unwrap! (map-get? token-owner token-id) ERR_TOKEN_NOT_FOUND)))
        (asserts! (or (is-eq tx-sender sender) (is-eq tx-sender owner)) ERR_NOT_AUTHORIZED)
        (asserts! (is-eq owner sender) ERR_NOT_TOKEN_OWNER)
        (map-set token-owner token-id recipient)
        (map-delete token-approvals {owner: sender, spender: tx-sender, token-id: token-id})
        (print {type: "transfer", token-id: token-id, sender: sender, recipient: recipient})
        (ok true)
    )
)

;; Core IP NFT Functions

;; Mint new IP NFT
(define-public (mint-ip-nft 
    (recipient principal)
    (title (string-utf8 256))
    (abstract-hash (string-ascii 64))
    (doi (optional (string-ascii 128)))
    (ip-type (string-ascii 32))
    (institution (optional (string-utf8 128)))
    (keywords (list 10 (string-utf8 64)))
    (license-type (string-ascii 64))
    (peer-reviewed bool)
)
    (let ((token-id (+ (var-get last-token-id) u1)))
        ;; Validate inputs
        (asserts! (> (len title) u0) ERR_INVALID_METADATA)
        (asserts! (is-eq (len abstract-hash) u64) ERR_INVALID_METADATA)
        (asserts! (is-none (map-get? hash-to-token abstract-hash)) ERR_ALREADY_MINTED)
        
        ;; Set token ownership and metadata
        (map-set token-owner token-id recipient)
        (map-set hash-to-token abstract-hash token-id)
        (map-set ip-metadata token-id {
            title: title,
            abstract-hash: abstract-hash,
            doi: doi,
            ip-type: ip-type,
            timestamp: block-height,
            author: tx-sender,
            institution: institution,
            keywords: keywords,
            license-type: license-type,
            peer-reviewed: peer-reviewed
        })
        
        ;; Update author statistics
        (update-author-stats tx-sender ip-type)
        
        ;; Update last token ID
        (var-set last-token-id token-id)
        
        ;; Emit mint event
        (print {
            type: "mint",
            token-id: token-id,
            recipient: recipient,
            author: tx-sender,
            title: title,
            ip-type: ip-type,
            timestamp: block-height
        })
        
        (ok token-id)
    )
)

;; Batch mint multiple IP NFTs
(define-public (batch-mint-ip-nfts 
    (mint-requests (list 10 {
        recipient: principal,
        title: (string-utf8 256),
        abstract-hash: (string-ascii 64),
        doi: (optional (string-ascii 128)),
        ip-type: (string-ascii 32),
        institution: (optional (string-utf8 128)),
        keywords: (list 10 (string-utf8 64)),
        license-type: (string-ascii 64),
        peer-reviewed: bool
    }))
)
    (fold batch-mint-helper mint-requests (ok (list)))
)

;; Helper function for batch minting
(define-private (batch-mint-helper 
    (request {
        recipient: principal,
        title: (string-utf8 256),
        abstract-hash: (string-ascii 64),
        doi: (optional (string-ascii 128)),
        ip-type: (string-ascii 32),
        institution: (optional (string-utf8 128)),
        keywords: (list 10 (string-utf8 64)),
        license-type: (string-ascii 64),
        peer-reviewed: bool
    })
    (prev-result (response (list 10 uint) uint))
)
    (match prev-result
        success-list (match (mint-ip-nft 
            (get recipient request)
            (get title request)
            (get abstract-hash request)
            (get doi request)
            (get ip-type request)
            (get institution request)
            (get keywords request)
            (get license-type request)
            (get peer-reviewed request)
        )
            token-id (ok (unwrap-panic (as-max-len? (append success-list token-id) u10)))
            error (err error)
        )
        error (err error)
    )
)

;; Update author statistics
(define-private (update-author-stats (author principal) (ip-type (string-ascii 32)))
    (let ((current-stats (default-to {total-minted: u0, papers: u0, datasets: u0, theses: u0} 
                                   (map-get? author-stats author))))
        (map-set author-stats author {
            total-minted: (+ (get total-minted current-stats) u1),
            papers: (+ (get papers current-stats) (if (is-eq ip-type "research-paper") u1 u0)),
            datasets: (+ (get datasets current-stats) (if (is-eq ip-type "dataset") u1 u0)),
            theses: (+ (get theses current-stats) (if (is-eq ip-type "thesis") u1 u0))
        })
    )
)

;; Approval Functions

;; Approve specific token for transfer
(define-public (approve (spender principal) (token-id uint))
    (let ((owner (unwrap! (map-get? token-owner token-id) ERR_TOKEN_NOT_FOUND)))
        (asserts! (is-eq tx-sender owner) ERR_NOT_TOKEN_OWNER)
        (map-set token-approvals {owner: owner, spender: spender, token-id: token-id} true)
        (print {type: "approve", owner: owner, spender: spender, token-id: token-id})
        (ok true)
    )
)

;; Set approval for all tokens
(define-public (set-approval-for-all (operator principal) (approved bool))
    (begin
        (map-set operator-approvals {owner: tx-sender, operator: operator} approved)
        (print {type: "approval-for-all", owner: tx-sender, operator: operator, approved: approved})
        (ok true)
    )
)

;; Check if spender is approved for token
(define-read-only (is-approved-for-all (owner principal) (operator principal))
    (default-to false (map-get? operator-approvals {owner: owner, operator: operator}))
)

;; Get approved spender for token
(define-read-only (get-approved (token-id uint))
    (map-get? token-approvals {owner: (unwrap! (map-get? token-owner token-id) ERR_TOKEN_NOT_FOUND), 
                              spender: tx-sender, 
                              token-id: token-id})
)

;; Read-only Functions

;; Get IP metadata
(define-read-only (get-ip-metadata (token-id uint))
    (map-get? ip-metadata token-id)
)

;; Get token by hash
(define-read-only (get-token-by-hash (abstract-hash (string-ascii 64)))
    (map-get? hash-to-token abstract-hash)
)

;; Get author statistics
(define-read-only (get-author-stats (author principal))
    (map-get? author-stats author)
)

;; Search functions
(define-read-only (get-tokens-by-author (author principal))
    ;; This would require additional mapping in a production system
    ;; For now, returns author stats as a reference
    (map-get? author-stats author)
)

;; Verify IP ownership
(define-read-only (verify-ip-ownership (token-id uint) (claimed-owner principal))
    (match (map-get? token-owner token-id)
        owner (is-eq owner claimed-owner)
        false
    )
)

;; Administrative Functions

;; Update contract URI (only owner)
(define-public (set-contract-uri (new-uri (string-utf8 256)))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
        (var-set contract-uri new-uri)
        (ok true)
    )
)

;; Get contract info
(define-read-only (get-contract-info)
    {
        name: "IP-NFT",
        symbol: "IPNFT",
        decimals: u0,
        total-supply: (var-get last-token-id),
        contract-uri: (var-get contract-uri),
        owner: CONTRACT_OWNER
    }
)

;; Utility Functions

;; Convert uint to ASCII string (helper for URI generation)
(define-read-only (uint-to-ascii (value uint))
    (if (is-eq value u0)
        "0"
        (uint-to-ascii-helper value "")
    )
)

(define-private (uint-to-ascii-helper (value uint) (result (string-ascii 10)))
    (if (is-eq value u0)
        result
        (uint-to-ascii-helper 
            (/ value u10) 
            (unwrap-panic (as-max-len? (concat (unwrap-panic (element-at "0123456789" (mod value u10))) result) u10))
        )
    )
)