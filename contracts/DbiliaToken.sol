// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-solidity/contracts/token/ERC721/ERC721.sol";
import "./ERC721URIStorageEnumerable.sol";
import "openzeppelin-solidity/contracts/utils/Counters.sol";
import "openzeppelin-solidity/contracts/utils/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";
import "./AccessControl.sol";
//import "hardhat/console.sol";

// contract deployer is CEO's EOA
// CEO adds Dbilia EOA in AccessControl
// CEO adds Marketplace contract in AccessControl
// Dbilia EOA does all the essential calls
// CEO is a master account who can halt smart contract and
// remove Dbilia EOA and Marketplace EOA just in case something happens

interface IMarketplace {
    function setPasscode(bytes32) external;
}

contract DbiliaToken is ERC721URIStorageEnumerable, AccessControl {
  using Counters for Counters.Counter;
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  struct RoyaltyReceiver {
    uint16 percentage;
    string receiverId;
  }

  struct TokenOwner {
    bool isW3user;
    address w3owner;
    string w2owner;
  }

  Counters.Counter private _tokenIds;
  IERC20 public weth; // WETH token contract
  address public beneficiary; // to receive user-transferred WETH

  uint16 public constant ROYALTY_MAX = 99;
  uint16 public feePercent;

  // Track royalty receiving address and percentage
  mapping (uint256 => RoyaltyReceiver) public royaltyReceivers;
  // Track w2user's token ownership
  mapping(uint256 => TokenOwner) public tokenOwners;
  // Make sure no duplicate is created per product/edition
  mapping (string => mapping(uint256 => uint256)) public productEditions;

  // Events
  event BatchMintWithFiatw2user(
    string _royaltyReceiverId,
    uint16 _royaltyPercentage,
    string _minterId,
    string _productId,
    uint256 _editionIdStart,
    uint256 _editionIdEnd,
    uint256 _mintedTokenIdStart,
    uint256 _mintedTokenIdEnd,
    uint256 _timestamp
  );

  event MintWithFiatw2user(
    uint256 _tokenId,
    string _royaltyReceiverId,
    uint16 _royaltyPercentage,
    string _minterId,
    string _productId,
    uint256 _edition,
    uint256 _timestamp
  );

  event MintWithFiatw3user(
    uint256 _tokenId,
    string _royaltyReceiverId,
    uint16 _royaltyPercentage,
    address indexed _minter,
    string _productId,
    uint256 _edition,
    uint256 _timestamp
  );

  event MintWithETH(
    uint256 _tokenId,
    string _royaltyReceiverId,
    uint16 _royaltyPercentage,
    address indexed _minterAddress,
    string _productId,
    uint256 _edition,
    uint256 _timestamp
  );

  event MintWithETHAndPurchase(
    uint256 _tokenId,
    string _royaltyReceiverId,
    uint16 _royaltyPercentage,
    address indexed _minter,
    string _productId,
    uint256 _edition,
    uint256 _timestamp
  );

  event ChangeTokenOwnership(
    uint256 _tokenId,
    string _newOwnerId,
    address indexed _newOwner,
    uint256 _timestamp
  );

  /**
    * Constructor
    *
    * Define the owner of the contract
    * Set Dbilia token name and symbol
    * Set initial fee percentage which is 2.5%
    *
    * @param _name Dbilia token name
    * @param _symbol Dbilia token symbol
    * @param _feePercent fee percentage Dbilia account will receive
    */
  constructor(
    string memory _name,
    string memory _symbol,
    uint16 _feePercent,
    address _wethAddress,
    address _beneficiaryAddress
  )
    ERC721(_name, _symbol)
    EIP712Base(DOMAIN_NAME, DOMAIN_VERSION, block.chainid)
    {
      feePercent = _feePercent;
      weth = IERC20(_wethAddress);
      beneficiary = _beneficiaryAddress;
    }

  // Over-ride _msgSender() function of contract Context inherited by ERC721
  // with  msgSender() function of contract EIP712MetaTransaction
  // From now on, use _msgSender() in replacement of msg.sender
  function _msgSender() internal view override returns (address sender) {
    return msgSender();
  }

  // Apply "isMaintaining" flag for token transfer
  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 tokenId
  ) internal virtual override {
    super._beforeTokenTransfer(from, to, tokenId);

    require(!isMaintaining, "it's currently maintaining");
  }

  /**
    * Minting paid with USD from w2user
    * Dbilia keeps the token on w2user's behalf

    * Precondition
    * 1. user pays gas fee to Dbilia in USD
    *
    * @param _royaltyReceiverId internal id of creator of card
    * @param _royaltyPercentage creator of card's royalty %
    * @param _minterId minter's internal id
    * @param _productId product id
    * @param _edition edition number
    * @param _tokenURI token uri stored in IPFS
    */
  function mintWithFiatw2user(
    string memory _royaltyReceiverId,
    uint16 _royaltyPercentage,
    string memory _minterId,
    string memory _productId,
    uint256 _edition,
    string memory _tokenURI
  )
    public
    isActive
    onlyDbilia
    returns (uint256)
  {
    require(bytes(_royaltyReceiverId).length > 0, "royalty receiver id is empty");
    require(
      _royaltyPercentage >= 0 && _royaltyPercentage <= ROYALTY_MAX,
      "royalty percentage is empty or exceeded max"
    );
    require(bytes(_minterId).length > 0, "minter id is empty");
    require(bytes(_productId).length > 0, "product id is empty");

    require(bytes(_tokenURI).length > 0, "token uri is empty");
    require(
      productEditions[_productId][_edition] == 0,
      "product edition has already been created"
    );

    _tokenIds.increment();

    uint256 newTokenId = _tokenIds.current();
    // Track the creator of card
    royaltyReceivers[newTokenId] = RoyaltyReceiver({
      receiverId: _royaltyReceiverId,
      percentage: _royaltyPercentage
    });
    // Track the owner of token
    tokenOwners[newTokenId] = TokenOwner({
      isW3user: false,
      w3owner: address(0),
      w2owner: _minterId
    });
    // productId and edition are mapped to new token
    productEditions[_productId][_edition] = newTokenId;
    // Dbilia keeps the token on minter's behalf
    _mint(_msgSender(), newTokenId);
    _setTokenURI(newTokenId, _tokenURI);

    emit MintWithFiatw2user(newTokenId, _royaltyReceiverId, _royaltyPercentage, _minterId, _productId, _edition, block.timestamp);
    
    return newTokenId;
  }

  /**
    * Batch mint of the same product for multiple editions
  
    * @param _royaltyReceiverId internal id of creator of card
    * @param _royaltyPercentage creator of card's royalty %
    * @param _minterId minter's internal id
    * @param _productId product id
    * @param _editionIdStart start Id of the edition to be minted
    * @param _editionIdEnd end Id of the edition to be minted
    * @param _tokenURI token uri stored in IPFS
    */
  function batchMintWithFiatw2user(
    string memory _royaltyReceiverId,
    uint16 _royaltyPercentage,
    string memory _minterId,
    string memory _productId,
    uint256 _editionIdStart,
    uint256 _editionIdEnd,
    string memory _tokenURI
  )
    public
    isActive
    onlyDbilia
  {
    require(bytes(_royaltyReceiverId).length > 0, "royalty receiver id is empty");
    require(
      _royaltyPercentage >= 0 && _royaltyPercentage <= ROYALTY_MAX,
      "royalty percentage is empty or exceeded max"
    );
    require(bytes(_minterId).length > 0, "minter id is empty");
    require(bytes(_productId).length > 0, "product id is empty");

    require(bytes(_tokenURI).length > 0, "token uri is empty");

    require(_editionIdStart <= _editionIdEnd, "invalid editionIdStart or editionIdEnd");

    bool mintedTokenIdStartAssigned = false;
    uint256 mintedTokenIdStart = 0;
    uint256 mintedTokenIdEnd = 0;
    uint256 mintedTokenId;

    for (uint256 i = _editionIdStart; i <= _editionIdEnd; i++) {
      // Let the whole batch-mint tx reverted if any of the product edition has already been minted
      // to ensure integrity of the minted tokenIds
      mintedTokenId = mintWithFiatw2user(
        _royaltyReceiverId, 
        _royaltyPercentage, 
        _minterId, 
        _productId, 
        i, 
        _tokenURI
      );

      // Assign "mintedTokenIdStart" only once
      if (mintedTokenIdStartAssigned == false) {
        mintedTokenIdStart = mintedTokenId;
        mintedTokenIdStartAssigned = true;
      }

      mintedTokenIdEnd = mintedTokenId;
    }

    emit BatchMintWithFiatw2user(
      _royaltyReceiverId, 
      _royaltyPercentage, 
      _minterId, 
      _productId, 
      _editionIdStart, 
      _editionIdEnd,
      mintedTokenIdStart,
      mintedTokenIdEnd,
      block.timestamp);
  }

/**
    * Minting paid with USD from w3user
    * token is sent to w3user's EOA

    * Precondition
    * 1. user pays gas fee to Dbilia in USD
    *
    * @param _royaltyReceiverId internal id of creator of card
    * @param _royaltyPercentage creator of card's royalty %
    * @param _minter minter's address
    * @param _productId product id
    * @param _edition edition number
    * @param _tokenURI token uri stored in IPFS
    */
  function mintWithFiatw3user(
    string memory _royaltyReceiverId,
    uint16 _royaltyPercentage,
    address _minter,
    string memory _productId,
    uint256 _edition,
    string memory _tokenURI
  )
    public
    isActive
    onlyDbilia
  {
    require(bytes(_royaltyReceiverId).length > 0, "royalty receiver id is empty");
    require(
      _royaltyPercentage >= 0 && _royaltyPercentage <= ROYALTY_MAX,
      "royalty percentage is empty or exceeded max"
    );
    require(_minter != address(0x0), "minter address is empty");
    require(bytes(_productId).length > 0, "product id is empty");

    require(bytes(_tokenURI).length > 0, "token uri is empty");
    require(
      productEditions[_productId][_edition] == 0,
      "product edition has already been created"
    );

    _tokenIds.increment();

    uint256 newTokenId = _tokenIds.current();
    // Track the creator of card
    royaltyReceivers[newTokenId] = RoyaltyReceiver({
      receiverId: _royaltyReceiverId,
      percentage: _royaltyPercentage
    });
    // Track the owner of token
    tokenOwners[newTokenId] = TokenOwner({
      isW3user: true,
      w3owner: _minter,
      w2owner: ""
    });
    // productId and edition are mapped to new token
    productEditions[_productId][_edition] = newTokenId;

    _mint(_minter, newTokenId);
    _setTokenURI(newTokenId, _tokenURI);

    emit MintWithFiatw3user(newTokenId, _royaltyReceiverId, _royaltyPercentage, _minter, _productId, _edition, block.timestamp);
  }

  /**
    * Minting paid with ETH from w3user
    *
    * @param _royaltyReceiverId internal id of creator of card
    * @param _royaltyPercentage creator of card's royalty %
    * @param _productId product id
    * @param _edition edition number
    * @param _tokenURI token uri stored in IPFS
    */
  function mintWithETH(
    string memory _royaltyReceiverId,
    uint16 _royaltyPercentage,
    string memory _productId,
    uint256 _edition,
    string memory _tokenURI,
    bytes32 _passcode
  )
    public
    isActive
    verifyPasscode(_passcode)
  {
    require(bytes(_royaltyReceiverId).length > 0, "royalty receiver id is empty");
    require(
      _royaltyPercentage >= 0 && _royaltyPercentage <= ROYALTY_MAX,
      "royalty percentage is empty or exceeded max"
    );
    require(bytes(_productId).length > 0, "product id is empty");

    require(bytes(_tokenURI).length > 0, "token uri is empty");
    require(
      productEditions[_productId][_edition] == 0,
      "product edition has already been created"
    );

    _tokenIds.increment();

    uint256 newTokenId = _tokenIds.current();
    // Track the creator of card
    royaltyReceivers[newTokenId] = RoyaltyReceiver({
      receiverId: _royaltyReceiverId,
      percentage: _royaltyPercentage
    });
    // Track the owner of token
    tokenOwners[newTokenId] = TokenOwner({
      isW3user: true,
      w3owner: _msgSender(),
      w2owner: ""
    });
    // productId and edition are mapped to new token
    productEditions[_productId][_edition] = newTokenId;

    _mint(_msgSender(), newTokenId);
    _setTokenURI(newTokenId, _tokenURI);

    emit MintWithETH(newTokenId, _royaltyReceiverId, _royaltyPercentage, _msgSender(), _productId, _edition, block.timestamp);
  }

  /**
    * Minting paid with ETH and purchase from w3user
    *
    * @param _creatorAddress address of creator
    * @param _validateAmount  paid in correct amount of weth
    * @param _minter address of minter
    * @param _royaltyReceiverId internal id of creator of card
    * @param _royaltyPercentage creator of card's royalty %
    * @param _productId product id
    * @param _edition edition number
    * @param _tokenURI token uri stored in IPFS
    */
  function mintWithETHAndPurchase(
    address _creatorAddress,
    uint256 _validateAmount,
    address _minter,
    string memory _royaltyReceiverId,
    uint16 _royaltyPercentage,
    string memory _productId,
    uint256 _edition,
    string memory _tokenURI
  )
    public
    isActive
    onlyDbilia
  {
    require(_creatorAddress != address(0x0), "creator address is empty");
    require(_validateAmount > 0, "Invalid amount");
    require(_minter != address(0x0), "minter address is empty");
    require(weth.allowance(_minter, address(this)) >= _validateAmount, "Weth allowance too low");

    require(bytes(_royaltyReceiverId).length > 0, "royalty receiver id is empty");
    require(
      _royaltyPercentage >= 0 && _royaltyPercentage <= ROYALTY_MAX,
      "royalty percentage is empty or exceeded max"
    );
    require(bytes(_productId).length > 0, "product id is empty");
    require(bytes(_tokenURI).length > 0, "token uri is empty");
    require(
      productEditions[_productId][_edition] == 0,
      "product edition has already been created"
    );

    uint256 fee = _validateAmount.mul(feePercent).div(feePercent + 1000);

    weth.safeTransferFrom(_minter, beneficiary, fee);
    weth.safeTransferFrom(_minter, _creatorAddress, _validateAmount.sub(fee));

    _tokenIds.increment();

    uint256 newTokenId = _tokenIds.current();
    // Track the creator of card
    royaltyReceivers[newTokenId] = RoyaltyReceiver({
      receiverId: _royaltyReceiverId,
      percentage: _royaltyPercentage
    });
    // Track the owner of token
    tokenOwners[newTokenId] = TokenOwner({
      isW3user: true,
      w3owner: _minter,
      w2owner: ""
    });
    // productId and edition are mapped to new token
    productEditions[_productId][_edition] = newTokenId;

    _mint(_minter, newTokenId);
    _setTokenURI(newTokenId, _tokenURI);

    emit MintWithETHAndPurchase(newTokenId, _royaltyReceiverId, _royaltyPercentage, _minter, _productId, _edition, block.timestamp);
  }

  /**
    * Set flat fee by Dbilia
    * Only CEO can set it
    *
    * @param _feePercent new fee percent
    */
  function setFlatFee(uint16 _feePercent)
    public
    onlyCEO
    returns (bool)
  {
    require(
      _feePercent > 0 && _feePercent <= 100,
      "flat fee is empty or exceeded max"
    );
    feePercent = _feePercent;
    return true;
  }

  /**
    * Change ownership of token
    * Only Dbilia can set it
    *
    * @param _tokenId token id
    * @param _newOwner w3user's address
    * @param _newOwnerId w2user's internal id
    */
  function changeTokenOwnership(
    uint256 _tokenId,
    address _newOwner,
    string memory _newOwnerId
  )
    public
    isActive
    onlyDbilia
  {
    require(
      _newOwner != address(0) ||
      bytes(_newOwnerId).length > 0,
      "either one of new owner should be passed in"
    );
    require(
      !(_newOwner != address(0) &&
      bytes(_newOwnerId).length > 0),
      "cannot pass in both new owner info"
    );

    if (_newOwner != address(0)) {
      tokenOwners[_tokenId] = TokenOwner({
        isW3user: true,
        w3owner: _newOwner,
        w2owner: ""
      });
    } else {
      tokenOwners[_tokenId] = TokenOwner({
        isW3user: false,
        w3owner: address(0),
        w2owner: _newOwnerId
      });
    }

    emit ChangeTokenOwnership(_tokenId, _newOwnerId, _newOwner, block.timestamp);
  }

  /**
    * Claim ownership of token
    *
    * @param _tokenIDs token id array
    * @param _w3user receiver address
    */
  function claimToken(uint256[] memory _tokenIDs, address _w3user) public onlyDbilia {
    for (uint i = 0; i < _tokenIDs.length; i++) {
      uint256 tokenId = _tokenIDs[i];
      require(!tokenOwners[tokenId].isW3user, "Only web2 users token can be claimed");
      require(ownerOf(tokenId) == dbiliaTrust, "Dbilia wallet does not own this token");
      if (_w3user != address(0)) {
        _transfer(dbiliaTrust, _w3user, tokenId);
        tokenOwners[tokenId] = TokenOwner({
          isW3user: true,
          w3owner: _w3user,
          w2owner: ""
        });
      }
    }
  }

  /**
    * Check product edition has already been minted
    *
    * @param _productId product id
    * @param _edition edition
    */
  function isProductEditionMinted(string memory _productId, uint256 _edition) public view returns (bool) {
    if (productEditions[_productId][_edition] > 0) {
      return true;
    }
    return false;
  }

  /**
    * Token ownership getter
    *
    *  @param _tokenId token id
    */
  function getTokenOwnership(uint256 _tokenId) public view returns (bool, address, string memory) {
    TokenOwner memory tokenOwner = tokenOwners[_tokenId];
    return (tokenOwner.isW3user, tokenOwner.w3owner, tokenOwner.w2owner);
  }

  /**
    * Royalty receiver getter
    *bytes32
    *  @param _tokenId token id
    */
  function getRoyaltyReceiver(uint256 _tokenId) public view returns (string memory, uint16) {
    RoyaltyReceiver memory royaltyReceiver = royaltyReceivers[_tokenId];
    return (royaltyReceiver.receiverId, royaltyReceiver.percentage);
  }

  function setPasscode(string memory strPasscode) onlyCEO external {
    require(bytes(strPasscode).length <= 32, "less than 32 bytes");
    bytes32 passcode_;
    if (bytes(strPasscode).length == 0) {
      passcode_ = 0x0;
    }
    else {
      assembly {
        passcode_ := mload(add(strPasscode, 32))
      }
    }
    passcode = passcode_;
    IMarketplace(marketplace).setPasscode(passcode_);
  }

  /////// Data migration section //////////
  function mintForDataMigration(address _to, string memory _tokenURI, uint256 _tokenId) 
    external 
    onlyDbilia 
  {
    _mint(_to, _tokenId);
    _setTokenURI(_tokenId, _tokenURI);
  }

  /**
    * Set royalty receiver info for a given tokenId
    *
    * @param _tokenId token id
    * @param _percentage percentage
    * @param _receiverId receiverId
    */
  function setRoyaltyReceiver(uint256 _tokenId, string memory _receiverId, uint16 _percentage) 
    external 
    onlyDbilia 
  {
    royaltyReceivers[_tokenId] = RoyaltyReceiver({
      receiverId: _receiverId,
      percentage: _percentage
    });
  }

  /**
    * Set royalty receiver info for a given tokenId
    *
    * @param _tokenId token id
    * @param _isW3user isW3user
    * @param _w3owner w3owner
    * @param _w2owner w2owner
    */
  function setTokenOwner(uint256 _tokenId, bool _isW3user, address _w3owner, string memory _w2owner) 
    external 
    onlyDbilia 
  {
    tokenOwners[_tokenId] = TokenOwner({
      isW3user: _isW3user,
      w3owner: _w3owner,
      w2owner: _w2owner
    });
  }

  /**
    * Set tokenId for a given _productId and _edition. The info of _productId and _edition is stored in DB
    *
    * @param _tokenId token id
    * @param _productId _productId
    * @param _edition _edition
    */
  function setProductEditionTokenId(uint256 _tokenId, string memory _productId, uint256 _edition) 
    external 
    onlyDbilia 
  {
    productEditions[_productId][_edition] = _tokenId;
  }

  /////////////////////////////////////////
}
