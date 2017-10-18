/******************************************************************************\

file:   MeteredPayments.sol
ver:    0.4.0
updated:17-Oct-2017
author: Darryl Morris (o0ragman0o)
email:  o0ragman0o AT gmail.com

This file is ancillary to the SandalStraps framework

`MeteredPayments` is a SandalStraps compliant contract to meter out periodic 
prefunded payments at a chosen rate. The recipient must call `withdrawAll()`
to pull the payments due up to that time.

Payments are setup and adjusted by calling 
`changePayment(_addr, _startTime, _period)`
Where `_addr` is recipient address
`_startTime` is the time when payments can being to be withdrawn
`_period` is the time in seconds over which the payment is metered out.
The rate of payment is calculated as the amount sent in `msg.value` / `_period`

Recipients call `withdrawAll()` to withdraw payments up to that time.
Payments can be pushed to recipients by calling `withdrawAllFor(_addr)`

Note: Loss of precision in the balance calculations means that small unclaimable
amounts of ether can accumulate in this contract until is it destroyed.

This software is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
See MIT Licence for further details.
<https://opensource.org/licenses/MIT>.

Release Notes
-------------
* Using Withdrawable 0.4.1

\******************************************************************************/

pragma solidity ^0.4.13;

import "https://github.com/o0ragman0o/SandalStraps/contracts/Factory.sol";
import "https://github.com/o0ragman0o/Withdrawable/contracts/Withdrawable.sol";

contract MeteredPayments is RegBase, WithdrawableMinItfc
{
    // Recipient structure records wei/second for payment seconds timeframe
    struct Recipient {
        // Payout period in seconds. Is consumed (reduced) upon withdrawal
        uint40 period;
        // Timestamp of last withdrawal
        uint40 lastWithdrawal;
        // Prevent the owner from changing the recipient address
        bool locked;
        // Wei per second payout rate
        uint168 rate;
    }
    
    bytes32 public constant VERSION = "MeteredPayments v0.4.0";
    
    /// @return 0.2% of payments for developer commission
    uint public constant COMMISION_DIV = 500;

    /// @return Commission wallet address
    address public commisionWallet;
    
    /// @return Total time owing across all payments
    uint40 public committedTime;
    
    /// @return Committed ether across all payments
    uint public committedPayments;
    
    /// @return Total ether paid out
    uint public paidOut;
    
    /// @return Recipient payment details
    mapping (address => Recipient) public recipients;

    /// @dev Logged on change of recipient address
    /// @param _old The addres which was changed
    /// @param _new The new recipient address
    event RecipientChanged(address indexed _old, address indexed _new);
    
    /// @dev Logged when a payment to an address is changed
    /// @param _addr A recipient address
    /// @param _value A commited value of ether
    /// @param _startDate The epoch time when the payments being
    /// @param _rate The payment release rate in wei/second
    event PaymentsChanged(
        address indexed _addr,
        uint indexed _value,
        uint40 indexed _startDate,
        uint _rate);
    
    /// @dev A SandalStraps compliant constructor
    function MeteredPayments(address _creator, bytes32 _regName, address _owner)
        public
        RegBase(_creator, _regName, _owner)
    {
        commisionWallet = _creator;
    }
    
    /// @dev For owner to destroy the contract if no payments are pending
    function destroy()
        public
    {
        require(committedPayments == 0);
        super.destroy();
    }
    
    /// @dev Returns the withdrawable amount of wei from a payment at time of call
    /// @param _addr A recipient address
    /// @return The released payment amount at that time of calling
    function etherBalanceOf(address _addr)
        public
        constant
        returns (uint)
    {
        Recipient storage recipient = recipients[_addr];
        
        if (uint40(now) < recipient.lastWithdrawal) return 0;
        uint40 period = uint40(now) - recipient.lastWithdrawal;
        period = period > recipient.period ? recipient.period : period;
        
        return period * recipient.rate;
    }
    
    /// @dev Returns maximum payout rate per second (includes payments which
    /// have not yet begun)
    function payoutRate()
        public
        constant
        returns(uint)
    {
        return committedPayments / committedTime;
    }
    
    /// @dev Returns the maximum daily payout rate.
    function dailyOutgoing()
        public
        constant
        returns (uint)
    {
        return 1 days * committedPayments / committedTime;
    }
    
    /// @notice Setup or change a precommited payment of `msg.sender` to `_addr`
    /// for a period of `_period` seconds after `_startTime`. Existing unclaimed
    /// payments will be sent to `_addr`. `msg.sender()` will be sent any
    /// refundable commitment. The commission wallet will be sent 0.02% of
    /// `msg.value`.
    /// @param _addr A recipient address
    /// @param _startTime and epoch start time
    /// @param _period A period in seconds over which the payment will be
    /// released after `_startTime`
    /// @return A boolean success value
    function changePayment(
            address _addr,
            uint40 _startTime,
            uint40 _period)
        public
        payable
        onlyOwner
        returns (bool)
    {
        Deposit(msg.sender, msg.value);

        // Full payment and commision is required
        Recipient storage recipient = recipients[_addr];

        // Discover oustanding payment period
        uint40 period = uint40(now) < recipient.lastWithdrawal ? 0 :
                        _period > recipient.period ? recipient.period : 
                        uint40(now) - recipient.lastWithdrawal;
        
        // Calculate unclaimed payments
        uint currentOwing = recipient.rate * period;
        // Calculate owner refund is adjusting payments down
        uint ownerRefund = recipient.rate * (recipient.period - period);
        // Calculate developer commision
        uint commision = msg.value / COMMISION_DIV;
        // Calculate final metered payment amount
        uint payment = msg.value - commision;
        // Payout rate wei/second
        uint rate =  payment / _period;

        // Write recipient state
        recipient.period = _period;
        recipient.rate = uint168(rate);
        recipient.lastWithdrawal= _startTime;

        committedTime += _period - period;
        committedPayments += payment - ownerRefund;
        
        PaymentsChanged(_addr, payment, _startTime, rate);

        // Refund owner any difference of previously commited payments
        intlWithdraw(this, owner, ownerRefund);
        // Pay commision
        intlWithdraw(this, commisionWallet, commision);
        // Pay outstanding payments to recipient (least trusted, do last);
        intlWithdraw(this, _addr, currentOwing);

        return true;
    }
    
    /// @notice Set recipient lock for `msg.sender` to `_lock`
    /// @param _lock The recipent address lock state
    /// @return Boolean success value
    function lock(bool _lock)
        public
        returns (bool)
    {
        recipients[msg.sender].locked = _lock;
        return true;
    }
    
    /// @notice Changes recipient payout address `_old` to `_new`.
    /// @dev Can be changed by owner or recipient.
    /// @param _old The existing recipient address
    /// @param _new The replacment recipient address
    /// @return 
    function changeAddress(address _old, address _new)
        public
        returns (bool)
    {
        require(msg.sender == _old
                || (msg.sender == owner && !recipients[_old].locked));
        recipients[_new] = recipients[_old];
        delete recipients[_old];

        RecipientChanged(_old, _new);
        return true;
    }
    
    /// @notice Withdraw the calling address's available balance
    /// @return Boolean success value
    function withdrawAll()
        public
        returns (bool)
    {
        address[] memory arr;
        arr[0] = msg.sender;
        return withdrawAllFor(arr);
    }

    /// @notice Push payments for an array of addresses
    /// @param _addrs An array of addresses to process withdrawals for
    /// @return Boolean success value
    function withdrawAllFor(address[] _addrs)
        public
        returns (bool)
    {
        Recipient memory recipient;
        for(uint i; i < _addrs.length; i++) {
            recipient = recipients[_addrs[i]];
            if (uint40(now) >= recipient.lastWithdrawal) {
                uint40 period = uint40(now) - recipient.lastWithdrawal;
                period = period > recipient.period ? recipient.period : period;
                
                uint value = period * recipient.rate;
                recipient.period -= period;
                recipient.lastWithdrawal = uint40(now);
                
                committedTime -= period;
                committedPayments -= value;
                
                recipients[_addrs[i]] = recipient;
                // Pay to recipient
                intlWithdraw(msg.sender, _addrs[i], value);
            }
        }
        return true;
    }
    
    function intlWithdraw(address _from, address _to, uint _value)
        internal
        returns (bool)
    {
        if (_value > 0) {
            Withdrawal(_from, _to, _value);
            paidOut += _value;
            _to.transfer(_value);
        }
    }
}


contract MeteredPaymentsFactory is Factory
{
//
// Constants
//

    bytes32 constant public regName = "meteredpayments";
    bytes32 constant public VERSION = "MeteredPaymentFactory v0.4.0";

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
    function MeteredPaymentsFactory(address _creator, bytes32 _regName, address _owner)
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
        kAddr_ = address(new MeteredPayments(this, _regName, _owner));
        Created(msg.sender, _regName, kAddr_);
    }
}


