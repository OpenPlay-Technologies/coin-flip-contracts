#[test_only]
module coin_flip::e2e_tests;

use coin_flip::constants::{place_bet_action, head_result, tail_result};
use coin_flip::test_utils::default_game;
use openplay_core::balance_manager;
use openplay_core::core_test_utils::{create_and_fix_random, fund_house_for_playing};
use openplay_core::registry::registry_for_testing;
use std::unit_test::destroy;
use sui::coin::mint_for_testing;
use sui::random::Random;
use sui::sui::SUI;
use sui::test_scenario::{begin, return_shared};

#[test]
public fun success_flow_win() {
    // We create and fix random
    // The result will be HEAD
    create_and_fix_random(x"0F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1E");

    // Start scenario
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create a coinflip backend
    let registry = registry_for_testing(scenario.ctx());
    let (mut game, mut house, admin_cap, param_store, mut stats) = default_game(scenario.ctx());

    // Create fee collector
    let (fee_collector, fee_collector_cap) = house.admin_create_fee_collector(
        &admin_cap,
        scenario.ctx(),
    );

    // Assign game to fee collector
    house.admin_add_tx_allowed_with_collector(&admin_cap, game.id(), &fee_collector);

    // Fund the house
    let participation = fund_house_for_playing(&mut house, &registry, 200_000_000, scenario.ctx());
    scenario.next_epoch(addr);

    // Create a balance manager with 1_000_000 stake
    let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());
    let play_cap = balance_manager.mint_play_cap(&balance_manager_cap, scenario.ctx());
    let deposit = mint_for_testing<SUI>(1_000_000, scenario.ctx());
    balance_manager.deposit(&balance_manager_cap, deposit, scenario.ctx());

    // Place 100_000 bet on head
    let rand = scenario.take_shared<Random>();
    game.interact(
        &registry,
        &param_store,
        &mut stats,
        &mut balance_manager,
        &mut house,
        &play_cap,
        place_bet_action(),
        100_000,
        head_result(),
        &rand,
        scenario.ctx(),
    );

    assert!(balance_manager.balance() == 1_100_000);

    destroy(balance_manager);
    destroy(participation);
    destroy(balance_manager_cap);
    destroy(registry);
    destroy(play_cap);
    destroy(game);
    destroy(admin_cap);
    destroy(param_store);
    destroy(stats);
    destroy(fee_collector);
    destroy(fee_collector_cap);
    return_shared(rand);
    destroy(house);
    scenario.end();
}

#[test]
public fun success_flow_lose() {
    // We create and fix random
    // The result will be HEAD
    create_and_fix_random(x"0F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1E");

    // Start scenario
    let addr = @0xa;
    let mut scenario = begin(addr);

    // Create a coinflip backend
    let registry = registry_for_testing(scenario.ctx());
    let (mut game, mut house, admin_cap, param_store, mut stats) = default_game(scenario.ctx());

    // Create fee collector
    let (fee_collector, fee_collector_cap) = house.admin_create_fee_collector(
        &admin_cap,
        scenario.ctx(),
    );

    // Assign game to fee collector
    house.admin_add_tx_allowed_with_collector(&admin_cap, game.id(), &fee_collector);

    // Fund the house
    let participation = fund_house_for_playing(&mut house, &registry, 200_000_000, scenario.ctx());
    scenario.next_epoch(addr);

    // Create a balance manager with 1_000_000 stake
    let (mut balance_manager, balance_manager_cap) = balance_manager::new(scenario.ctx());
    let play_cap = balance_manager.mint_play_cap(&balance_manager_cap, scenario.ctx());
    let deposit = mint_for_testing<SUI>(1_000_000, scenario.ctx());
    balance_manager.deposit(&balance_manager_cap, deposit, scenario.ctx());

    // Place 100_000 bet on tail
    let rand = scenario.take_shared<Random>();
    game.interact(
        &registry,
        &param_store,
        &mut stats,
        &mut balance_manager,
        &mut house,
        &play_cap,
        place_bet_action(),
        100_000,
        tail_result(),
        &rand,
        scenario.ctx(),
    );

    assert!(balance_manager.balance() == 900_000);

    destroy(balance_manager);
    destroy(participation);
    destroy(balance_manager_cap);
    destroy(play_cap);
    destroy(game);
    destroy(admin_cap);
    destroy(registry);
    destroy(param_store);

    return_shared(rand);
    destroy(house);
    destroy(stats);
    destroy(fee_collector);
    destroy(fee_collector_cap);
    scenario.end();
}
