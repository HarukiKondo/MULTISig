pragma solidity 0.5.13;
// マルチシグウォレットコントラクトをインポートｓ
import "./GSNMultiSigWallet.sol";


/// @title Multisignature wallet with daily limit - Allows an owner to withdraw a daily limit without multisig.
// 一人のコントラクト所有者が複数署名無しに引き出せる一日の限界を表すコントラクト
/// @author Stefan George - <stefan.george@consensys.net>
contract GSNMultiSigWalletWithDailyLimit is GSNMultiSigWallet {

    /*
     *  Events
     */
    event DailyLimitChange(uint dailyLimit);

    /*
     *  Storage
     */
    uint public dailyLimit;
    uint public lastDay;
    uint public spentToday;

    /*
     * Public functions
     */
    /// @dev Contract constructor sets initial owners, required number of confirmations and daily withdraw limit.
    /// @param _owners List of initial owners.
    /// @param _required Number of required confirmations.
    /// @param _dailyLimit Amount in wei, which can be withdrawn without confirmations on a daily basis.
    function initialize(address[] memory _owners, uint _required, uint _dailyLimit) public initializer {
        GSNMultiSigWallet.initialize(_owners, _required);
        dailyLimit = _dailyLimit;
    }

    /// @dev Allows to change the daily limit. Transaction has to be sent by wallet.
    /// @param _dailyLimit Amount in wei.
    function changeDailyLimit(uint _dailyLimit) public onlyWallet {
        dailyLimit = _dailyLimit;
        emit DailyLimitChange(_dailyLimit);
    }

    /// @dev Allows anyone to execute a confirmed transaction or ether withdraws until daily limit is reached.
    /// @param transactionId Transaction ID.
    function executeTransaction(uint transactionId) public ownerExists(_msgSender()) confirmed(transactionId, _msgSender()) notExecuted(transactionId) {
        // IDからトランザクションデータを取得する。
        Transaction storage txn = transactions[transactionId];
        // 確認済みとする。
        bool _confirmed = isConfirmed(transactionId);
        if (_confirmed || txn.data.length == 0 && isUnderLimit(txn.value)) {
            // 実行済みフラグをONにする。
            txn.executed = true;
            if (!_confirmed)
                spentToday += txn.value;
            // external_call()関数の戻り値がtrueなら実行する。falseなら取り消す。
            if (external_call(txn.destination, txn.value, txn.data.length, txn.data))
                // イベントの呼び出し
                emit Execution(transactionId);
            else {
                // イベントの呼び出し
                emit ExecutionFailure(transactionId);
                // 実行済みフラグをOFFにする。
                txn.executed = false;
                if (!_confirmed)
                    spentToday -= txn.value;
            }
        }
    }

    /*
     * Internal functions
     */
    /// @dev Returns if amount is within daily limit and resets spentToday after one day.
    /// @param amount Amount to withdraw.
    /// @return Returns if amount is under daily limit.
    function isUnderLimit(uint amount) internal returns (bool) {
        if (now > lastDay + 24 hours) {
            lastDay = block.timestamp;
            spentToday = 0;
        }
        if (spentToday + amount > dailyLimit || spentToday + amount < spentToday)
            return false;
        return true;
    }

    /*
     * Web3 call functions
     */
    /// @dev Returns maximum withdraw amount.
    /// @return Returns amount.
    function calcMaxWithdraw() public view returns (uint) {
        if (now > lastDay + 24 hours)
            return dailyLimit;
        if (dailyLimit < spentToday)
            return 0;
        return dailyLimit - spentToday;
    }
}