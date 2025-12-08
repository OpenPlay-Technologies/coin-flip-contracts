#[test_only]
module coin_flip::test_utils;

use coin_flip::game::{Self, Game, get_admin_cap_for_testing};
use openplay_core::game_stats::GameStatistics;
use openplay_core::house::{Self, House, HouseAdminCap};
use openplay_core::parameter_store::ParameterStore;
use openplay_core::registry::registry_for_testing;
use std::unit_test::destroy;

public fun default_game(
    ctx: &mut TxContext,
): (Game, House, HouseAdminCap, ParameterStore, GameStatistics) {
    let coin_flip_cap = get_admin_cap_for_testing(ctx);
    let mut registry = registry_for_testing(ctx);
    let (game, param_store, stats) = game::admin_create(
        &coin_flip_cap,
        &mut registry,
        0,
        10_000_000,
        2_000,
        20_000,
        ctx,
    );

    let (house, house_admin_cap) = house::new_for_testing(false, 10_000_000, 50, ctx);

    destroy(coin_flip_cap);
    destroy(registry);
    (game, house, house_admin_cap, param_store, stats)
}
