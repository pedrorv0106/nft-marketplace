// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "./DbiliaToken.sol";
import "./PriceConsumerV3.sol";
import "openzeppelin-solidity/contracts/utils/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";
import "./EIP712MetaTransaction.sol";
//import "hardhat/console.sol";

contract Marketplace is PriceConsumerV3, EIP712MetaTransaction {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    DbiliaToken public dbiliaToken;
    IERC20 public weth;

    // tokenId => price in fiat (USD or EUR)
    mapping (uint256 => uint256) public tokenPriceFiat;
    mapping (uint256 => bool) public tokenOnAuction;

    // Used to protect public function
    bytes32 internal passcode = "protected";

    // Set to true for Momenta app with base currency of EUR. Any functions of "WithUSD" will be meant for "WithEUR"
    // Set to false for Dbilia app with base currency of USD
    bool public useEUR;

    // Events
    event SetForSale(
        uint256 _tokenId,
        uint256 _priceFiat,
        bool _auction,
        address indexed _seller,
        uint256 _timestamp
    );
    event PurchaseWithFiat(
        uint256 _tokenId,
        address indexed _buyer,
        string _buyerId,
        bool _isW3user,
        address _w3owner,
        string _w2owner,
        uint256 _timestamp
    );
    event PurchaseWithETH(
        uint256 _tokenId,
        address indexed _buyer,
        bool _isW3user,
        address _w3owner,
        string _w2owner,
        uint256 _fee,
        uint256 _creatorReceives,
        uint256 _sellerReceives,
        uint256 _timestamp
    );
    event BiddingWithETH(
        uint256 _tokenId,
        address indexed _bidder,
        uint256 _fee,
        uint256 _creatorReceives,
        uint256 _sellerReceives,
        uint256 _timestamp
    );
    event ClaimAuctionWinner(
        uint256 _tokenId,
        address indexed _receiver,
        string _receiverId,
        uint256 _timestamp
    );

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

    // Protect public function with passcode
    modifier verifyPasscode(bytes32 _passcode) {
        require(_passcode == keccak256(bytes.concat(passcode, bytes20(address(msgSender())))), "invalid passcode");
        _;
    }

    constructor(address _tokenAddress, address _wethAddress, bool _useEUR)
        EIP712Base(DOMAIN_NAME, DOMAIN_VERSION, block.chainid)
    {
        dbiliaToken = DbiliaToken(_tokenAddress);
        weth = IERC20(_wethAddress);
        useEUR = _useEUR;
    }

    /**
        SET FOR SALE FUNCTIONS
        - When w2 or w3user wants to put it up for sale
        - trigger getTokenOwnership() by passing in tokenId and find if it belongs to w2 or w3user
        - if w2 or w3user wants to pay in USD, they pay gas fee to Dbilia first
        - then Dbilia triggers setForSaleWithFiat for them
        - if w3user wants to pay in ETH they can trigger setForSaleWithETH,
        - but msgSender() must have the ownership of token
     */

  /**
    * w2, w3user selling a token in USD
    *
    * Preconditions
    * 1. before we make this contract go live,
    * 2. trigger setApprovalForAll() from Dbilia EOA to approve this contract
    * 3. seller pays gas fee in USD
    * 4. trigger getTokenOwnership() and if tokenId belongs to w3user,
    * 5. call isApprovedForAll() first to check whether w3user has approved the contract on his behalf
    * 6. if not, w3user has to trigger setApprovalForAll() with his ETH to trigger setForSaleWithFiat()
    *
    * @param _tokenId token id to sell
    * @param _priceFiat price in USD or in EURto sell
    * @param _auction on auction or not
    */
    function setForSaleWithFiat(uint256 _tokenId, uint256 _priceFiat, bool _auction) public isActive onlyDbilia {
        require(_tokenId > 0, "token id is zero or lower");
        require(tokenPriceFiat[_tokenId] == 0, "token has already been set for sale");
        require(_priceFiat > 0, "price is zero or lower");
        require(
            dbiliaToken.isApprovedForAll(dbiliaToken.dbiliaTrust(), address(this)),
            "Dbilia did not approve Marketplace contract"
        );
        tokenPriceFiat[_tokenId] = _priceFiat;
        tokenOnAuction[_tokenId] = _auction;
        emit SetForSale(_tokenId, _priceFiat, _auction, msgSender(), block.timestamp);
    }

  /**
    * w2, w3user removing a token in USD
    *
    * @param _tokenId token id to remove
    */
    function removeSetForSaleFiat(uint256 _tokenId) public isActive onlyDbilia {
        require(_tokenId > 0, "token id is zero or lower");
        require(tokenPriceFiat[_tokenId] > 0, "token has not set for sale");
        require(
            dbiliaToken.isApprovedForAll(dbiliaToken.dbiliaTrust(), address(this)),
            "Dbilia did not approve Marketplace contract"
        );
        tokenPriceFiat[_tokenId] = 0;
        tokenOnAuction[_tokenId] = false;
        emit SetForSale(_tokenId, 0, false, msgSender(), block.timestamp);
    }

  /**
    * w3user selling a token in ETH
    *
    * Preconditions
    * 1. call isApprovedForAll() to check w3user has approved the contract on his behalf
    * 2. if not, trigger setApprovalForAll() from w3user
    *
    * @param _tokenId token id to sell
    * @param _priceFiat price in USD to sell
    * @param _auction on auction or not
    */
    function setForSaleWithETH(uint256 _tokenId, uint256 _priceFiat, bool _auction, bytes32 _passcode) public isActive verifyPasscode(_passcode) {
        require(_tokenId > 0, "token id is zero or lower");
        require(tokenPriceFiat[_tokenId] == 0, "token has already been set for sale");
        require(_priceFiat > 0, "price is zero or lower");
        address owner = dbiliaToken.ownerOf(_tokenId);
        require(owner == msgSender(), "caller is not a token owner");
        require(dbiliaToken.isApprovedForAll(msgSender(), address(this)),
                "token owner did not approve Marketplace contract"
        );
        tokenPriceFiat[_tokenId] = _priceFiat;
        tokenOnAuction[_tokenId] = _auction;
        emit SetForSale(_tokenId, _priceFiat, _auction, msgSender(), block.timestamp);
    }

  /**
    * w3user removing a token in USD
    *
    * @param _tokenId token id to remove
    */
    function removeSetForSaleETH(uint256 _tokenId, bytes32 _passcode) public isActive verifyPasscode(_passcode){
        require(_tokenId > 0, "token id is zero or lower");
        require(tokenPriceFiat[_tokenId] > 0, "token has not set for sale");
        address owner = dbiliaToken.ownerOf(_tokenId);
        require(owner == msgSender(), "caller is not a token owner");
        require(dbiliaToken.isApprovedForAll(msgSender(), address(this)),
                "token owner did not approve Marketplace contract"
        );
        tokenPriceFiat[_tokenId] = 0;
        tokenOnAuction[_tokenId] = false;
        emit SetForSale(_tokenId, 0, false, msgSender(), block.timestamp);
    }

  /**
    * w2user purchasing in USD
    * function triggered by Dbilia
    *
    * Preconditions
    * For NON-AUCTION
    * 1. call getTokenOwnership() to check whether seller is w2 or w3user holding the token
    * 2. if seller is w3user, call ownerOf() to check seller still holds the token
    * 3. call tokenPriceFiat() to get the price of token
    * 4. buyer pays 2.5% fee
    * 5. buyer pays gas fee
    * 6. check buyer paid in correct amount of USD (NFT price + 2.5% fee + gas fee)
    *
    * After purchase
    * 1. increase the seller's internal USD wallet balance
    *    - seller receives = (tokenPriceFiat - seller 2.5% fee - royalty)
    *    - for royalty, use royaltyReceivers(tokenId)
    * 2. increase the royalty receiver's internal USD wallet balance
    *    - for royalty, use royaltyReceivers(tokenId)
    *
    * @param _tokenId token id to buy
    * @param _buyerId buyer's w2user internal id
    */
    function purchaseWithFiatw2user(uint256 _tokenId, string memory _buyerId)
        public
        isActive
        onlyDbilia
    {
        require(tokenPriceFiat[_tokenId] > 0, "seller is not selling this token");
        require(bytes(_buyerId).length > 0, "buyerId Id is empty");

        address owner = dbiliaToken.ownerOf(_tokenId);
        (bool isW3user, address w3owner, string memory w2owner) = dbiliaToken.getTokenOwnership(_tokenId);

        if (isW3user) {
            require(owner == w3owner, "wrong owner");
            require(w3owner != address(0), "w3owner is empty");
            dbiliaToken.safeTransferFrom(w3owner, dbiliaToken.dbiliaTrust(), _tokenId);
        } else {
            require(owner == dbiliaToken.dbiliaTrust(), "wrong owner");
            require(bytes(w2owner).length > 0, "w2owner is empty");
        }

        dbiliaToken.changeTokenOwnership(_tokenId, address(0), _buyerId);
        tokenPriceFiat[_tokenId] = 0;
        tokenOnAuction[_tokenId] = false;

        emit PurchaseWithFiat(
            _tokenId,
            address(0),
            _buyerId,
            isW3user,
            w3owner,
            w2owner,
            block.timestamp
        );
    }

  /**
    * w3user purchasing in USD
    * function triggered by Dbilia
    *
    * Preconditions
    * For NON-AUCTION
    * 1. call getTokenOwnership() to check whether seller is w2 or w3user holding the token
    * 2. if seller is w3user, call ownerOf() to check seller still holds the token
    * 3. call tokenPriceFiat() to get the price of token
    * 4. buyer pays 2.5% fee
    * 5. buyer pays gas fee
    * 6. check buyer paid in correct amount of USD (NFT price + 2.5% fee + gas fee)
    *
    * After purchase
    * 1. increase the seller's internal USD wallet balance
    *    - seller receives = (tokenPriceFiat - seller 2.5% fee - royalty)
    *    - for royalty, use royaltyReceivers(tokenId)
    * 2. increase the royalty receiver's internal USD wallet balance
    *    - for royalty, use royaltyReceivers(tokenId)
    *
    * @param _tokenId token id to buy
    * @param _buyer buyer's w3user id
    */
    function purchaseWithFiatw3user(uint256 _tokenId, address _buyer)
        public
        isActive
        onlyDbilia
    {
        require(tokenPriceFiat[_tokenId] > 0, "seller is not selling this token");
        require(_buyer != address(0), "buyer address is empty");

        address owner = dbiliaToken.ownerOf(_tokenId);
        (bool isW3user, address w3owner, string memory w2owner) = dbiliaToken.getTokenOwnership(_tokenId);

        if (isW3user) {
            require(owner == w3owner, "wrong owner");
            require(w3owner != address(0), "w3owner is empty");
            dbiliaToken.safeTransferFrom(w3owner, _buyer, _tokenId);
        } else {
            require(owner == dbiliaToken.dbiliaTrust(), "wrong owner");
            require(bytes(w2owner).length > 0, "w2owner is empty");
            dbiliaToken.safeTransferFrom(dbiliaToken.dbiliaTrust(), _buyer, _tokenId);
        }

        dbiliaToken.changeTokenOwnership(_tokenId, _buyer, "");
        tokenPriceFiat[_tokenId] = 0;
        tokenOnAuction[_tokenId] = false;

        emit PurchaseWithFiat(
            _tokenId,
            _buyer,
            "",
            isW3user,
            w3owner,
            w2owner,
            block.timestamp
        );
    }

  /**
    * w3user purchasing in ETH
    * function triggered by w3user
    *
    * Preconditions
    * For NON-AUCTION
    * 1. call getTokenOwnership() to check whether seller is w2 or w3user holding the token
    * 2. if seller is w3user, call ownerOf() to check seller still holds the token
    * 3. call tokenPriceFiat() to get the price of token
    * 4. do conversion and calculate how much buyer needs to pay in ETH
    * 5. add up buyer fee 2.5% in msg.value
    *
    * After purchase
    * 1. check if seller is a w2user from getTokenOwnership(tokenId)
    * 2. if w2user, increase the seller's internal ETH wallet balance
    *    - use sellerReceiveAmount from the event
    * 3. increase the royalty receiver's internal ETH wallet balance
    *    - use royaltyReceivers(tokenId) to get the in-app address
    *    - use royaltyAmount from the event
    *
    * @param _tokenId token id to buy
    */
    function purchaseWithETHw3user(uint256 _tokenId, uint256 wethAmount, bytes32 _passcode) public isActive verifyPasscode(_passcode) {
        require(tokenPriceFiat[_tokenId] > 0, "seller is not selling this token");
        // only non-auction items can be purchased from w3user
        require(tokenOnAuction[_tokenId] == false, "this token is on auction");

        _validateAmount(_tokenId, wethAmount);

        weth.safeTransferFrom(msgSender(), address(this), wethAmount);

        address owner = dbiliaToken.ownerOf(_tokenId);
        (bool isW3user, address w3owner, string memory w2owner) = dbiliaToken.getTokenOwnership(_tokenId);

        if (isW3user) {
            require(owner == w3owner, "wrong owner");
            require(w3owner != address(0), "w3owner is empty");
            dbiliaToken.safeTransferFrom(w3owner, msgSender(), _tokenId);
        } else {
            require(owner == dbiliaToken.dbiliaTrust(), "wrong owner");
            require(bytes(w2owner).length > 0, "w2owner is empty");
            dbiliaToken.safeTransferFrom(dbiliaToken.dbiliaTrust(), msgSender(), _tokenId);
        }

        dbiliaToken.changeTokenOwnership(_tokenId, msgSender(), "");
        tokenPriceFiat[_tokenId] = 0;
        tokenOnAuction[_tokenId] = false;

        uint256 fee = _payBuyerSellerFee(wethAmount);
        uint256 royaltyAmount = _sendRoyalty(_tokenId, wethAmount);
        uint256 sellerReceiveAmount = wethAmount.sub(fee.add(royaltyAmount));

        _sendToSeller(sellerReceiveAmount, isW3user, w3owner);

        emit PurchaseWithETH(
            _tokenId,
            msgSender(),
            isW3user,
            w3owner,
            w2owner,
            fee,
            royaltyAmount,
            sellerReceiveAmount,
            block.timestamp
        );
    }

  /**
    * w3user bidding in ETH
    * function triggered by w3user
    *
    * Preconditions
    * For AUCTION
    * 1. call getTokenOwnership() to check whether seller is w2 or w3user holding the token
    * 2. if seller is w3user, call ownerOf() to check seller still holds the token
    * 3. call tokenPriceFiat() to get the price of token
    * 4. buyer pays 2.5% fee
    * 5. buyer pays gas fee
    * 6. check buyer paid in correct amount of USD (NFT price + 2.5% fee + gas fee)
    *
    * After bidding
    * 1. auction history records bidAmount, creatorReceives and sellerReceives
    *
    * @param _tokenId token id to buy
    * @param _bidPriceFiat bid amount in USD or in EUR
    */
    function placeBidWithETHw3user(uint256 _tokenId, uint256 _bidPriceFiat, uint256 wethAmount, bytes32 _passcode) public isActive verifyPasscode(_passcode) {
        require(tokenPriceFiat[_tokenId] > 0, "seller is not selling this token");
        // only non-auction items can be purchased from w3user
        require(tokenOnAuction[_tokenId] == true, "this token is not on auction");

        _validateBidAmount(_bidPriceFiat, wethAmount);

        weth.safeTransferFrom(msgSender(), address(this), wethAmount);

        uint256 fee = _payBuyerSellerFee(wethAmount);
        uint256 royaltyAmount = _sendRoyalty(_tokenId, wethAmount);
        uint256 sellerReceiveAmount = wethAmount.sub(fee.add(royaltyAmount));

        _send(sellerReceiveAmount, dbiliaToken.dbiliaTrust());

        emit BiddingWithETH(
            _tokenId,
            msgSender(),
            fee,
            royaltyAmount,
            sellerReceiveAmount,
            block.timestamp
        );
    }

  /**
    * send token to auction winner
    * function triggered by Dbilia
    *
    * Preconditions
    * For AUCTION
    * 1. call getTokenOwnership() to check whether seller is w2 or w3user holding the token
    * 2. if seller is w3user, call ownerOf() to check seller still holds the token
    *
    * After purchase
    * 1. increase the seller's internal wallet balance either in USD or ETH
    * 2. increase the royalty receiver's internal wallet balance either in USD or ETH
    *
    * @param _tokenId token id to buy
    * @param _receiver receiver address
    * @param _receiverId receiver's w2user internal id
    */
    function claimAuctionWinner(
        uint256 _tokenId,
        address _receiver,
        string memory _receiverId
    )
        public
        isActive
        onlyDbilia
    {
        require(tokenPriceFiat[_tokenId] > 0, "seller is not selling this token");
        // only non-auction items can be purchased from w3user
        require(tokenOnAuction[_tokenId] == true, "this token is not on auction");
        require(
            _receiver != address(0) ||
            bytes(_receiverId).length > 0,
            "either one of receivers should be passed in"
        );
        require(
            !(_receiver != address(0) &&
            bytes(_receiverId).length > 0),
            "cannot pass in both receiver info"
        );

        address owner = dbiliaToken.ownerOf(_tokenId);
        (bool isW3user, address w3owner, string memory w2owner) = dbiliaToken.getTokenOwnership(_tokenId);
        bool w3user = _receiver != address(0) ? true : false; // check token buyer is w3user
        // token seller is a w3user
        if (isW3user) {
            require(owner == w3owner, "wrong owner");
            require(w3owner != address(0), "w3owner is empty");
            dbiliaToken.safeTransferFrom(w3owner, w3user ? _receiver : dbiliaToken.dbiliaTrust(), _tokenId);
        // w2user
        } else {
            require(owner == dbiliaToken.dbiliaTrust(), "wrong owner");
            require(bytes(w2owner).length > 0, "w2owner is empty");
            if (w3user) {
                dbiliaToken.safeTransferFrom(dbiliaToken.dbiliaTrust(), _receiver, _tokenId);
            }
        }

        dbiliaToken.changeTokenOwnership(_tokenId, w3user ? _receiver : address(0), w3user ? "" : _receiverId);
        tokenPriceFiat[_tokenId] = 0;
        tokenOnAuction[_tokenId] = false;

        emit ClaimAuctionWinner(
            _tokenId,
            _receiver,
            _receiverId,
            block.timestamp
        );
    }

    function _eur2Usd(uint256 _usdAmount) private view returns (uint256) {
        return (_usdAmount * uint256(getThePriceEurUsd())) / 10**8;
    }

    // For purchase, Frontend calls this function to get the token price in WETH amount
    // instead of manual converting from fiat to WETH
    function getTokenPriceInWethAmountForPurchase(uint256 _tokenId) public view returns (uint256) {
        uint256 tokenPrice = tokenPriceFiat[_tokenId];
        
        // For Momenta, tokenPriceFiat is in EUR that needs to be converted to USD
        if (useEUR) {
            tokenPrice = _eur2Usd(tokenPrice);
        }

        int256 currentPriceOfETHtoUSD = getCurrentPriceOfETHtoUSD();
        uint256 buyerFee = tokenPrice.mul(dbiliaToken.feePercent()).div(1000);
        uint256 buyerTotal = tokenPrice.add(buyerFee) * 10**18;
        uint256 buyerTotalToWei = buyerTotal.div(uint256(currentPriceOfETHtoUSD));

        return buyerTotalToWei;
    }

  /**
    * Validate user purchasing in ETH matches with USD conversion using chainlink
    * checks buyer fee of the token price as well (i.e. 2.5%)
    *
    * @param _tokenId token id
    */
    function _validateAmount(uint256 _tokenId, uint256 wethAmount) private view {
        uint256 buyerTotalToWei = getTokenPriceInWethAmountForPurchase(_tokenId);
        require(wethAmount >= buyerTotalToWei, "not enough of ETH being sent");
    }

    // For bid, Frontend calls this function to get the bid price in WETH amount
    // instead of manual converting from fiat to WETH
    function getBidPriceInWethAmountForAuction(uint256 _bidPriceFiat) public view returns (uint256) {
        uint256 bidPrice = _bidPriceFiat;
        
        // For Momenta, bidPrice is in EUR that needs to be converted to USD
        if (useEUR) {
            bidPrice = _eur2Usd(bidPrice);
        }

        int256 currentPriceOfETHtoUSD = getCurrentPriceOfETHtoUSD();
        uint256 buyerFee = bidPrice.mul(dbiliaToken.feePercent()).div(1000);
        uint256 buyerTotal = bidPrice.add(buyerFee) * 10**18;
        uint256 buyerTotalToWei = buyerTotal.div(uint256(currentPriceOfETHtoUSD));
        
        return buyerTotalToWei;
    }

  /**
    * Validate user bidding in ETH matches with USD conversion using chainlink
    * checks buyer fee of the token price as well (i.e. 2.5%)
    *
    * @param _bidPriceFiat bidding price in usd
    */
    function _validateBidAmount(uint256 _bidPriceFiat, uint256 wethAmount) private view {
        uint256 buyerTotalToWei = getBidPriceInWethAmountForAuction(_bidPriceFiat);
        require(wethAmount >= buyerTotalToWei, "not enough of ETH being sent");
    }

  /**
    * Pay flat fees to Dbilia
    * i.e. buyer fee + seller fee = 5%
    */
    function _payBuyerSellerFee(uint256 wethAmount) private returns (uint256) {
        uint256 feePercent = dbiliaToken.feePercent();
        uint256 fee = wethAmount.mul(feePercent.mul(2)).div(feePercent.add(1000));
        _send(fee, dbiliaToken.dbiliaFee());
        return fee;
    }

  /**
    * Pay royalty to creator
    * Dbilia receives on creator's behalf
    *
    * @param _tokenId token id
    */
    function _sendRoyalty(uint256 _tokenId, uint256 wethAmount) private returns (uint256) {
        uint256 feePercent = dbiliaToken.feePercent();
        (, uint16 percentage) = dbiliaToken.getRoyaltyReceiver(_tokenId);
        uint256 firstFee = wethAmount.mul(feePercent).div(feePercent + 1000);
        uint256 royalty = wethAmount.sub(firstFee).mul(percentage).div(100);
        _send(royalty, dbiliaToken.dbiliaTrust());
        return royalty;
    }

  /**
    * Send money to seller
    * Dbilia keeps it if seller is w2user
    *
    * @param sellerReceiveAmount total - (fee + royalty)
    * @param _isW3user w3user or w3user
    * @param _w3owner w3user EOA
    */
    function _sendToSeller(
        uint256 sellerReceiveAmount,
        bool _isW3user,
        address _w3owner
    )
        private
    {
        _send(sellerReceiveAmount, _isW3user ? _w3owner : dbiliaToken.dbiliaTrust());
    }

  /**
    * Low-level call methods instead of using transfer()
    *
    * @param _amount amount in ETH
    * @param _to receiver
    */
    function _send(uint256 _amount, address _to) private {
        weth.transfer(_to, _amount);
    }

  /**
    * Get current price of ETH to USD
    *
    */
    function getCurrentPriceOfETHtoUSD() public view returns (int256) {
        return getThePriceEthUsd() / 10 ** 8;
    }

    function setPasscode(bytes32 passcode_) external {
        require(msgSender() == address(dbiliaToken));
        passcode = passcode_;
    }

    /////// Data migration section //////////
    /**
        * Set price fiat info for a given tokenId
        *
        * @param _tokenId token id
        * @param _priceFiat priceFiat
        */
    function setTokenPriceFiat(uint256 _tokenId, uint256 _priceFiat) 
        external 
        onlyDbilia 
    {
        tokenPriceFiat[_tokenId] = _priceFiat;
    }

    /**
        * Set price fiat info for a given tokenId
        *
        * @param _tokenId token id
        * @param _onAuction onAuction
        */
    function setTokenOnAuction(uint256 _tokenId, bool _onAuction) 
        external 
        onlyDbilia 
    {
        tokenOnAuction[_tokenId] = _onAuction;
    }
}
