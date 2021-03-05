pragma solidity 0.5.13;

// openzeppelinのインポート
// openzeppelin：セキュリティーソリューションを提供するスマートコントラクト用ライブラリ
// ERC20は、トークン基準
// GSN(Gas Station Network) ：dappユーザーが負担するガスコストをアプリケーション側に負担させることで、ガスコストなしのトランザクションを
// 実現させるオープンソースネットワーク。(トランザクションの送信を第3者に負担させることで可能にしている。)
import "@openzeppelin/contracts-ethereum-package/contracts/GSN/GSNRecipientERC20Fee.sol";
// トークンを生成するためのMiterRoleコントラクトをインポートする。
import "@openzeppelin/contracts-ethereum-package/contracts/access/roles/MinterRole.sol";
// コントラクトの実行権限を限定するためにOwnableコントラクトをインポートする。
import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
// コントラクトのインポート
import "./GSNMultiSigWalletWithDailyLimit.sol";

// マルチシグウォレット生成コントラクト
contract GSNMultisigFactory is GSNRecipientERC20Fee, MinterRole, Ownable {
    //アドレスとそれに紐づくウォレットのアドレスを紐づけるマップ変数
    mapping(address => address[]) public deployedWallets;
    // マルチシグウォレットかどうかの判定を紐づけるマップ変数
    mapping(address => bool) public isMULTISigWallet;
    // コントラクトがインスタンス化されたときのイベントをセット
    // sender：コントラクト呼び出し元
    // instantiation：インスタンス化されたコントラクトのアドレス
    event ContractInstantiation(address sender, address instantiation);

    // 初期化関数
    function initialize(string memory name, string memory symbol) initializer public {
        // 各種、コントラクトを初期化
        GSNRecipientERC20Fee.initialize(name, symbol);
        MinterRole.initialize(_msgSender());
        Ownable.initialize(_msgSender());
    }

    /*
     * トークン生成用関数
     */
    function mint(address account, uint256 amount) public onlyMinter {
        // トークン生成関数の呼び出し。
        _mint(account, amount);
    }

    /*
     * トークンを生成した人(アドレス)を削除する関数
     * コントラクト作成者のみが実行可能
     */
    function removeMinter(address account) public onlyOwner {
        // アドレス削除関数の呼び出し
        _removeMinter(account);
    }

    /*
     * Public functions
     */
    /// @dev Returns number of instantiations by creator.
    /// @param creator Contract creator.
    /// @return Returns number of instantiations by creator.
    function getDeployedWalletsCount(address creator) public view returns(uint) {
        // デプロイされたウォレットの数を返す。
        return deployedWallets[creator].length;
    }

    /*
     * ウォレット生成関数
     * @_owners コントラクト作成者アドレスリスト
     * @_required 最低限必要な署名数
     * @_dailyLimit 値幅制限
     * @return wallet ウォレットのアドレス
     */
    function create(address[] memory _owners, uint _required, uint _dailyLimit) public returns (address wallet)
    {
        // マルチシグインスタンスを生成
        GSNMultiSigWalletWithDailyLimit multisig = new GSNMultiSigWalletWithDailyLimit();
        // マルチシグウォレットを初期化
        multisig.initialize(_owners, _required, _dailyLimit);
        // アドレスを格納する。
        wallet = address(multisig);
        // マルチシグウォレットであることを保管する。
        isMULTISigWallet[wallet] = true;
        // デプロイ済みウォレットアドレスリストに追加する。
        deployedWallets[_msgSender()].push(wallet);
        // イベントの呼び出し。
        emit ContractInstantiation(_msgSender(), wallet);
    }
}
