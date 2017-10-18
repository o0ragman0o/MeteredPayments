/*
file:   PayableERC20.sol
ver:    0.4.2
updated:17-Oct-2017
author: Darryl Morris
email:  o0ragman0o AT gmail.com

A payable ERC20 token where payments are split according to token holdings.

WARNINGS:
* These tokens are not suitible for trade on a centralised exchange.
Doing so will result in permanent loss of ether.
* These tokens may not be suitable for state channel transfers as no ether
balances will be accounted for

The supply of this token is a constant of 100,000,000 which can intuitively
represent 100.000000% to be distributed to holders.


This software is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
See MIT Licence for further details.
<https://opensource.org/licenses/MIT>.

Release notes
-------------
* Changed to withdrawAll functions to `withdrawAll()`,`withdrawAllTo()`,
  `withdrawAllFor()` and `withdrawAllFrom()`
* Using SandalStraps 0.4.0

*/

pragma solidity ^0.4.13;

import "https://github.com/o0ragman0o/Math/Math.sol";
import "https://github.com/o0ragman0o/ReentryProtected/ReentryProtected.sol";
import "https://github.com/o0ragman0o/SandalStraps/contracts/Factory.sol";
import "https://github.com/o0ragman0o/Withdrawable/contracts/Withdrawable.sol";

// ERC20 Standard Token Abstract including state variables
contract ERC20Abstract
{
/* Structs */

/* State Valiables */

    /// @return
    uint public decimals;
    
    /// @return Token symbol
    string public symbol;
    
    /// @return Token Name
    string public name;

/* Events */

    /// @dev Logged when tokens are transferred.
    /// @param _from The address tokens were transferred from
    /// @param _to The address tokens were transferred to
    /// @param _value The number of tokens transferred
    event Transfer(
        address indexed _from,
        address indexed _to,
        uint256 _value);

    /// @dev Logged when approve(address _spender, uint256 _value) is called.
    /// @param _owner The owner address of spendable tokens
    /// @param _spender The permissioned spender address
    /// @param _value The number of tokens that can be spent
    event Approval(
        address indexed _owner,
        address indexed _spender,
        uint256 _value);

/* Modifiers */

/* Function Abstracts */

    /// @return The total supply of tokens
    function totalSupply() public view returns (uint);
    
    /// @param _addr The address of a token holder
    /// @return The amount of tokens held by `_addr`
    function balanceOf(address _addr) public view returns (uint);

    /// @param _owner The address of a token holder
    /// @param _spender the address of a third-party
    /// @return The amount of tokens the `_spender` is allowed to transfer
    function allowance(address _owner, address _spender) public view
        returns (uint);
        
    /// @notice Send `_amount` of tokens from `msg.sender` to `_to`
    /// @param _to The address of the recipient
    /// @param _amount The amount of tokens to transfer
    function transfer(address _to, uint256 _amount) public returns (bool);

    /// @notice Send `_amount` of tokens from `_from` to `_to` on the condition
    /// it is approved by `_from`
    /// @param _from The address of the sender
    /// @param _to The address of the recipient
    /// @param _amount The amount of tokens to transfer
    function transferFrom(address _from, address _to, uint256 _amount)
        public returns (bool);

    /// @notice `msg.sender` approves `_spender` to spend `_amount` tokens on
    /// its behalf
    /// @param _spender The address of the approved spender
    /// @param _amount The amount of tokens to transfer
    function approve(address _spender, uint256 _amount) public returns (bool);
}


// contract PayableERC20Abstract is ERC20Interface, WithdrawableMinItfc
contract PayableERC20Abstract is ERC20Abstract, WithdrawableMinItfc
{
/* Constants */

    // 100.000000% supply
    uint64 constant TOTALSUPPLY = 100000000;
    
    // 6 decimal places
    uint8 constant DECIMALS = 6;
    
    // 0.2% of tokens are awarded to creator
    uint64 constant COMMISION = 200000;
    
    /// @return Tokens untouched for 1 year can be redistributed
    // uint64 public constant ORPHANED_PERIOD = 3 years;
    uint64 public constant ORPHANED_PERIOD = 3 minutes;

/* Structs */

    struct Holder {
        // Token balance.
        uint64 balance;
        
        // Last time the account was touched.
        uint64 lastTouched;
        
        // The totalDeposits at the time of last claim.
        uint lastSumDeposits;
        
        // Ether balance
        uint etherBalance;
        
        // Thirdparty sender allownaces
        mapping (address => uint) allowed;
    }

/* State Valiables */

    /// @return Whether the contract is accepting payments
    bool public acceptingDeposits;

    // Mapping of holder accounts
    mapping (address => Holder) holders;

    event AcceptingDeposits(bool indexed _accept);
    
/* Events */

    /// @dev Triggered upon a redistribution of untouched tokens
    /// @param _from The orphaned address
    /// @param _to The claiming address
    /// @param _amount The amount of tokens salvaged
    /// @param _value The value of ether salvaged
    event OrphanedTokensClaim(
        address indexed _from,
        address indexed _to,
        uint _amount,
        uint _value);

    /// @dev Logged upon calling `callAsContract()`
    /// @param _kAddr A contract address that was called
    /// @param _value A value of ether sent with the transaction
    /// @param _data Call data sent with the transaction
    event ExternalCall(
        address indexed _kAddr,
        uint _value,
        bytes _data);

/* Modifiers */

/* Function Abstracts */

    /// @dev Deposits only receivable by the default account. Minimum gas is
    /// required as no state is mutated. 
    function() public payable;

    /// @notice Set the token symbol to `_symbol`. This can only be done once!
    /// @param _symbol The chosen token symbol
    /// @return success
    function setSymbol(string _symbol) public returns (bool);
    
    /// @return Timestamp when an account is considered orphaned
    function orphanedAfter(address _addr) public constant returns (uint64);

    /// @notice Claim tokens of orphaned account `_addr`
    /// @param _addr Address of orphaned account
    /// @return _bool
    function salvageOrphanedTokens(address _addr) public returns (bool);
    
    /// @notice Refresh the time to orphan of holder account `_addr`
    /// @param _addr the address of a holder
    /// @return success
    function touch(address _addr) public returns (bool);

    /// @notice Transfer `_value` tokens from ERC20 contract at `_addr` to `_to`
    /// @param _kAddr Address of and external ERC20 contract
    /// @param _to An address to transfer external tokens to.
    /// @param _value number of tokens to be transferred
    function transferExternalTokens(address _kAddr, address _to, uint _value)
        public returns (bool);
}


contract PayableERC20 is
    ReentryProtected,
    RegBase,
    PayableERC20Abstract
{
    using Math for uint;
    using Math64 for uint64;
    
/* Constants */
    
    /// @return Contract version constant
    bytes32 public constant VERSION = "PayableERC20 v0.4.2";

/* State Valiables */

    // The summation of ether deposited up to when a holder last triggered a 
    // claim
    uint sumDeposits;
    
    // The contract balance at last claim (transfer or withdraw)
    uint lastBalance;

/* Functions Public non-constant*/

    // This is a SandalStraps Framework compliant constructor
    function PayableERC20(address _creator, bytes32 _regName, address _owner)
        public
        RegBase(_creator, _regName, _owner)
    {
        _creator = _creator == 0x0 ? owner : _creator;
        decimals = DECIMALS;
        acceptingDeposits = true;
        holders[owner].balance = TOTALSUPPLY.sub(COMMISION);
        holders[owner].lastTouched = uint64(now);
        Transfer(0x0, owner, TOTALSUPPLY.sub(COMMISION));
        holders[_creator].balance = holders[_creator].balance.add(COMMISION);
        holders[_creator].lastTouched = uint64(now);
        Transfer(0x0, _creator, COMMISION);
    }

    /// @dev Deposits only receivable by the default account. Minimum gas is
    /// required as no state is mutated. 
    function()
        public
        payable
    {
        require(acceptingDeposits);
        Deposit(msg.sender, msg.value);
    }
    
//
// Getters
//

    /// @return Standard ERC20 token supply
    function totalSupply()
        public
        view
        returns (uint)
    {
        return TOTALSUPPLY;
    }
    
    /// @param _addr An address to discover token balance
    /// @return Token balance for `_addr` 
    function balanceOf(address _addr)
        public
        view
        returns (uint)
    {
        return holders[_addr].balance;
    }
    
    /// @param _addr An address to discover ether balance
    /// @return the withdrawable ether balance of `_addr`
    function etherBalanceOf(address _addr)
        public
        view
        returns (uint)
    {
        return holders[_addr].etherBalance.add(claimableEther(holders[_addr]));
    }

    // Standard ERC20 3rd party sender allowance getter
    function allowance(address _owner, address _spender)
        public
        view
        returns (uint remaining_)
    {
        return holders[_owner].allowed[_spender];
    }

    /// @param _addr An address to enquire orphan date
    /// @return An epoch time after which the account is orphaned
    function orphanedAfter(address _addr)
        public
        view
        returns (uint64)
    {
        return holders[_addr].lastTouched.add(ORPHANED_PERIOD);
    }
    
    /// @param _addr An address to enquire current orphan state
    /// @return Boolean value as to the whether the address is orphaned or not
    function isOrphaned(address _addr)
        public
        view
        returns (bool)
    {
        return now > holders[_addr].lastTouched.add(ORPHANED_PERIOD);
    }

//
// ERC20 and Orphaned Tokens Functions
//

    // ERC20 standard tranfer. Send _value amount of tokens to address _to
    // Reentry protection prevents attacks upon the state
    function transfer(address _to, uint _amount)
        public
        noReentry
        returns (bool)
    {
        xfer(msg.sender, _to, uint64(_amount));
        return true;
    }

    // ERC20 standard tranferFrom. Send _value amount of tokens from address 
    // _from to address _to
    // Reentry protection prevents attacks upon the state
    function transferFrom(address _from, address _to, uint _amount)
        public
        noReentry
        returns (bool)
    {
        // Validate and adjust allowance
        uint64 amount = uint64(_amount);
        require(amount <= holders[_from].allowed[msg.sender]);
        
        // Adjust spender allowance
        holders[_from].allowed[msg.sender] = 
            holders[_from].allowed[msg.sender].sub(amount);
        
        xfer(_from, _to, amount);
        return true;
    }

    // Overload the ERC20 xfer() to account for unclaimed ether
    function xfer(address _from, address _to, uint64 _amount)
        internal
    {
        // Cache holder structs from storage to memory to avoid excessive SSTORE
        Holder memory from = holders[_from];
        Holder memory to = holders[_to];
        
        // Cannot transfer to self or the contract
        require(_from != _to);
        require(_to != address(this));

        // Validate amount
        require(_amount > 0 && _amount <= from.balance);
        
        // Update party's outstanding claims
        claimEther(from);
        claimEther(to);
        
        // Transfer tokens
        from.balance = from.balance.sub(_amount);
        to.balance = to.balance.add(_amount);

        // Commit changes to storage
        holders[_from] = from;
        holders[_to] = to;

        Transfer(_from, _to, _amount);
    }

    // Approves a third-party spender
    // Reentry protection prevents attacks upon the state
    function approve(address _spender, uint _amount)
        public
        noReentry
        returns (bool)
    {
        require(holders[msg.sender].balance != 0);
        
        holders[msg.sender].allowed[_spender] = uint64(_amount);
        Approval(msg.sender, _spender, _amount);
        return true;
    }

    /// @notice Transfer `_amount` ERC20 tokens from `_kAddr` owned by this
    /// address to address `_to`
    /// @param _kAddr Address of an ERC20 token contract
    /// @param _to Recipient address
    /// @param _amount An amount of tokens
    /// @return Boolean success value
    function transferExternalTokens(address _kAddr, address _to, uint _amount)
        public
        onlyOwner
        returns(bool)
    {
        return ERC20Abstract(_kAddr).transfer(_to, _amount);
    }

    /// @notice Refresh the shelflife of account `_addr`
    /// @param _addr The address of a holder
    function touch(address _addr)
        public
        noReentry
        returns (bool)
    {
        require(holders[msg.sender].balance > 0);
        holders[_addr].lastTouched = uint64(now);
        return true;
    }

    /// @notice Claim tokens and ther of `_addr`
    /// @param _addr The holder address of orphaned tokens
    /// @return Boolean success value
    function salvageOrphanedTokens(address _addr)
        public
        noReentry
        returns(bool)
    {
        // Claim ownership if owner address itself has been orphaned
        if (now > orphanedAfter(owner)) {
            ChangedOwner(owner, msg.sender);
            owner = msg.sender;
        }
        
        // Caller must be owner
        require(msg.sender == owner);
        
        // Orphan account must have exceeded shelflife
        require(now > orphanedAfter(_addr));
        
        // Log claim
        OrphanedTokensClaim(
            _addr,
            msg.sender,
            holders[_addr].balance,
            holders[_addr].etherBalance);

        // Transfer orphaned tokens
        xfer(_addr, msg.sender, holders[_addr].balance);
        
        // Transfer ether. Orphaned ether was claimed during token transfer.
        holders[msg.sender].etherBalance = 
            holders[msg.sender].etherBalance.add(holders[_addr].etherBalance);
        
        // Delete ophaned account
        delete holders[_addr];

        return true;
    }
    
//
// Deposit processing function
//

    /// @return Total deposits made to the contract to date
    function deposits()
        public
        constant
        returns (uint)
    {
        return sumDeposits.add(this.balance - lastBalance); 
    }
    
    /// @notice Set the payment acceptance state to `_accept`
    /// @param _accept accept to deny payments to contract
    /// @return Boolean success value
    function acceptDeposits(bool _accept)
        public
        noReentry
        onlyOwner
        returns (bool)
    {
        acceptingDeposits = _accept;
        AcceptingDeposits(_accept);
        return true;
    }

//
// Withdrawal processing functions
//

    /// @notice Withdraw the calling address's available balance
    /// @return Boolean success value
    function withdrawAll()
        public
        returns (bool)
    {
        return intlWithdraw(msg.sender, msg.sender);
    }

    /// @notice Push payments for an array of addresses
    /// @param _addrs An array of addresses to process withdrawals for
    /// @return Boolean success value
    function withdrawAllFor(address[] _addrs)
        public
        returns (bool)
    {
        for(uint i; i < _addrs.length; i++) {
            intlWithdraw(_addrs[i], _addrs[i]);
        }
        return true;
    }

    /// @notice Have contract pull payment from `_kAddr`
    /// @param _kAddr A Withdrawlable contract
    /// @return Booleanbalance.
    // Reentry is prevented to all but the default function to recieve payment.
    function withdrawAllFrom(address _kAddr)
        public
        preventReentry
        returns (bool)
    {
        return WithdrawableAbstract(_kAddr).withdrawAll();
    }
    
    // Account withdrawl function
    function intlWithdraw(address _from, address _to)
        internal
        preventReentry
        returns (bool)
    {
        Holder memory holder = holders[_from];
        claimEther(holder);
        
        // check balance and withdraw on valid amount
        uint value = holder.etherBalance;
        require(value > 0);
        holder.etherBalance = 0;
        holders[_from] = holder;
        
        // snapshot adjusted contract balance
        lastBalance = lastBalance.sub(value);
        
        Withdrawal(_from, _to, value);
        _to.transfer(value);
        return true;
    }

//
// Payment distribution functions
//

    // Ether balance delta for holder's unclaimed ether
    // function claimableDeposits(address _addr)
    function claimableEther(Holder holder)
        internal
        view
        returns (uint)
    {
        return uint(holder.balance).mul(
            deposits().sub(holder.lastSumDeposits)
            ).div(TOTALSUPPLY);
    }
    
    // Claims share of ether deposits
    // before withdrawal or change to token balance.
    function claimEther(Holder holder)
        internal
        returns(Holder)
    {
        // Update unprocessed deposits
        if (lastBalance != this.balance) {
            sumDeposits = sumDeposits.add(this.balance.sub(lastBalance));
            lastBalance = this.balance;
        }

        // Claim share of deposits since last claim
        holder.etherBalance = holder.etherBalance.add(claimableEther(holder));
        
        // Snapshot deposits summation
        holder.lastSumDeposits = sumDeposits;

        // touch
        holder.lastTouched = uint64(now).add(ORPHANED_PERIOD);

        return holder;
    }

//
// Contract managment functions
//

    /// @notice Owner can selfdestruct the contract on the condition it has
    /// near zero balance
    function destroy()
        public
        noReentry
        onlyOwner
    {
        // must flush all ether balances first. But imprecision may have
        // accumulated  under 100,000,000 wei
        require(this.balance <= 100000000);
        selfdestruct(msg.sender);
    }

    /// @notice Set the token symbol to `_symbol`. This can only be set once
    /// @param _symbol The token symbol
    /// @return Boolean success value
    function setSymbol(string _symbol)
        public
        onlyOwner
        noReentry
        returns (bool)
    {
        require(bytes(symbol).length == 0);
        symbol = _symbol;
        return true;
    }

    /// @notice Set the token name to `_name`. This can only be set once
    /// @param _name The token symbol
    /// @return Boolean success value
    function setName(string _name)
        public
        onlyOwner
        noReentry
        returns (bool)
    {
        require(bytes(name).length == 0);
        name = _name;
        return true;
    }
    
    /// @dev For low level calls to external contracts
    /// @notice Call external contract at `_kAddr` sending `msg.value` and data
    /// `_data`
    /// @param _kAddr A contract address
    /// @param _data Call data sent to contract
    /// @return boolean success value
    function callAsContract(address _kAddr, bytes _data)
        public
        payable
        onlyOwner
        preventReentry
        returns (bool)
    {
        ExternalCall(_kAddr, msg.value, _data);
        return _kAddr.call.value(msg.value)(_data);
    }
}


contract PayableERC20Factory is Factory
{
//
// Constants
//

    bytes32 constant public regName = "payableerc20";
    bytes32 constant public VERSION = "PayableERC20Factory v0.4.2";

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
    function PayableERC20Factory(address _creator, bytes32 _regName, address _owner)
        public
        Factory(_creator, regName, _owner)
    {
        _regName; // Not passed to super. Quiet compiler warning
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
        returns(address kAddr_)
    {
        require(_regName != 0x0);
        _owner = _owner == 0x0 ? msg.sender : _owner;
        kAddr_ = address(new PayableERC20(this, _regName, _owner));
        Created(msg.sender, _regName, kAddr_);
    }
}

