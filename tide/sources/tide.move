module tide::tide {
  use sui::object::{Self, UID};
  use sui::coin::{Self, Coin};
  use sui::url::{Self, Url};
  use sui::tx_context::{Self, TxContext};
  use sui::balance::{Self, Balance};
  use sui::sui::SUI;
  use sui::transfer;
  use sui::event;

  const EWITHDRAWN_TOO_MUCH: u64 = 1001;
  

  public struct Vault<phantom CoinType> has key {
    id: UID,
    total_amount: u64,
    total_shares: u64, // Track total LP shares
    token_balance: Balance<CoinType>,
    locked_profit: u64,
    last_report: u64,
    locked_profit_degradation: u64,
    performance_fee: u64,
  }

  public struct VaultEvent has copy, drop {
        vault_id: address,
        amount: u64,
        timestamp: u64
    }

  public fun create_vault<CoinType>(ctx: &mut TxContext) {
      let vault = Vault<CoinType> {
        id: object::new(ctx),
            total_amount: 0,
            total_shares: 0,
            token_balance: balance::zero<CoinType>(),
            locked_profit: 0,
            last_report: 0,
            locked_profit_degradation: 100,
            performance_fee: 500
      };

      transfer::share_object(vault);
  }

  public fun deposit(
    ctx: &mut TxContext, 
    coin: Coin<SUI>, 
    vault: &mut Vault<SUI>
  ) {
    let amount = coin::value(&coin);
    let balance = coin::into_balance(coin);

    balance::join(&mut vault.token_balance, balance);
    vault.total_amount = vault.total_amount + amount;

    event::emit(VaultEvent {
            vault_id: object::uid_to_address(&vault.id),
            amount,
            timestamp: tx_context::epoch(ctx)
        });
  }

  public fun withdraw(
    vault: &mut Vault<SUI>,
    amount: u64,
    ctx: &mut TxContext

  ) {
    let unlocked = get_unlocked_amount(vault, ctx);
    assert!(amount <= unlocked, EWITHDRAWN_TOO_MUCH);

    vault.total_amount = vault.total_amount - amount;

    let shares_to_burn = (amount * vault.total_shares) / vault.total_amount;
    vault.total_shares = vault.total_shares - shares_to_burn;
  }

  public fun claim_fees(
   vault: &mut Vault<SUI>,
   treasury: address, 
   ctx: &mut TxContext
) {
   // Calculate fee based on unlocked profit
   let unlocked_amount = get_unlocked_amount(vault, ctx);
   let profit = unlocked_amount - vault.total_amount; 
   let fee_amount = (profit * vault.performance_fee) / 10000;

   // Reset locked profit after claiming
   vault.locked_profit = 0;
   vault.last_report = tx_context::epoch(ctx);

   // Transfer fee to treasury
   let fee_coin = coin::take<SUI>(&mut vault.token_balance, fee_amount, ctx);
   transfer::public_transfer(fee_coin, treasury);
   
}

  // Helper: Calculate withdrawable amount 
  fun get_unlocked_amount(vault: &Vault<SUI>, ctx: &mut TxContext): u64 {
   let duration = tx_context::epoch(ctx) - vault.last_report;
   let locked_ratio = 100 - (duration * vault.locked_profit_degradation);
   vault.total_amount - (vault.locked_profit * locked_ratio / 100)
  }
}

