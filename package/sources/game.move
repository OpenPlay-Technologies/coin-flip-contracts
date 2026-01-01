module coin_flip::game;

use coin_flip::constants::{
    head_result,
    tail_result,
    house_bias_result,
    place_bet_action,
    max_house_edge_bps,
    max_payout_factor_bps,
    min_stake_param_name,
    max_stake_param_name,
    house_edge_bps_param_name,
    payout_factor_bps_param_name
};
use coin_flip::context::{Self, CoinFlipContext};
use openplay_core::balance_manager::{BalanceManager, PlayCap};
use openplay_core::game_stats::GameStatistics;
use openplay_core::house::House;
use openplay_core::parameter_store::{Self, ParameterStore};
use openplay_core::registry::Registry;
use openplay_core::transaction::{Transaction, bet_checked, win_checked, min_transaction_amount};
use std::string::String;
use std::uq32_32::{UQ32_32, from_quotient, int_mul};
use sui::event::emit;
use sui::random::{Random, RandomGenerator};
use sui::table::{Self, Table};
use sui::transfer::share_object;

// === Errors ===
const EUnsupportedHouseEdge: u64 = 1;
const EUnsupportedPayoutFactor: u64 = 2;
const EUnsupportedStake: u64 = 3;
const EUnsupportedPrediction: u64 = 4;
const EUnsupportedAction: u64 = 5;
const EInvalidParamStore: u64 = 9;
const EMinStakeBelowMinTransaction: u64 = 10;

// === Structs ===
public struct GAME has drop {}

public struct Game has key {
    id: UID,
    param_store_id: ID,
    contexts: Table<ID, CoinFlipContext>,
}

public struct CoinFlipCap has key, store {
    id: UID,
}

public struct Interaction has copy, drop, store {
    balance_manager_id: ID,
    interact_type: InteractionType,
    transactions: vector<Transaction>,
}

public enum InteractionType has copy, drop, store {
    PLACE_BET { stake: u64, prediction: String },
}

// === Events ===
public struct InteractedWithGame has copy, drop {
    old_balance: u64,
    new_balance: u64,
    context: CoinFlipContext,
    balance_manager_id: ID,
}

fun init(_: GAME, ctx: &mut TxContext) {
    let admin = CoinFlipCap { id: object::new(ctx) };
    transfer::public_transfer(admin, ctx.sender());
}

// === Public-View Functions ===
public fun id(self: &Game): ID {
    self.id.to_inner()
}

public fun transactions(interaction: &Interaction): vector<Transaction> {
    interaction.transactions
}

public fun get_context(self: &mut Game, balance_manager: &BalanceManager): &CoinFlipContext {
    self.ensure_context(balance_manager.id());
    self.contexts.borrow(balance_manager.id())
}

// === Public-Mutative Functions ===
/// Interact entry function without referral
entry fun interact(
    self: &mut Game,
    registry: &Registry,
    param_store: &ParameterStore,
    game_stats: &mut GameStatistics,
    balance_manager: &mut BalanceManager,
    house: &mut House,
    play_cap: &PlayCap,
    interact_name: String,
    stake: u64,
    prediction: String,
    random: &Random,
    ctx: &mut TxContext,
) {
    let house_tx_cap = house.borrow_tx_cap(&mut self.id);

    // Make sure we have enough funds in the house to play this game
    let payout_factor = self.payout_factor(param_store);
    house.ensure_sufficient_funds(registry, max_payout(payout_factor, stake), ctx);

    // Interact with coin flip game and record any transactions made
    let mut interact = new_interact(
        interact_name,
        balance_manager.id(),
        prediction,
        stake,
    );
    let mut random_generator = random.new_generator(ctx);
    self.interact_int(param_store, &mut interact, &mut random_generator);

    // Process transactions by house
    let old_balance = balance_manager.balance();
    house.tx_admin_process_transactions_v2(
        registry,
        game_stats,
        house_tx_cap,
        balance_manager,
        &interact.transactions(),
        play_cap,
        ctx,
    );

    // Emit event
    let new_balance = balance_manager.balance();
    emit(InteractedWithGame {
        old_balance,
        new_balance,
        context: *self.get_context(balance_manager),
        balance_manager_id: balance_manager.id(),
    })
}

public fun share(game: Game) {
    share_object(game);
}

// === Admin Functions ===
public fun admin_create(
    _cap: &CoinFlipCap,
    registry: &mut Registry,
    min_stake: u64,
    max_stake: u64,
    house_edge_bps: u64,
    payout_factor_bps: u64,
    ctx: &mut TxContext,
): (Game, ParameterStore, GameStatistics) {
    assert!(house_edge_bps < max_house_edge_bps(), EUnsupportedHouseEdge);
    assert!(payout_factor_bps < max_payout_factor_bps(), EUnsupportedPayoutFactor);
    // Ensure min_stake is at least the minimum transaction amount required by openplay_core
    assert!(min_stake >= min_transaction_amount(), EMinStakeBelowMinTransaction);

    // Setup the param store
    let mut param_store = parameter_store::new(ctx);
    let param_store_id = param_store.id();
    param_store.add(min_stake_param_name(), min_stake);
    param_store.add(max_stake_param_name(), max_stake);
    param_store.add(house_edge_bps_param_name(), house_edge_bps);
    param_store.add(payout_factor_bps_param_name(), payout_factor_bps);

    let game = Game {
        id: object::new(ctx),
        param_store_id,
        contexts: table::new(ctx),
    };

    // Create game stats
    let stats = registry.init_stats(&game.id, ctx);

    (game, param_store, stats)
}

// === Public-Package Functions ===
public(package) fun interact_int(
    self: &mut Game,
    param_store: &ParameterStore,
    interaction: &mut Interaction,
    rand: &mut RandomGenerator,
) {
    // Validate the interaction
    self.validate_interact(param_store, interaction);

    let payout_factor = self.payout_factor(param_store);
    let house_edge_bps = self.house_edge_bps(param_store);

    // Ensure context
    self.ensure_context(interaction.balance_manager_id);
    let context = self.contexts.borrow_mut(interaction.balance_manager_id);

    match (interaction.interact_type) {
        InteractionType::PLACE_BET { stake, prediction } => {
            // Place bet and deduct stake
            interaction.transactions.push_back(bet_checked(stake));
            context.bet(stake, prediction);
            // Generate result
            let x = rand.generate_u64_in_range(0, 10_000);
            let result;
            if (x < house_edge_bps) {
                result = house_bias_result();
            } else if (x % 2 == 0) {
                result = head_result();
            } else {
                result = tail_result();
            };
            // Pay out winnings
            let payout;
            if (prediction == result) {
                payout = int_mul(stake, payout_factor);
                interaction.transactions.push_back(win_checked(payout));
                context.settle_win(result, payout);
            } else {
                context.settle_loss(result);
            };
        },
    };
}

public(package) fun new_interact(
    interact_name: String,
    balance_manager_id: ID,
    prediction: String,
    stake: u64,
): Interaction {
    // Transaction vec
    let transactions = vector::empty<Transaction>();
    // Construct the correct interact type
    let interact_type;
    if (interact_name == place_bet_action()) {
        interact_type = InteractionType::PLACE_BET { stake, prediction: prediction };
    } else {
        abort EUnsupportedAction
    };
    Interaction {
        balance_manager_id,
        transactions,
        interact_type,
    }
}

// === Private Functions ===
fun validate_interact(self: &Game, param_store: &ParameterStore, interaction: &Interaction) {
    match (interaction.interact_type) {
        InteractionType::PLACE_BET { stake, prediction: prediction } => {
            assert!(stake >= self.min_stake(param_store), EUnsupportedStake);
            assert!(stake <= self.max_stake(param_store), EUnsupportedStake);
            assert!(
                prediction == head_result() || prediction == tail_result(),
                EUnsupportedPrediction,
            );
        },
    }
}

fun ensure_context(self: &mut Game, balance_manager_id: ID) {
    if (!self.contexts.contains(balance_manager_id)) {
        self.contexts.add(balance_manager_id, context::empty());
    };
}

// === Access to Parameter Store ===

public fun payout_factor(self: &Game, param_store: &ParameterStore): UQ32_32 {
    self.assert_param_store(param_store);
    let payout_factor_bps: u64 = *param_store.borrow<String, u64>(payout_factor_bps_param_name());
    from_quotient(payout_factor_bps, 10_000)
}

public fun house_edge_bps(self: &Game, param_store: &ParameterStore): u64 {
    self.assert_param_store(param_store);
    *param_store.borrow<String, u64>(house_edge_bps_param_name())
}

public fun min_stake(self: &Game, param_store: &ParameterStore): u64 {
    self.assert_param_store(param_store);
    *param_store.borrow<String, u64>(min_stake_param_name())
}

public fun max_stake(self: &Game, param_store: &ParameterStore): u64 {
    self.assert_param_store(param_store);
    *param_store.borrow<String, u64>(max_stake_param_name())
}

/// Gets the max payout of the game. This ensures that the vault has sufficient funds to accept the bet.
fun max_payout(payout_factor: UQ32_32, stake: u64): u64 {
    int_mul(stake, payout_factor)
}

public fun assert_param_store(self: &Game, param_store: &ParameterStore) {
    let param_store_id = self.param_store_id;
    assert!(param_store_id == param_store.id(), EInvalidParamStore);
}

// === Test Functions ===
#[test_only]
public fun get_admin_cap_for_testing(ctx: &mut TxContext): CoinFlipCap {
    CoinFlipCap { id: object::new(ctx) }
}
