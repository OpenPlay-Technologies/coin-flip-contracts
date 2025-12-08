#[test_only]
module coin_flip::context_tests;

use coin_flip::constants::{
    head_result,
    tail_result,
    new_status,
    initialized_status,
    settled_status
};
use coin_flip::context;
use std::string::utf8;
use std::unit_test::destroy;

#[test, expected_failure(abort_code = context::EInvalidStateTransition)]
public fun invalid_transition_bet_twice() {
    let mut context = context::empty();
    context.bet(100_000, head_result());
    context.bet(100_000, head_result());
    abort 0
}

#[test, expected_failure(abort_code = context::EInvalidStateTransition)]
public fun invalid_transition_settle_twice() {
    let mut context = context::empty();
    context.bet(100_000, head_result());
    context.settle_loss(head_result());
    context.settle_loss(head_result());
    abort 0
}

#[test, expected_failure(abort_code = context::EInvalidStateTransition)]
public fun invalid_transition_settle_first() {
    let mut context = context::empty();
    context.settle_loss(head_result());
    abort 0
}

#[test]
public fun ok_flow() {
    // Create new context
    let mut context = context::empty();
    assert!(context.status() == new_status());

    // Bet
    context.bet(100_000, head_result());
    assert!(context.status() == initialized_status());
    assert!(context.prediction() == head_result());

    // Settle
    context.settle_win(tail_result(), 31);
    assert!(context.result() == tail_result());
    assert!(context.player_won() == false);
    assert!(context.win() == 31);
    assert!(context.status() == settled_status());

    destroy(context);
}

#[test, expected_failure(abort_code = context::EUnsupportedPrediction)]
public fun invalid_prediction() {
    let mut context = context::empty();
    context.bet(100_000, utf8(b"unknown result"));
    abort 0
}

#[test, expected_failure(abort_code = context::EUnsupportedResult)]
public fun invalid_result() {
    let mut context = context::empty();
    context.bet(100_000, head_result());
    context.settle_loss(utf8(b"unknown result"));
    abort 0
}
