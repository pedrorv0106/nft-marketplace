// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "./DbiliaToken.sol";
import "./EIP712MetaTransaction.sol";
import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";

contract WethReceiver is EIP712MetaTransaction {
  using SafeERC20 for IERC20;

  DbiliaToken public dbiliaToken;
  IERC20 public weth; // WETH token contract
  address public beneficiary; // to receive user-transferred WETH

  event ReceiveWeth(address _from, string _productId, uint256 _amount);
  event SendPayout(address _from, address _to, uint256 _amount);

  modifier isActive {
    require(!dbiliaToken.isMaintaining());
    _;
  }

  modifier onlyDbilia() {
    require(
      msgSender() == dbiliaToken.owner() ||
        msgSender() == dbiliaToken.dbiliaTrust() ||
        dbiliaToken.isAuthorizedAddress(msgSender()),
      "caller is not one of dbilia accounts"
    );
    _;
  }

  constructor(
    address _tokenAddress,
    address _wethAddress,
    address _beneficiaryAddress
  ) EIP712Base(DOMAIN_NAME, DOMAIN_VERSION, block.chainid) {
    dbiliaToken = DbiliaToken(_tokenAddress);
    weth = IERC20(_wethAddress);
    beneficiary = _beneficiaryAddress;
  }

  function receiveWeth(string memory _productId, uint256 _amount)
    external
    isActive
  {
    require(bytes(_productId).length > 0, "WethReceiver: Invalid product Id");
    require(_amount > 0, "WethReceiver: Invalid amount");

    weth.safeTransferFrom(msgSender(), beneficiary, _amount);

    emit ReceiveWeth(msgSender(), _productId, _amount);
  }

  function setBeneficiary(address _beneficiary) external onlyDbilia {
    beneficiary = _beneficiary;
  }

  function sendPayout(uint256 amount, address _receiver) external onlyDbilia {
    require(amount > 0, "WethReceiver: Invalid amount");
    weth.safeTransferFrom(beneficiary, _receiver, amount);

    emit SendPayout(beneficiary, _receiver, amount);
  }
}
