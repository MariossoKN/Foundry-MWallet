// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

/**
 * @dev MWallet is a multi owner ethereum wallet contract. This contract allows to send or withdraw ETH from the contract only if at least 50% or more of
 * owners of the wallet approved this. Its advised to have atleast 3 owner addresses, so in case one of them is hacked, the balance of the contract can be safely
 * transfered out by the remaining two owner addresses (with the createSendingTransaction function (!!! not createWithdrawTransaction because the withdraw function
 * splits the withdrawed amount between all the current owners!!!)).
 * @dev any owner addres can create two possible transactions:
 * 1. transaction to transfer ETH from the contract. This requires two parameters - a address to where the ETH will be sended and an amount of ETH sended.
 * 2. transaction to withdraw ETH from the contract.
 * In both cases the other owners have to approve the transaction in orded to be able to execute them. !!!Keep in mind, if there is only two owners and one of the owners
 * gets hacked, the hacker can freely create and execute transactions.!!!
 */

contract MWallet {
    error Wallet__TransactionAlreadyExecuted();
    error Wallet__CanOnlyBeCalledByOwner();
    error Wallet__NotEnoughApprovals(uint256);
    error Wallet__NotEnoughEthInTheWallet(uint256);
    error Wallet__DuplicateAddresses(address duplicateAddress);
    error Wallet__WalletAddresseCantBeZeroAddress();
    error Wallet__AlreadyApproved();
    error Wallet__DidntApproved();

    event TransactionCreated(
        bool withdrawTransaction,
        uint256 transactionAmount,
        address transactionTo
    );
    event Approved(address approver, uint256 transactionId);
    event ApprovalRemoved(
        address approvalRemovedAddress,
        uint256 transactionId
    );
    event TransactionExecuted(
        address transactionExecutedBy,
        uint256 transactionId
    );
    event Withdrawed(uint256 balanceWithdrawed);
    event OwnerAddressChanged(address oldWallet, address newWallet);

    struct Transaction {
        bool isWithdraw;
        uint256 amounSentInWei;
        address addressToSent;
        uint32 approvals;
        bool transactionExecuted;
    }

    address[] public owners;
    Transaction[] public transactions;
    mapping(address => mapping(uint256 => bool)) approvals;

    /**
     * @param  _owners array of wallet owners. Only owners can create, approve and execute transactions. Function checks for duplicates and for zero addresses.
     */
    constructor(address[] memory _owners) {
        for (uint256 i = 0; i < _owners.length; i++) {
            if (_owners[i] == address(0)) {
                revert Wallet__WalletAddresseCantBeZeroAddress();
            }
            for (uint256 j = i + 1; j < _owners.length; j++) {
                if (_owners[i] == _owners[j]) {
                    revert Wallet__DuplicateAddresses(_owners[i]);
                }
            }
            owners.push(_owners[i]);
        }
    }

    // [0x5B38Da6a701c568545dCfcB03FcB875f56beddC4,0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2,0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db]
    // 1000000000000000000 (1ETH)

    /**
     * @dev lets the caller to check if the provided address is an owner address or not
     * @param  _callerAddress address to check if its and owner address
     */
    function isOwner(address _callerAddress) public view returns (bool) {
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == _callerAddress) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev lets one of the owners to create a transaction to transfer ETH from the contract. Can only be called by the owners. Function checks for zero address.
     * @param  _amountSentInWei amount of ETH which will be trasnfered
     * @param  _addressTo address where the ETH will be trasnfered
     */
    function createSendingTransaction(
        uint256 _amountSentInWei,
        address _addressTo
    ) external returns (uint256) {
        if (isOwner(msg.sender) != true) {
            revert Wallet__CanOnlyBeCalledByOwner();
        }
        if (_addressTo == address(0)) {
            revert Wallet__WalletAddresseCantBeZeroAddress();
        }
        // if this is a first transaction created
        if (transactions.length == 0) {
            transactions.push(
                Transaction(
                    false,
                    _amountSentInWei,
                    payable(_addressTo),
                    1,
                    false
                )
            );
            approvals[msg.sender][transactions.length - 1] = true;
        } else {
            approvals[msg.sender][transactions.length] = true;
            transactions.push(
                Transaction(
                    false,
                    _amountSentInWei,
                    payable(_addressTo),
                    1,
                    false
                )
            );
        }
        emit TransactionCreated(false, _amountSentInWei, _addressTo);
        return transactions.length - 1;
    }

    /**
     * @dev lets one of the owners to create a transaction to withdraw ETH from the contract which will be then split between owners
     */
    function createWithdrawTransaction() external returns (uint256) {
        if (isOwner(msg.sender) != true) {
            revert Wallet__CanOnlyBeCalledByOwner();
        }
        if (transactions.length == 0) {
            transactions.push(Transaction(true, 0, address(0), 1, false));
            approvals[msg.sender][transactions.length - 1] = true;
        } else {
            approvals[msg.sender][transactions.length] = true;
            transactions.push(Transaction(true, 0, address(0), 1, false));
        }
        emit TransactionCreated(true, 0, address(0));
        return transactions.length - 1;
    }

    /**
     * @dev lets the owner to change his own address to a new address
     * @param _newAddress a new address to which will be the old address changed. Cant be an address which is already an owner
     */
    function changeOwnerAddress(address _newAddress) external returns (bool) {
        if (isOwner(msg.sender) != true) {
            revert Wallet__CanOnlyBeCalledByOwner();
        }
        for (uint256 j = 0; j < owners.length; j++) {
            if (owners[j] == _newAddress) {
                revert Wallet__DuplicateAddresses(owners[j]);
            }
        }
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == msg.sender) {
                owners[i] = _newAddress;
                emit OwnerAddressChanged(msg.sender, _newAddress);
                return true;
            }
        }
        return false;
    }

    /**
     * @dev lets the owner to approve an existing transaction in orded to be able to execute it - either a send transaction or withdraw
     * @param _transactionId id of the transaction which will be approved
     */
    function approve(uint256 _transactionId) external {
        if (isOwner(msg.sender) != true) {
            revert Wallet__CanOnlyBeCalledByOwner();
        }
        if (approvals[msg.sender][_transactionId] == true) {
            revert Wallet__AlreadyApproved();
        } else {
            approvals[msg.sender][_transactionId] = true;
            transactions[_transactionId].approvals++;
        }
        emit Approved(msg.sender, _transactionId);
    }

    /**
     * @dev lets the owner to remove approval of an existing transaction
     * @param _transactionId id of the transaction where the approval will be removed
     */
    function removeApproval(uint256 _transactionId) external {
        if (isOwner(msg.sender) != true) {
            revert Wallet__CanOnlyBeCalledByOwner();
        }
        if (approvals[msg.sender][_transactionId] == false) {
            revert Wallet__DidntApproved();
        } else {
            approvals[msg.sender][_transactionId] = false;
            transactions[_transactionId].approvals--;
        }
        emit ApprovalRemoved(msg.sender, _transactionId);
    }

    /**
     * @dev lets any the owners to execute the transacation - either a send transaction or withdraw.
     * @param _transactionId id of the transaction where the approval will be removed
     */
    function executeTransaction(uint256 _transactionId) external payable {
        if (isOwner(msg.sender) != true) {
            revert Wallet__CanOnlyBeCalledByOwner();
        }
        Transaction[] memory transaction = transactions;
        uint256 currentApprovals = transaction[_transactionId].approvals;
        if (currentApprovals * 10 < ((owners.length * 10) / 2)) {
            revert Wallet__NotEnoughApprovals(currentApprovals);
        }
        uint256 contractEthBalance = address(this).balance;
        if (transaction[_transactionId].isWithdraw == false) {
            if ((transaction[_transactionId]).transactionExecuted == true)
                revert Wallet__TransactionAlreadyExecuted();
            uint256 amountTo = transaction[_transactionId].amounSentInWei;
            address addressTo = transaction[_transactionId].addressToSent;
            if (amountTo > contractEthBalance)
                revert Wallet__NotEnoughEthInTheWallet(contractEthBalance);
            transactions[_transactionId].transactionExecuted = true;
            sendEth(amountTo, addressTo);
        } else {
            withdraw(contractEthBalance);
            emit Withdrawed(contractEthBalance);
        }
        emit TransactionExecuted(msg.sender, _transactionId);
    }

    /**
     * @dev internal function to send ETH from the wallet
     * @param _amountTo amount of ETH sent
     * @param _addressTo address where the ETH will be sent to
     */
    function sendEth(uint256 _amountTo, address _addressTo) internal {
        (bool callSuccess, ) = payable(_addressTo).call{value: _amountTo}("");
        require(callSuccess, "Send failed");
    }

    /**
     * @dev internal function to withdraw ETH from the wallet - contract balance will be split between current owners
     * @param _contractBalance balance of the wallet contract.
     */
    function withdraw(uint256 _contractBalance) internal {
        uint256 ownersAmount = owners.length;
        uint256 contractBalanceDividedBetweenOwners = _contractBalance /
            ownersAmount;
        for (uint256 i = 0; i < ownersAmount; i++) {
            (bool callSuccess, ) = payable(owners[i]).call{
                value: contractBalanceDividedBetweenOwners
            }("");
            require(callSuccess, "Withdraw failed");
        }
    }

    /**
     * @dev allows the caller to send ETH to the wallet contract
     */
    function sendEthToWallet() external payable {
        (bool callSuccess, ) = payable(address(this)).call{value: msg.value}(
            ""
        );
        require(callSuccess, "Call failed");
    }

    /**
     * @dev allows the caller to check if the provided address approved the provided transaction
     * @param _address address to check if approved the provided transaction
     * @param _transactionId id of the transaction to check if the provided address approved
     */
    function checkIfApproved(
        address _address,
        uint256 _transactionId
    ) external view returns (bool) {
        return approvals[_address][_transactionId];
    }

    /**
     * @dev allows the caller to check the transaction information
     * @param _transactionId id of the transaction to check
     */
    function checkTransactionInformation(
        uint256 _transactionId
    ) external view returns (Transaction memory) {
        return (transactions[_transactionId]);
    }

    /**
     * @dev allows the caller to check the balance of the wallet contract
     */
    function checkWalletBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev allows the caller to check how many transaction exists
     */
    function checkAmountOfTransactions() external view returns (uint256) {
        return transactions.length;
    }

    /**
     * @dev allows the wallet contract to recieve ETH
     */
    receive() external payable {}
}
