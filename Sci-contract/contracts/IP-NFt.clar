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
(define-constant ERR_INVALID_TOKEN_ID (err u107))
(define-constant ERR_APPROVAL_NOT_FOUND (err u108))

;; Data Variables
;; Data Variables - Use string-ascii for consistency
(define-data-var last-token-id uint u0)
(define-data-var contract-uri (string-utf8 256) u"https://ipnft.research.org/metadata/")

;; Define the NFT
(define-non-fungible-token ip-nft uint)

;; Maps
;; Token approval mapping - FIXED: Simplified structure
(define-map token-approvals uint principal)

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

;; ;; Get token URI - FIXED: Better error handling with working uint conversion
;; (define-read-only (get-token-uri (token-id uint))
;;     (if (and (> token-id u0) (<= token-id (var-get last-token-id)))
;;         (ok (some (concat (var-get contract-uri) (int-to-ascii (to-int token-id)))))
;;         (ok none)
;;     )
;; )

;; Get token URI - Clean implementation with matching types
(define-read-only (get-token-uri (token-id uint))
    (if (and (> token-id u0) (<= token-id (var-get last-token-id)))
        (ok (some (concat (var-get contract-uri) (int-to-utf8 (to-int token-id)))))
        (ok none)
    )
)

;; Administrative function - Update to match string-ascii
(define-public (set-contract-uri (new-uri (string-utf8 256)))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
        (var-set contract-uri new-uri)
        (ok true)
    )
)

;; Get token owner - FIXED: Use built-in NFT function
(define-read-only (get-owner (token-id uint))
    (ok (nft-get-owner? ip-nft token-id))
)

;; Transfer function - FIXED: Inline approval check to avoid function order issues
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
    (begin
        ;; Validate token exists
        (asserts! (and (> token-id u0) (<= token-id (var-get last-token-id))) ERR_INVALID_TOKEN_ID)
        
        ;; Check ownership and authorization
        (asserts! (is-eq (some sender) (nft-get-owner? ip-nft token-id)) ERR_NOT_TOKEN_OWNER)
        
        ;; Check if tx-sender is authorized to transfer
        (asserts! (or 
            ;; Sender is the tx-sender (owner transferring their own token)
            (is-eq tx-sender sender)
            ;; tx-sender is approved for this specific token
            (is-eq (some tx-sender) (map-get? token-approvals token-id))
            ;; tx-sender is approved as operator for all tokens of this owner
            (default-to false (map-get? operator-approvals {owner: sender, operator: tx-sender}))
        ) ERR_NOT_AUTHORIZED)
        
        ;; Clear any existing approval for this token
        (map-delete token-approvals token-id)
        
        ;; Transfer the NFT using built-in function
        (match (nft-transfer? ip-nft token-id sender recipient)
            success (begin
                (print {type: "transfer", token-id: token-id, sender: sender, recipient: recipient})
                (ok true)
            )
            error ERR_TRANSFER_FAILED
        )
    )
)

;; Core IP NFT Functions

;; Mint new IP NFT - FIXED: Inline author stats update
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
        
        ;; Mint the NFT
        (match (nft-mint? ip-nft token-id recipient)
            success (begin
                ;; Set metadata mappings
                (map-set hash-to-token abstract-hash token-id)
                (map-set ip-metadata token-id {
                    title: title,
                    abstract-hash: abstract-hash,
                    doi: doi,
                    ip-type: ip-type,
                    timestamp: stacks-block-height,
                    author: tx-sender,
                    institution: institution,
                    keywords: keywords,
                    license-type: license-type,
                    peer-reviewed: peer-reviewed
                })
                
                ;; Update author statistics inline
                (let ((current-stats (default-to {total-minted: u0, papers: u0, datasets: u0, theses: u0} 
                                               (map-get? author-stats tx-sender))))
                    (map-set author-stats tx-sender {
                        total-minted: (+ (get total-minted current-stats) u1),
                        papers: (+ (get papers current-stats) (if (is-eq ip-type "research-paper") u1 u0)),
                        datasets: (+ (get datasets current-stats) (if (is-eq ip-type "dataset") u1 u0)),
                        theses: (+ (get theses current-stats) (if (is-eq ip-type "thesis") u1 u0))
                    })
                )
                
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
                    timestamp: stacks-block-height
                })
                
                (ok token-id)
            )
            error ERR_TRANSFER_FAILED
        )
    )
)

;; ;; Batch mint multiple IP NFTs - FIXED: Better error handling
;; (define-public (batch-mint-ip-nfts 
;;     (mint-requests (list 10 {
;;         recipient: principal,
;;         title: (string-utf8 256),
;;         abstract-hash: (string-ascii 64),
;;         doi: (optional (string-ascii 128)),
;;         ip-type: (string-ascii 32),
;;         institution: (optional (string-utf8 128)),
;;         keywords: (list 10 (string-utf8 64)),
;;         license-type: (string-ascii 64),
;;         peer-reviewed: bool
;;     }))
;; )
;;     (fold batch-mint-helper mint-requests (ok (list)))
;; )

;; Helper to process individual mint request
(define-private (process-mint-request 
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
)
    (mint-ip-nft 
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
)

;; Simplified batch mint - processes all requests and returns results
(define-public (batch-mint-ip-nfts-simple
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
    (let ((results (map process-mint-request mint-requests)))
        (ok results)
    )
)



;; Helper function for batch minting - FIXED: Better error propagation
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

;; Approval Functions - FIXED: Simplified and corrected

;; Approve specific token for transfer
(define-public (approve (spender principal) (token-id uint))
    (let ((owner (unwrap! (nft-get-owner? ip-nft token-id) ERR_TOKEN_NOT_FOUND)))
        (asserts! (is-eq tx-sender owner) ERR_NOT_TOKEN_OWNER)
        (map-set token-approvals token-id spender)
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

;; Check if spender is approved for all tokens
(define-read-only (is-approved-for-all (owner principal) (operator principal))
    (default-to false (map-get? operator-approvals {owner: owner, operator: operator}))
)

;; Get approved spender for token - FIXED: Simplified
(define-read-only (get-approved (token-id uint))
    (ok (map-get? token-approvals token-id))
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

;; Verify IP ownership - FIXED: Use built-in NFT function
(define-read-only (verify-ip-ownership (token-id uint) (claimed-owner principal))
    (is-eq (some claimed-owner) (nft-get-owner? ip-nft token-id))
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

;; Recommended: Use built-in int-to-ascii
(define-read-only (uint-to-string (value uint))
    (int-to-ascii (to-int value))
)

;; Remove the problematic uint-to-ascii-custom function entirely
;; and update get-token-uri to use the built-in approach:


;; Burn function - ADDED: Allow burning of NFTs
(define-public (burn (token-id uint))
    (let ((owner (unwrap! (nft-get-owner? ip-nft token-id) ERR_TOKEN_NOT_FOUND)))
        (asserts! (is-eq tx-sender owner) ERR_NOT_TOKEN_OWNER)
        (match (nft-burn? ip-nft token-id owner)
            success (begin
                ;; Clean up mappings
                (match (get-ip-metadata token-id)
                    metadata (map-delete hash-to-token (get abstract-hash metadata))
                    true
                )
                (map-delete ip-metadata token-id)
                (map-delete token-approvals token-id)
                (print {type: "burn", token-id: token-id, owner: owner})
                (ok true)
            )
            error ERR_TRANSFER_FAILED
        )
    )
)
