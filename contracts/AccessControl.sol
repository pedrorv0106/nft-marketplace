// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "./EIP712MetaTransaction.sol";

abstract contract AccessControl is EIP712MetaTransaction {
    address public owner;
    address public dbiliaTrust;
    address public dbiliaFee;
    address public marketplace;
    bool public isMaintaining = false;

    // List of authorized addresses
    mapping(address => bool) public _authorizedAddressList;

    // Used to protect public function
    bytes32 internal passcode = "protected";

    constructor() {
        owner = msgSender();
    }

    modifier onlyCEO {
        require(msgSender() == owner, "caller is not CEO");
        _;
    }

    modifier isActive {
        require(!isMaintaining, "it's currently maintaining");
        _;
    }

    modifier onlyDbilia() {
        require(msg.sender == owner || _authorizedAddressList[msg.sender] == true, 
        "caller is not one of Dbilia accounts");
        _;
    }

    // Protect public function with passcode
    modifier verifyPasscode(bytes32 _passcode) {
        require(_passcode == keccak256(bytes.concat(passcode, bytes20(address(msgSender())))), "invalid passcode");
        _;
    }

    function changeOwner(address _newOwner) onlyCEO external {
        if (_newOwner != address(0)) {
            owner = _newOwner;
        }
    }

    function changeDbiliaTrust(address _newDbiliaTrust) onlyCEO external {
        if (_newDbiliaTrust != address(0)) {
            dbiliaTrust = _newDbiliaTrust;
            _authorizedAddressList[_newDbiliaTrust] = true;
        }
    }

    function changeDbiliaFee(address _newDbiliaFee) onlyCEO external {
        if (_newDbiliaFee != address(0)) {
            dbiliaFee = _newDbiliaFee;
        }
    }

    function changeMarketplace(address _newMarketplace) onlyCEO external {
        if (_newMarketplace != address(0)) {
            marketplace = _newMarketplace;
            _authorizedAddressList[_newMarketplace] = true;
        }
    }

    // Add address to the authorized list
    function addAuthorizedAddress(address _addr) onlyCEO external {
        if (_addr != address(0)) {
            _authorizedAddressList[_addr] = true;
        }
    }

    // Remove address from the authorized list
    function revokeAuthorizedAddress(address _addr) onlyCEO external {
        if (_addr != address(0)) {
            _authorizedAddressList[_addr] = false;
        }
    }

    // Check if address is authorized
    function isAuthorizedAddress(address _addr) external view returns (bool) {
        return _addr == owner || _authorizedAddressList[_addr];
    }

    function updateMaintaining(bool _isMaintaining) onlyCEO external {
        isMaintaining = _isMaintaining;
    }
}
