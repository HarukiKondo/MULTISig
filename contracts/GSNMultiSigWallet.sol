pragma solidity 0.5.13;

import "@openzeppelin/contracts-ethereum-package/contracts/GSN/GSNRecipient.sol";

/// @title Multisignature wallet - Allows multiple parons bties to agree on transactiefore execution.
/// @author Stefan George - <stefan.george@consensys.net>
// マルチシグのコントラクト GSNRecipientコントラクトを継承
contract GSNMultiSigWallet is GSNRecipient {

    /*
     *  各種イベントを設定
     */
    event Confirmation(address indexed sender, uint indexed transactionId);
    event Revocation(address indexed sender, uint indexed transactionId);
    event Submission(uint indexed transactionId);
    event Execution(uint indexed transactionId);
    event ExecutionFailure(uint indexed transactionId);
    event Deposit(address indexed sender, uint value);
    event OwnerAddition(address indexed owner);
    event OwnerRemoval(address indexed owner);
    event RequirementChange(uint required);

    /*
     *  Constants
     *  コントラクト作成者の最大値
     */
    uint constant public MAX_OWNER_COUNT = 50;

    /*
     *  各種ストレージ変数を生成
     */
    // トランザクションデータを紐づけるためのマップ変数
    mapping (uint => Transaction) public transactions;
    mapping (uint => mapping (address => bool)) public confirmations;
    // コントラクト作成者であるかどうかを紐づけるマップ変数
    mapping (address => bool) public isOwner;
    // コントラクト作成者アドレスリスト
    address[] public owners;
    uint public required;
    uint public transactionCount;
    // 構造体 Transacitonを定義
    struct Transaction {
        // 送信先アドレス
        address destination;
        // 送金額
        uint value;
        bytes data;
        // 実行済みかどうか
        bool executed;
    }

    /*
     *  Modifiers
     *  各関数修飾子を定義する。(関数の呼び出し時に実行するため。)
     */
    modifier onlyWallet() {
        // コントラクト自身であること
        require(_msgSender() == address(this));
        _;
    }

    modifier ownerDoesNotExist(address owner) {
        require(!isOwner[owner]);
        _;
    }

    modifier ownerExists(address owner) {
        require(isOwner[owner]);
        _;
    }

    modifier transactionExists(uint transactionId) {
        require(transactions[transactionId].destination != address(0));
        _;
    }

    modifier confirmed(uint transactionId, address owner) {
        require(confirmations[transactionId][owner]);
        _;
    }

    modifier notConfirmed(uint transactionId, address owner) {
        require(!confirmations[transactionId][owner]);
        _;
    }

    modifier notExecuted(uint transactionId) {
        require(!transactions[transactionId].executed);
        _;
    }

    modifier notNull(address _address) {
        require(_address != address(0));
        _;
    }

    modifier validRequirement(uint ownerCount, uint _required) {
        // 要求された署名数の条件を満たしているかチェックする。
        require(ownerCount <= MAX_OWNER_COUNT && _required <= ownerCount && _required != 0 && ownerCount != 0);
        _;
    }

    /// @dev Fallback function allows to deposit ether.
    // フォールバック関数
    function() external payable {
        // 0ETH以上所有していることの確認
        if (msg.value > 0)
            // msg.sender safe to use instead of _msgSender()
            // because fallback never called by RelayHub directly
            // イベントの呼び出し
            emit Deposit(msg.sender, msg.value);
    }

    /*
     * Public functions
     */
    /// @dev Contract constructor sets initial owners and required number of confirmations.
    /// @param _owners List of initial owners.
    /// @param _required Number of required confirmations.
    // 初期化関数
    function initialize(address[] memory _owners, uint _required) public initializer validRequirement(_owners.length, _required) {
        // 初期化する。
        GSNRecipient.initialize();

        for (uint i=0; i<_owners.length; i++) {
            require(!isOwner[_owners[i]] && _owners[i] != address(0));
            // コントラクト所有者とする。
            isOwner[_owners[i]] = true;
        }
        owners = _owners;
        required = _required;
    }

    /// @dev Allows to add a new owner. Transaction has to be sent by wallet.
    /// @param owner Address of new owner.
    // ウォレット管理者を増やす。
    function addOwner(address owner) public onlyWallet ownerDoesNotExist(owner) notNull(owner) validRequirement(owners.length + 1, required) {
        isOwner[owner] = true;
        owners.push(owner);
        emit OwnerAddition(owner);
    }

    /// @dev Allows to remove an owner. Transaction has to be sent by wallet.
    /// @param owner Address of owner.
    //　ウォレット管理者を削除する。
    function removeOwner(address owner) public onlyWallet ownerExists(owner) {
        isOwner[owner] = false;
        for (uint i=0; i<owners.length - 1; i++)
            if (owners[i] == owner) {
                owners[i] = owners[owners.length - 1];
                break;
            }
        owners.length -= 1;
        if (required > owners.length)
            // 署名に必要な人数を変更する。
            changeRequirement(owners.length);
        // イベントの呼び出し
        emit OwnerRemoval(owner);
    }

    /// @dev Allows to replace an owner with a new owner. Transaction has to be sent by wallet.
    // コントラクト所有者を更新する。
    /// @param owner Address of owner to be replaced.
    /// @param newOwner Address of new owner.
    function replaceOwner(address owner, address newOwner) public onlyWallet ownerExists(owner) ownerDoesNotExist(newOwner) {
        for (uint i=0; i<owners.length; i++)
            if (owners[i] == owner) {
                owners[i] = newOwner;
                break;
            }
        isOwner[owner] = false;
        isOwner[newOwner] = true;
        emit OwnerRemoval(owner);
        emit OwnerAddition(newOwner);
    }

    // 署名に必要な人数を変更する。
    /// @dev Allows to change the number of required confirmations. Transaction has to be sent by wallet.
    /// @param _required Number of required confirmations.
    function changeRequirement(uint _required) public onlyWallet validRequirement(owners.length, _required) {
        required = _required;
        emit RequirementChange(_required);
    }

    /// @dev Allows an owner to submit and confirm a transaction.
    /// @param destination Transaction target address.
    /// @param value Transaction ether value.
    /// @param data Transaction data payload.
    /// @return Returns transaction ID.
    function submitTransaction(address destination, uint value, bytes memory data) public returns (uint transactionId){
        transactionId = addTransaction(destination, value, data);
        confirmTransaction(transactionId);
    }

    /// @dev Allows an owner to confirm a transaction.
    /// @param transactionId Transaction ID.
    function confirmTransaction(uint transactionId) public ownerExists(_msgSender()) transactionExists(transactionId) notConfirmed(transactionId, _msgSender()) {
        // トランザクションを確認済みにする
        confirmations[transactionId][_msgSender()] = true;
        // イベントの呼び出し
        emit Confirmation(_msgSender(), transactionId);
        // トランザクション実行
        executeTransaction(transactionId);
    }

    /// @dev Allows an owner to revoke a confirmation for a transaction.
    /// @param transactionId Transaction ID.
    // トランザクジョンの確認を取り消す関数
    function revokeConfirmation(uint transactionId) public ownerExists(_msgSender()) confirmed(transactionId, _msgSender()) notExecuted(transactionId) {
        // 確認を取り消す。
        confirmations[transactionId][_msgSender()] = false;
        emit Revocation(_msgSender(), transactionId);
    }

    /// @dev Allows anyone to execute a confirmed transaction.
    /// @param transactionId Transaction ID.
    // トランザクション実行関数
    function executeTransaction(uint transactionId) public ownerExists(_msgSender()) confirmed(transactionId, _msgSender()) notExecuted(transactionId) {
        // 確認されているかチェックする。
        if (isConfirmed(transactionId)) {
            // IDからトランザクションデータを取得する。
            Transaction storage txn = transactions[transactionId];
            // 実行済みフラグをONにする。
            txn.executed = true;
            if (external_call(txn.destination, txn.value, txn.data.length, txn.data))
                emit Execution(transactionId);
            else {
                emit ExecutionFailure(transactionId);
                txn.executed = false;
            }
        }
    }

    // call has been separated into its own function in order to take advantage
    // of the Solidity's code generator to produce a loop that copies tx.data into memory.
    // 外部呼出し関数
    function external_call(address destination, uint value, uint dataLength, bytes memory data) internal returns (bool) {
        // 戻り値用の変数を宣言
        bool result;
        // 以下、アセンブリコード
        assembly {
            // "Allocate" memory for output (0x40 is where "free memory" pointer is stored by convention)
            // フリーメモリを取得する。
            let x := mload(0x40)
            // First 32 bytes are the padded length of data, so exclude that
            // 算術命令(data + 32)
            let d := add(data, 32)
            // 戻り値を取得する。
            // 34710 is the value that solidity is currently emitting
            // It includes callGas (700) + callVeryLow (3, to pay for SUB) + callValue TransferGas (9000) +
            // callNewAccountGas (25000, in case the destination address does not exist and needs creating)
            // 外部の変数？を参照する。
            result := call(
                // 算術命令(gas - 34710)
                sub(gas, 34710),
                // 送信先アドレス
                destination,
                // 送金額
                value,
                d,
                // トランザクションのデータサイズ
                dataLength,
                x,
                0                  // Output is ignored, therefore the output size is zero
            )
        }
        // 戻り値を返却
        return result;
    }

    /// @dev Returns the confirmation status of a transaction.
    /// @param transactionId Transaction ID.
    /// @return Confirmation status.
    // トランザクションが確認済みかどうかチェックする関数
    function isConfirmed(uint transactionId) public view returns (bool) {
        uint count = 0;
        for (uint i=0; i<owners.length; i++) {
            if (confirmations[transactionId][owners[i]])
                count += 1;
            // 必要な署名数に達していることを確認する。
            if (count == required)
                return true;
        }
    }

    /*
     * Internal functions
     */
    /// @dev Adds a new transaction to the transaction mapping, if transaction does not exist yet.
    /// @param destination Transaction target address.
    /// @param value Transaction ether value.
    /// @param data Transaction data payload.
    /// @return Returns transaction ID.
    function addTransaction(address destination, uint value, bytes memory data) internal notNull(destination) returns (uint transactionId) {
        transactionId = transactionCount;
        // トランザクションデータを作成する。
        transactions[transactionId] = Transaction({
            destination: destination,
            value: value,
            data: data,
            executed: false
        });
        // トランザクションIDを発行
        transactionCount += 1;
        // イベントの呼び出し
        emit Submission(transactionId);
    }

    /*
     * Web3 call functions
     */
    /// @dev Returns number of confirmations of a transaction.
    /// @param transactionId Transaction ID.
    /// @return Number of confirmations.
    // トランザクションの同意数を取得する。
    function getConfirmationCount(uint transactionId) public view returns (uint count) {
        for (uint i=0; i<owners.length; i++)
            if (confirmations[transactionId][owners[i]])
                count += 1;
    }

    /// @dev Returns total number of transactions after filers are applied.
    /// @param pending Include pending transactions.
    /// @param executed Include executed transactions.
    /// @return Total number of transactions after filters are applied.
    function getTransactionCount(bool pending, bool executed) public view returns (uint count) {
        for (uint i=0; i<transactionCount; i++)
            if (pending && !transactions[i].executed || executed && transactions[i].executed)
                count += 1;
    }

    /// @dev Returns list of owners.
    /// @return List of owner addresses.
    function getOwners() public view returns (address[] memory) {
        return owners;
    }

    /// @dev Returns array with owner addresses, which confirmed transaction.
    /// @param transactionId Transaction ID.
    /// @return Returns array of owner addresses.
    // トランザクションに署名したコントラクト所有者のアドレスリストを返す関数
    function getConfirmations(uint transactionId) public view returns (address[] memory _confirmations) {
        address[] memory confirmationsTemp = new address[](owners.length);
        uint count = 0;
        uint i;
        for (i=0; i<owners.length; i++)
            if (confirmations[transactionId][owners[i]]) {
                confirmationsTemp[count] = owners[i];
                count += 1;
            }
        _confirmations = new address[](count);
        for (i=0; i<count; i++)
            _confirmations[i] = confirmationsTemp[i];
    }

    /// @dev Returns list of transaction IDs in defined range.
    /// @param from Index start position of transaction array.
    /// @param to Index end position of transaction array.
    /// @param pending Include pending transactions.
    /// @param executed Include executed transactions.
    /// @return Returns array of transaction IDs.
    function getTransactionIds(uint from, uint to, bool pending, bool executed) public view returns (uint[] memory _transactionIds) {
        uint[] memory transactionIdsTemp = new uint[](transactionCount);
        uint count = 0;
        uint i;
        for (i=0; i<transactionCount; i++)
            if (   pending && !transactions[i].executed || executed && transactions[i].executed) {
                transactionIdsTemp[count] = i;
                count += 1;
            }
        _transactionIds = new uint[](to - from);
        for (i=from; i<to; i++)
            _transactionIds[i - from] = transactionIdsTemp[i];
    }

    // accept all requests
    // すべての要求を承認するための関数
    function acceptRelayedCall(
        address,
        address from,
        bytes calldata,
        uint256 transactionFee,
        uint256 gasPrice,
        uint256,
        uint256,
        bytes calldata,
        uint256 maxPossibleCharge
        ) external view returns (uint256, bytes memory) {
        return _approveRelayedCall(abi.encode(from, maxPossibleCharge, transactionFee, gasPrice));
    }

    function _preRelayedCall(bytes memory context) internal returns (bytes32) {
        return "";
    }

    function _postRelayedCall(bytes memory context, bool, uint256 actualCharge, bytes32) internal {
    }
}