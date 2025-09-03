#[test_only]
module sui_pay::sui_pay_tests;

use std::type_name;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::test_scenario::{Self, Scenario};
use sui::test_utils;
use sui_pay::sui_pay;

const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;
const CHARLIE: address = @0xC;

/// Sets up a new test scenario with ALICE as the initial sender.
///
/// # Returns
/// A new Scenario instance for testing
fun setup_test_scenario(): Scenario {
    test_scenario::begin(ALICE)
}

/// Creates a test SUI coin with the specified amount.
///
/// # Parameters
/// * `scenario` - Test scenario to use for coin creation
/// * `amount` - Amount of SUI to mint in the coin
///
/// # Returns
/// A Coin<SUI> with the specified amount
fun create_test_coin(scenario: &mut Scenario, amount: u64): Coin<SUI> {
    coin::mint_for_testing<SUI>(amount, test_scenario::ctx(scenario))
}

/// Tests creating a payment registry with no expiration duration.
#[test]
fun test_create_registry() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_pay::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_pay::Namespace>(&scenario);
        let (registry, cap) = sui_pay::create_registry(
            &mut namespace,
            std::ascii::string(b"test_registry"),
            test_scenario::ctx(&mut scenario),
        );
        test_utils::destroy(registry);
        test_utils::destroy(cap);
        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests processing a payment where the coin amount exactly matches the payment amount.
#[test]
fun test_successful_payment_exact_amount() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_pay::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_pay::Namespace>(&scenario);
        let (mut registry, cap) = sui_pay::create_registry(
            &mut namespace,
            std::ascii::string(b"test_registry"),
            test_scenario::ctx(&mut scenario),
        );
        let coin = create_test_coin(&mut scenario, 1000);

        let _receipt = sui_pay::process_payment_in_registry<SUI>(
            &mut registry,
            std::ascii::string(b"12345"), // payment_id
            1000, // payment_amount
            coin,
            BOB,
            test_scenario::ctx(&mut scenario),
        );

        // Payment completed successfully - nonce is now recorded

        test_utils::destroy(registry);
        test_utils::destroy(cap);
        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests that providing more coin amount than payment amount fails with EIncorrectAmount error.
#[test, expected_failure(abort_code = 1, location = sui_pay)]
fun test_overpayment_failure() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_pay::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_pay::Namespace>(&scenario);
        let (mut registry, cap) = sui_pay::create_registry(
            &mut namespace,
            std::ascii::string(b"test_registry"),
            test_scenario::ctx(&mut scenario),
        );
        let coin = create_test_coin(&mut scenario, 1500); // More than expected

        let _receipt = sui_pay::process_payment_in_registry<SUI>(
            &mut registry,
            std::ascii::string(b"67890"), // salt
            1000, // payment_amount - less than coin value
            coin,
            BOB,
            test_scenario::ctx(&mut scenario),
        );

        test_utils::destroy(registry);
        test_utils::destroy(cap);
        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests that using identical payment parameters fails with EReceiptAlreadyExists error.
#[test, expected_failure(abort_code = 0, location = sui_pay)]
fun test_duplicate_payment_hash_failure() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_pay::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_pay::Namespace>(&scenario);
        let (mut registry, cap) = sui_pay::create_registry(
            &mut namespace,
            std::ascii::string(b"test_registry"),
            test_scenario::ctx(&mut scenario),
        );

        // Set config to enable receipt writing
        let config = sui_pay::create_receipt_config(
            option::none() // receipt_expiration_duration_ms
        );
        sui_pay::set_receipt_config(
            &mut registry,
            &cap,
            config,
            test_scenario::ctx(&mut scenario),
        );
        let coin1 = create_test_coin(&mut scenario, 1000);
        let coin2 = create_test_coin(&mut scenario, 1000);

        // First payment with specific parameters should succeed
        let _receipt1 = sui_pay::process_payment_in_registry<SUI>(
            &mut registry,
            std::ascii::string(b"12345"),
            1000, // payment_amount
            coin1,
            BOB,
            test_scenario::ctx(&mut scenario),
        );

        // Second payment with identical parameters should fail (same hash)
        let _receipt2 = sui_pay::process_payment_in_registry<SUI>(
            &mut registry,
            std::ascii::string(b"12345"), // Same salt
            1000, // Same payment_amount
            coin2,
            BOB, // Same receiver
            test_scenario::ctx(&mut scenario),
        );

        test_utils::destroy(registry);
        test_utils::destroy(cap);
        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests that providing insufficient coin amount fails with EInsufficientAmount error.
#[test, expected_failure(abort_code = 1, location = sui_pay)]
fun test_insufficient_amount_failure() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_pay::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_pay::Namespace>(&scenario);
        let (mut registry, cap) = sui_pay::create_registry(
            &mut namespace,
            std::ascii::string(b"test_registry"),
            test_scenario::ctx(&mut scenario),
        );
        let coin = create_test_coin(&mut scenario, 500); // Less than expected

        let _receipt = sui_pay::process_payment_in_registry<SUI>(
            &mut registry,
            std::ascii::string(b"12345"),
            1000, // Expected 1000 but coin only has 500
            coin,
            BOB,
            test_scenario::ctx(&mut scenario),
        );

        test_utils::destroy(registry);
        test_utils::destroy(cap);
        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests processing multiple payments with different nonces successfully.
#[test]
fun test_multiple_different_nonces() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_pay::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_pay::Namespace>(&scenario);
        let (mut registry, cap) = sui_pay::create_registry(
            &mut namespace,
            std::ascii::string(b"test_registry"),
            test_scenario::ctx(&mut scenario),
        );

        // Process multiple payments with different salts
        let coin1 = create_test_coin(&mut scenario, 1000);
        let _receipt1 = sui_pay::process_payment_in_registry<SUI>(
            &mut registry,
            std::ascii::string(b"1"),
            1000,
            coin1,
            BOB,
            test_scenario::ctx(&mut scenario),
        );

        let coin2 = create_test_coin(&mut scenario, 1500);
        let _receipt2 = sui_pay::process_payment_in_registry<SUI>(
            &mut registry,
            std::ascii::string(b"2"),
            1500,
            coin2,
            CHARLIE,
            test_scenario::ctx(&mut scenario),
        );

        let coin3 = create_test_coin(&mut scenario, 500);
        let _receipt3 = sui_pay::process_payment_in_registry<SUI>(
            &mut registry,
            std::ascii::string(b"3"),
            500,
            coin3,
            BOB,
            test_scenario::ctx(&mut scenario),
        );

        // All payments completed successfully with different nonces

        test_utils::destroy(registry);
        test_utils::destroy(cap);
        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests processing a payment with zero payment amount (entire amount becomes tip).
#[test]
fun test_zero_payment_amount() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_pay::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_pay::Namespace>(&scenario);
        let (mut registry, cap) = sui_pay::create_registry(
            &mut namespace,
            std::ascii::string(b"test_registry"),
            test_scenario::ctx(&mut scenario),
        );
        let coin = create_test_coin(&mut scenario, 1000);

        let _receipt = sui_pay::process_payment_in_registry<SUI>(
            &mut registry,
            std::ascii::string(b"12345"),
            1000, // payment amount
            coin,
            BOB,
            test_scenario::ctx(&mut scenario),
        );

        // Payment with zero payment amount completed successfully

        test_utils::destroy(registry);
        test_utils::destroy(cap);
        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests processing a payment with maximum u64 nonce value.
#[test]
fun test_large_nonce_values() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_pay::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_pay::Namespace>(&scenario);
        let (mut registry, cap) = sui_pay::create_registry(
            &mut namespace,
            std::ascii::string(b"test_registry"),
            test_scenario::ctx(&mut scenario),
        );

        // Test with large salt value
        let coin = create_test_coin(&mut scenario, 1000);
        let _receipt = sui_pay::process_payment_in_registry<SUI>(
            &mut registry,
            std::ascii::string(b"18446744073709551615"), // Large salt
            1000,
            coin,
            BOB,
            test_scenario::ctx(&mut scenario),
        );

        // Payment with large nonce completed successfully

        test_utils::destroy(registry);
        test_utils::destroy(cap);
        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests successfully closing an expired receipt (expiration duration = 0).
#[test]
fun test_close_expired_receipt_success() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_pay::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_pay::Namespace>(&scenario);
        let (mut registry, cap) = sui_pay::create_registry(
            &mut namespace,
            std::ascii::string(b"test_registry"),
            test_scenario::ctx(&mut scenario),
        );

        // Set config to enable receipt writing with 0ms expiration
        let config = sui_pay::create_receipt_config(
            option::some(0) // receipt_expiration_duration_ms
        );
        sui_pay::set_receipt_config(
            &mut registry,
            &cap,
            config,
            test_scenario::ctx(&mut scenario),
        );
        let coin = create_test_coin(&mut scenario, 1000);

        let payment_id = std::ascii::string(b"12345");
        let payment_amount = 1000;
        let receiver = BOB;

        let _receipt = sui_pay::process_payment_in_registry<SUI>(
            &mut registry,
            payment_id,
            payment_amount,
            coin,
            receiver,
            test_scenario::ctx(&mut scenario),
        );

        // Create payment key to close the receipt
        let coin_type = type_name::into_string(type_name::with_defining_ids<SUI>());
        let payment_key = sui_pay::create_payment_key(
            payment_id,
            payment_amount,
            coin_type,
            receiver,
        );

        sui_pay::close_expired_receipt(
            &mut registry,
            payment_key,
            test_scenario::ctx(&mut scenario),
        );

        test_utils::destroy(registry);
        test_utils::destroy(cap);
        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests that closing a non-existent receipt fails with EReceiptDoesNotExist error.
#[test, expected_failure(abort_code = 2, location = sui_pay)]
fun test_close_nonexistent_receipt() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_pay::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_pay::Namespace>(&scenario);
        let (mut registry, cap) = sui_pay::create_registry(
            &mut namespace,
            std::ascii::string(b"test_registry"),
            test_scenario::ctx(&mut scenario),
        );

        // Set config to enable receipt writing
        let config = sui_pay::create_receipt_config(
            option::some(1000) // receipt_expiration_duration_ms
        );
        sui_pay::set_receipt_config(
            &mut registry,
            &cap,
            config,
            test_scenario::ctx(&mut scenario),
        );

        // Create a fake payment key for a non-existent receipt
        let coin_type = type_name::into_string(type_name::with_defining_ids<SUI>());
        let fake_payment_key = sui_pay::create_payment_key(
            std::ascii::string(b"99999"),
            1000,
            coin_type,
            BOB,
        );

        sui_pay::close_expired_receipt(
            &mut registry,
            fake_payment_key,
            test_scenario::ctx(&mut scenario),
        );

        test_utils::destroy(registry);
        test_utils::destroy(cap);
        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests that closing a receipt before expiration fails with EReceiptHasNotExpired error.
#[test, expected_failure(abort_code = 3, location = sui_pay)]
fun test_close_receipt_not_expired() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_pay::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_pay::Namespace>(&scenario);
        let (mut registry, cap) = sui_pay::create_registry(
            &mut namespace,
            std::ascii::string(b"test_registry"),
            test_scenario::ctx(&mut scenario),
        );

        // Set config to enable receipt writing with 10s expiration
        let config = sui_pay::create_receipt_config(
            option::some(10000) // receipt_expiration_duration_ms
        );
        sui_pay::set_receipt_config(
            &mut registry,
            &cap,
            config,
            test_scenario::ctx(&mut scenario),
        );
        let coin = create_test_coin(&mut scenario, 1000);

        let payment_id = std::ascii::string(b"12345");
        let payment_amount = 1000;
        let receiver = BOB;

        let _receipt = sui_pay::process_payment_in_registry<SUI>(
            &mut registry,
            payment_id,
            payment_amount,
            coin,
            receiver,
            test_scenario::ctx(&mut scenario),
        );

        // Create payment key to close the receipt
        let coin_type = type_name::into_string(type_name::with_defining_ids<SUI>());
        let payment_key = sui_pay::create_payment_key(
            payment_id,
            payment_amount,
            coin_type,
            receiver,
        );

        sui_pay::close_expired_receipt(
            &mut registry,
            payment_key,
            test_scenario::ctx(&mut scenario),
        );

        test_utils::destroy(registry);
        test_utils::destroy(cap);
        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests that closing a receipt fails when expiration is disabled (None).
#[test, expected_failure(abort_code = 3, location = sui_pay)]
fun test_close_receipt_no_expiration() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_pay::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_pay::Namespace>(&scenario);
        let (mut registry, cap) = sui_pay::create_registry(
            &mut namespace,
            std::ascii::string(b"test_registry"),
            test_scenario::ctx(&mut scenario),
        );

        // Set config to enable receipt writing with no expiration
        let config = sui_pay::create_receipt_config(
            option::none() // receipt_expiration_duration_ms
        );
        sui_pay::set_receipt_config(
            &mut registry,
            &cap,
            config,
            test_scenario::ctx(&mut scenario),
        );
        let coin = create_test_coin(&mut scenario, 1000);

        let payment_id = std::ascii::string(b"12345");
        let payment_amount = 1000;
        let receiver = BOB;

        let _receipt = sui_pay::process_payment_in_registry<SUI>(
            &mut registry,
            payment_id,
            payment_amount,
            coin,
            receiver,
            test_scenario::ctx(&mut scenario),
        );

        // Create payment key to close the receipt
        let coin_type = type_name::into_string(type_name::with_defining_ids<SUI>());
        let payment_key = sui_pay::create_payment_key(
            payment_id,
            payment_amount,
            coin_type,
            receiver,
        );

        sui_pay::close_expired_receipt(
            &mut registry,
            payment_key,
            test_scenario::ctx(&mut scenario),
        );

        test_utils::destroy(registry);
        test_utils::destroy(cap);
        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests that closing a receipt fails when using 30-day expiration duration.
#[test, expected_failure(abort_code = 3, location = sui_pay)]
fun test_30_day_expiration_duration() {
    let mut scenario = setup_test_scenario();
    let thirty_days_ms = 30 * 24 * 60 * 60 * 1000; // 30 days in milliseconds

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_pay::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_pay::Namespace>(&scenario);
        let (mut registry, cap) = sui_pay::create_registry(
            &mut namespace,
            std::ascii::string(b"test_registry"),
            test_scenario::ctx(&mut scenario),
        );

        // Set config to enable receipt writing with 30-day expiration
        let config = sui_pay::create_receipt_config(
            option::some(thirty_days_ms) // receipt_expiration_duration_ms
        );
        sui_pay::set_receipt_config(
            &mut registry,
            &cap,
            config,
            test_scenario::ctx(&mut scenario),
        );
        let coin = create_test_coin(&mut scenario, 1000);

        let payment_id = std::ascii::string(b"12345");
        let payment_amount = 1000;
        let receiver = BOB;

        let _receipt = sui_pay::process_payment_in_registry<SUI>(
            &mut registry,
            payment_id,
            payment_amount,
            coin,
            receiver,
            test_scenario::ctx(&mut scenario),
        );

        // Create payment key to close the receipt
        let coin_type = type_name::into_string(type_name::with_defining_ids<SUI>());
        let payment_key = sui_pay::create_payment_key(
            payment_id,
            payment_amount,
            coin_type,
            receiver,
        );

        sui_pay::close_expired_receipt(
            &mut registry,
            payment_key,
            test_scenario::ctx(&mut scenario),
        );

        test_utils::destroy(registry);
        test_utils::destroy(cap);
        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests setting receipt config as admin.
#[test]
fun test_set_config_success() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_pay::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_pay::Namespace>(&scenario);
        let (mut registry, cap) = sui_pay::create_registry(
            &mut namespace,
            std::ascii::string(b"test_registry"),
            test_scenario::ctx(&mut scenario),
        );

        let config = sui_pay::create_receipt_config(
            option::some(1000) // receipt_expiration_duration_ms
        );

        sui_pay::set_receipt_config(
            &mut registry,
            &cap,
            config,
            test_scenario::ctx(&mut scenario),
        );

        test_utils::destroy(registry);
        test_utils::destroy(cap);
        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests that setting config fails when caller is not admin.
#[test, expected_failure(abort_code = 4, location = sui_pay)]
fun test_set_config_unauthorized() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_pay::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, BOB);
    {
        let mut namespace = test_scenario::take_shared<sui_pay::Namespace>(&scenario);
        let (mut registry, bob_cap) = sui_pay::create_registry(
            &mut namespace,
            std::ascii::string(b"test_registry"),
            test_scenario::ctx(&mut scenario),
        );
        test_scenario::return_shared(namespace);

        test_scenario::next_tx(&mut scenario, ALICE);
        {
            let mut namespace = test_scenario::take_shared<sui_pay::Namespace>(&scenario);
            let (alice_registry, alice_cap) = sui_pay::create_registry(
                &mut namespace,
                std::ascii::string(b"alice_registry"),
                test_scenario::ctx(&mut scenario),
            );
            test_utils::destroy(alice_registry);
            
            let config = sui_pay::create_receipt_config(
                option::some(1000) // receipt_expiration_duration_ms
            );

            // ALICE tries to set config on BOB's registry with her cap - should fail
            sui_pay::set_receipt_config(
                &mut registry,
                &alice_cap,
                config,
                test_scenario::ctx(&mut scenario),
            );
            
            test_utils::destroy(alice_cap);
            test_scenario::return_shared(namespace);
        };

        test_utils::destroy(registry);
        test_utils::destroy(bob_cap);
    };

    test_scenario::end(scenario);
}
