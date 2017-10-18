/******************************************************************************\

file:   Invoices.sol
ver:    0.4.0
updated:17-Oct-2017
author: Darryl Morris
email:  o0ragman0o AT gmail.com

A SandalStraps compliant factory to create invoice payment channels.


Contracts:
- Invoice
    SandalStraps compliant
    Created by Invoices contract.
    Client sends money to this contract
    Payments are withdrawn to Invoices contract
    
- Invoices
    SandalStraps compliant
    Created by InvoicesFactory
    Central collector and Registrar of all invoices it creates.
    Charges 0.2% fee from payments, claimable by InvoicesFactory owner
    
- InvoicesFactory
    SandalStraps complaint factory for Invoices

This software is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
See MIT Licence for further details.
<https://opensource.org/licenses/MIT>.
    
Release notes
-------------
* Using Sandalstraps 0.4.0
* Using Withdrawable 0.4.0 API
\******************************************************************************/

pragma solidity ^0.4.13;

import "https://github.com/o0ragman0o/SandalStraps/contracts/Registrar.sol";
import "https://github.com/o0ragman0o/Withdrawable/contracts/Withdrawable.sol";

//
// Invoice is a product of Invoices used to channel payments from its unique
// contract address to the Invoices payment collector. 
//
contract Invoice
{
    bytes32 constant public VERSION = "Invoice v0.4.0";
    
    // Payments state used to prevent contract destruction after a payment
    bool noPayments = true;
    
    /// @return The contract owner address, being the creating Invoices contract instance
    address public owner;
    
    /// @return The SandalStraps registration name
    bytes32 public regName;
    
    /// @return A SandalStraps resource
    bytes32 public resource;
    
    // The outstanding amount at last withdrawAll()
    uint outstanding;

    /// @dev Logged upon receiving a deposit
    /// @param _from The address from which value has been recieved
    /// @param _value The value of ether received
    event Deposit(address indexed _from, uint _value);
    
    /// @dev Logged upon a withdrawal
    /// @param _by the address of the withdrawer
    /// @param _to Address to which value was sent
    /// @param _value The value in ether which was withdrawn
    event Withdrawal(address indexed _by, address indexed _to, uint _value);

    /// @notice Create a new Invoice for invoice `_invoiceHash` with value of `_value`
    /// @param _value The value to be paid in ether.
    function Invoice(bytes32 _regName, bytes32 _resource, uint _value)
        public
    {
        owner = msg.sender;
        regName = _regName;
        resource = _resource;
        outstanding = _value;
    }
    
    /// @return The outstanding payments amount
    function amountDue()
        public
        view
        returns (uint)
    {
        return outstanding - this.balance;
    }
    
    /// @dev Accepts trivial transaction payments
    function ()
        public
        payable
    {
        if (msg.value > 0) {
            require(this.balance <= outstanding);
            Deposit(msg.sender, msg.value);
        }
    }
    
    /// @dev To withdraw accumulated payments
    /// @return Boolean success value
    function withdrawAll()
        public
        returns (bool)
    {
        if (this.balance > 0 && noPayments) delete noPayments;
        outstanding -= this.balance;
        Withdrawal(msg.sender, owner, this.balance);
        owner.transfer(this.balance);
        return true;
    }
    
    /// @notice Change the resource to `_resource`
    /// @param _resource A key or short text to be stored as the resource.
    /// @return Boolean success value
    function changeResource(bytes32 _resource)
        public
        returns (bool)
    {
        require(msg.sender == owner);
        // Cannot change invoice terms after a payment has been received
        require(noPayments);
        resource = _resource;
        return true;
    }

    /// @dev An invoice can only be cancelled by calling 
    /// `Invoices.cancelInvoice()` if it has not yet recieved payments.
    function destroy()
        public
    {
        require(msg.sender == owner);
        // An invoice cannot be destroyed if a payment has been recieved
        require(this.balance == 0 && noPayments);
        selfdestruct(msg.sender);
    }
}


//
// Invoices is the invoice creator and payment collector.
//
contract Invoices is Registrar, WithdrawableMinItfc {
    
    bytes32 constant public VERSION = "Invoices v0.4.0";
    
    /// @return Commission divisor of 0.2% of payments for developer commission
    uint constant COMMISSION_DIV = 500;

    /// @return The address which created this instance 
    address public creator;

    /// @dev Logged when a new invoice is created
    /// @param _kAddr The address of the invoice contract
    /// @param _value ether value of payment due to the invoice contract
    event NewInvoice(address indexed _kAddr, uint _value);

    function Invoices(address _creator, bytes32 _regName, address _owner)
        public
        Registrar(_creator, _regName, _owner)
    {
            creator = msg.sender;
    }
    
    /// @dev Default is payable
    function ()
        public
        payable
    {
        if (msg.value > 0) {
            Deposit(msg.sender, msg.value);
        }
    }
    
    /// @param _addr An addres to return an ether balance for
    /// @return the ether balance of owner or commission wallet
    function etherBalanceOf(address _addr)
        public
        view
        returns (uint)
    {
        return
            _addr == owner ? this.balance - this.balance / COMMISSION_DIV :
            _addr == creator ? this.balance / COMMISSION_DIV :
            0;
    }
    
    /// @notice Create a new invoice `_regName` for `_value` ether
    /// @param _regName A Sandalstraps registry name
    /// @param _value A value in ether
    function newInvoice(bytes32 _regName, bytes32 _resource, uint _value)
        public
        onlyOwner
        returns (address kAddr_)
    {
        address invoice = new Invoice(_regName, _resource, _value);
        add(invoice);
        NewInvoice(invoice, _value);
        kAddr_ = invoice;
    }
    
    /// @notice Change resource of invoice `_kAddr` to `_resource`
    /// @param _kAddr the address of an invoice
    /// @param _resource A resource. e.g. Swarm hash.
    /// @return success boolean
    function changeResourceOf(address _kAddr, bytes32 _resource)
        public
        onlyOwner
        returns (bool)
    {
        return RegBase(_kAddr).changeResource(_resource);
    }
    
    /// @notice Cancel invoice at address `_kAddr`
    /// @param _kAddr An invoice address
    function cancelInvoice(address _kAddr)
        public
        onlyOwner
        returns (bool)
    {
        remove(_kAddr);
        Invoice(_kAddr).destroy();
        return true;
    }
    
    /// @notice Withdraw received payments to owner and commission wallet
    /// @dev will pay out owner an commision wallet
    /// @return Boolean success value
    function withdrawAll()
        public
        returns (bool)
    {
        Withdrawal(msg.sender, creator, this.balance / COMMISSION_DIV);
        Withdrawal(msg.sender, owner, this.balance - this.balance / COMMISSION_DIV);
        creator.transfer(this.balance / COMMISSION_DIV);
        owner.transfer(this.balance);
        return true;
    }
}

contract InvoicesFactory is Factory
{
//
// Constants
//

    /// @return registrar name
    bytes32 constant public regName = "invoices";
    
    /// @return version string
    bytes32 constant public VERSION = "InvoicesFactory v0.4.0";

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
    function InvoicesFactory(
            address _creator, bytes32 _regName, address _owner)
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
        returns (address kAddr_)
    {
        require(_regName != 0x0);
        kAddr_ = address(new Invoices(msg.sender, _regName, _owner));
        Created(msg.sender, _regName, kAddr_);
    }
}