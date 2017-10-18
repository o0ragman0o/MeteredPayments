/******************************************************************************\

file:   Forwarder.sol
ver:    0.4.0
updated:17-Oct-2017
author: Darryl Morris (o0ragman0o)
email:  o0ragman0o AT gmail.com

This file is part of the SandalStraps framework

CallForwarder acts as a proxy address for call pass-through of call data, gas
and value.

This software is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
See MIT Licence for further details.
<https://opensource.org/licenses/MIT>.

Release Notes
-------------
* Name change from 'Redirector' to 'Forwarder'
* Changes state name from 'payTo' to 'forwardTo'

\******************************************************************************/

pragma solidity ^0.4.13;

import "https://github.com/o0ragman0o/SandalStraps/contracts/Registrar.sol";
import "https://github.com/o0ragman0o/Withdrawable/contracts/Withdrawable.sol";

contract PassPurse
{
    bytes27 pass;
    uint40 public expiry;
    address public owner;
    
    event Deposit(address indexed _from, uint _value);
    
    function PassPurse(bytes32 _pass, uint _expiry)
        public
        payable
    {
        pass = bytes27(_pass);
        expiry = uint40(_expiry);
        owner = msg.sender;
        if (msg.value > 0) {
            Deposit(msg.sender, msg.value);
        }
    }
    
    function ()
        public
        payable
    {
        if (msg.value > 0) {
            Deposit(msg.sender, msg.value);
        }
    }
    
// TODO: Prone to front running
    function sweep(bytes32 _pass)
        public
    {
        address recip = now > expiry ? owner :
            bytes27(keccak256(_pass)) == pass ? msg.sender :
            0x0;
        if (recip != 0x0) selfdestruct(recip);
    }
}

contract PassPurses is RegBase, Withdrawable
{
//
// Constants
//

    /// @return The contract's version constant
    bytes32 constant public VERSION = "PassPurse v0.4.0";

//
// State
//

    /// @return The forwarding address.
    address[] public purses;
    
//
// Events
//
    
    /// @dev Logged upon forwarding a transaction
    /// @param _kAddr The purse address
    /// @param _pass The hash of the password
    event NewPurse(address indexed _kAddr, bytes27 _pass);

//
// Functions
//

    /// @dev A SandalStraps compliant constructor
    /// @param _creator The creating address
    /// @param _regName The contracts registration name
    /// @param _owner The owner address for the contract
    function PassPurses(address _creator, bytes32 _regName, address _owner)
        public
        RegBase(_creator, _regName, _owner)
    {
        // forwardTo will be set to msg.sender of if _owner == 0x0 or _owner
        // otherwise
    }
    
    /// @dev Transactions are unconditionally forwarded to the forwarding address
    function ()
        public
        payable 
    {
        if(msg.value > 0) {
            Deposit(msg.sender, msg.value);
        }
    }

    function createNew(bytes27 _pass, uint _expiry)
        public
        payable
        returns (address kAddr_)
    {
        kAddr_ = address(new PassPurse(_pass, _expiry));
        purses.push(kAddr_);
        NewPurse(kAddr_, _pass);
    }
    
    function withdrawAll()
        public
        returns (bool)
    {
        owner.transfer(this.balance);
    }
    
}


contract PassPursesFactory is Factory
{
//
// Constants
//

    /// @return registrar name
    bytes32 constant public regName = "passpurses";
    
    /// @return version string
    bytes32 constant public VERSION = "PassPursesFactory v0.4.0";

//
// Functions
//

    /// @param _creator The calling address passed through by a factory,
    /// typically msg.sender
    /// @param _regName A static name referenced by a Registrar
    /// @param _owner optional owner address if creator is not the intended
    /// owner
    /// @dev On 0x0 value for _owner or _creator, ownership precedence is:
    /// `_owner` else `_creator` else msg.sender
    function PassPursesFactory(
        address _creator, bytes32 _regName, address _owner)
            public
        Factory(_creator, regName, _owner)
    {
        _regName; // Not passed to super. quite compiler warning
    }

    /// @notice Create a new product contract
    /// @param _regName A unique name if the the product is to be registered in
    /// a SandalStraps registrar
    /// @param _owner An address of a third party owner.  Will default to
    /// msg.sender if 0x0
    /// @return kAddr_ The address of the new product contract
    function createNew(bytes32 _regName, address _owner)
        public
        payable
        pricePaid
        returns (address kAddr_)
    {
        kAddr_ = address(new PassPurses(msg.sender, _regName, _owner));
        Created(msg.sender, _regName, kAddr_);
    }
}

