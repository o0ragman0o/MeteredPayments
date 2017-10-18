# PayPipes

PayPipes is an ether payments and accounting suite of tools built on (and for) 
the [SandalStraps](https://github.com/o0ragman0o/SandalStraps) framework and
using the [Withdrawable](https://github.com/o0ragman0o/Withdrawable) API.
It consists of a number of generic utility contracts to channelling ether into
and out of contracts using the `withdrawAll()` for pull payments and bulk
withdrawer `withdrawAllFor([])` for batching push payments.

These contracts accept trivial payments to their default functions which are
written to not manipulate state which would risk reverting batched or chained
transactions.

### `DepositWithdrawAll`
Is a simple hold and forward contract which can be used
as a permenant published address while the actual recipient address can be
changed at will by the contract's owner.

### `Forwarder`
Can be used as a proxy address for a forwarding address. Calls and call data
made to this will be piped to the forwarding address as an internal transaction.
The forwarding address will see the proxy address as `msg.sender` and not the
origional caller.

### `PayableERC20`
Is an ERC20 compliant token contract which can recieve ether
payments from which holders can withdraw a share proportional to their token
balance. It accounts for the high likelyhood of orphaned tokens their
respective ether payments by allowing anyone to 'salvage' (claim) tokens which
have not been touched for a period of 3 years.  If the orphaned account is that
of the contract owner, then contract ownership is also transferred to the
claimant.  The contract owner has the ability to prevent or allow the contract
to accept deposits, set optional name, set optional symbol, change owner, change
resource and destroy (on low balance).

The intended use case is for private or small group holdings such as royalty
sharing, family trusts and basic budgeting into various accounts. For this
reason the tokens supply is fixed at 100.000000 tokens for intuitive percentile
splits.

**WARNING:** The ether balances are a dynamic calculations. These tokens are not
suitable for trading on centralised exchanges or transferred through state
channels.

### `Invoices`
Invoices is an integrate invoice factory and registrar.  New invoices can be
created providing unique addresses from which all payments can be withdrawn back
to the Invoices contract and withdrawn again to the contract owner.

### `MeteredPayments`
This contract provisions a system where bulk payments can be committed to
recipients but which the recipients can only withdraw from over a period of time
begining from some starting date. The owner can change the payment terms and
amounts but this will pay the recipient any unclaimed payments up to that time.
Both the owner and the recipient can change a recipient address unless the
recipient explicitly puts a lock on their address after which only they can
change it.

### `EscrowingITO`
This contract is a generic token fund raiser. Once created, it can be
initialized with a minimum fund cap, start date and fund wallet. A maximum cap
is set at 10x the minimum. Funding runs for up to 28 days or until `finalizeITO`
is successfully called once the minimum cap is reached. Token transfers are
blocked until the ITO is successful. If the minimum cap is not reached, funders
can withdraw their funds. The owner may elect to abort the ITO at any time
before it is finalised.

### `PassPurse` (in progress)
A factory for simple password permissioned ether contracts which `selfdestruct`
to the senders address when provided the correct password.

### `ProjectFundRaiser` (in progress)
This is a `PayableERC` and `EscrowingITO` by which funders can recieve shares
of returned payments.

### Utility Tokens (in progress)
Utility tokens are ERC20 contracts that can be aware of and interact with other
contracts through the standard `transfer()` functions.

### EthenianDAO (in progress)
Modular contract Liquid Democracy building on top of the SandalStraps and
PayPipes frameworks.


### Commissions
In order to help fund this development work, these contracts collect a 0.2%
commission upon the ether cash flows that pass through them. These commissions
will be withdrawn back through the respective contract factories into the
official SandalStraps `PayableERC20` contract named `Fee Parking (FPK)`.

instances -> factories -> SandalStraps -> FeeParking -> FPK token holders
