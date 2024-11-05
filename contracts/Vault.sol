// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;


import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

// Trivial vault that allows users to deposit ERC20 tokens then claim them later.
contract Permit2Vault is EIP712("Permit2", "")  {
    using ECDSA for bytes32;
    bool private _reentrancyGuard;
    // The canonical permit2 contract.
    IPermit2 public immutable PERMIT2;
    // User -> token -> deposit balance
    mapping (address => mapping (IERC20 => uint256)) public tokenBalancesByUser;

    bytes32 public constant TOKEN_PERMISSIONS_TYPEHASH =
        keccak256("TokenPermissions(address token,uint256 amount)");
    bytes32 public constant TRANSFER_FROM_TYPEHASH =
        keccak256(
            "PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
        );

    constructor(IPermit2 permit_) {
        PERMIT2 = permit_;
    }
    
    // Prevents reentrancy attacks via tokens with callback mechanisms. 
    modifier nonReentrant() {
        require(!_reentrancyGuard, 'no reentrancy');
        _reentrancyGuard = true;
        _;
        _reentrancyGuard = false;
    }

    // Deposit some amount of an ERC20 token from the caller
    // into this contract using Permit2.
    function depositERC20(
        IERC20 token,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external nonReentrant {

        bytes32 structHash = keccak256(abi.encode(
            TRANSFER_FROM_TYPEHASH,
            keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, token, amount)),
            address(this),
            nonce,
            deadline
        ));
        bytes32 digest = _hashTypedDataV4(structHash);
        address user = ECDSA.recover(digest, signature);
        // Credit the caller.
        console.log("user is : %s", user);
        // Ensure the recovered address matches msg.sender
        require(user == msg.sender, "Invalid signer"); //keeps failing here
        tokenBalancesByUser[user][token] += amount;
        // Transfer tokens from the caller to ourselves.
        PERMIT2.permitTransferFrom(
            // The permit message. Spender will be inferred as the caller (us).
            IPermit2.PermitTransferFrom({
                permitted: IPermit2.TokenPermissions({
                    token: token,
                    amount: amount
                }),
                nonce: nonce,
                deadline: deadline
            }),
            // The transfer recipient and amount.
            IPermit2.SignatureTransferDetails({
                to: address(this),
                requestedAmount: amount
            }),
            // The owner of the tokens, which must also be
            // the signer of the message, otherwise this call
            // will fail.
            user,
            // The packed signature that was the result of signing
            // the EIP712 hash of `permit`.
            signature
        );
        console.log("Deposit successful");
        console.log("Msg.sender:", msg.sender);
        console.log("User is: ", user);
        console.log("Amount:", amount);
    }

    
}

// Minimal Permit2 interface, derived from
// https://github.com/Uniswap/permit2/blob/main/src/interfaces/ISignatureTransfer.sol
interface IPermit2 {
    // Token and amount in a permit message.
    struct TokenPermissions {
        // Token to transfer.
        IERC20 token;
        // Amount to transfer.
        uint256 amount;
    }

    // The permit2 message.
    struct PermitTransferFrom {
        // Permitted token and maximum amount.
        TokenPermissions permitted;// deadline on the permit signature
        // Unique identifier for this permit.
        uint256 nonce;
        // Expiration for this permit.
        uint256 deadline;
    }

    // The permit2 message for batch transfers.
    struct PermitBatchTransferFrom {
        // Permitted tokens and maximum amounts.
        TokenPermissions[] permitted;
        // Unique identifier for this permit.
        uint256 nonce;
        // Expiration for this permit.
        uint256 deadline;
    }

    // Transfer details for permitTransferFrom().
    struct SignatureTransferDetails {
        // Recipient of tokens.
        address to;
        // Amount to transfer.
        uint256 requestedAmount;
    }

    // Consume a permit2 message and transfer tokens.
    function permitTransferFrom(
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes calldata signature
    ) external;

    // Consume a batch permit2 message and transfer tokens.
    function permitTransferFrom(
        PermitBatchTransferFrom calldata permit,
        SignatureTransferDetails[] calldata transferDetails,
        address owner,
        bytes calldata signature
    ) external;
}

// Minimal ERC20 interface.
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
}
