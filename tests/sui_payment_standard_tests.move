#[test_only]
module sui_payment_standard::sui_pay_tests;

use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::test_scenario::{Self, Scenario};
use sui::test_utils;
use sui_payment_standard::sui_payment_standard;

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

/// Creates a test clock for testing time-dependent functionality.
///
/// # Parameters
/// * `scenario` - Test scenario to use for clock creation
///
/// # Returns
/// A Clock instance for testing
fun create_test_clock(scenario: &mut Scenario): Clock {
    clock::create_for_testing(test_scenario::ctx(scenario))
}

/// Tests creating a payment registry with no expiration duration.
#[test]
fun test_create_registry() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_payment_standard::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_payment_standard::Namespace>(&scenario);
        let (registry, cap) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"testregistry"),
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
        sui_payment_standard::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_payment_standard::Namespace>(&scenario);
        let (mut registry, cap) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"testregistry"),
            test_scenario::ctx(&mut scenario),
        );
        let coin = create_test_coin(&mut scenario, 1000);
        let clock = create_test_clock(&mut scenario);

        let _receipt = sui_payment_standard::process_payment_in_registry<SUI>(
            &mut registry,
            std::ascii::string(b"12345"), // payment_id
            1000, // payment_amount
            coin,
            BOB,
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        // Payment completed successfully - nonce is now recorded
        test_utils::destroy(clock);
        test_utils::destroy(registry);
        test_utils::destroy(cap);
        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests that providing more coin amount than payment amount fails with EIncorrectAmount error.
#[test, expected_failure(abort_code = 1, location = sui_payment_standard)]
fun test_overpayment_failure() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_payment_standard::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_payment_standard::Namespace>(&scenario);
        let (mut registry, cap) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"testregistry"),
            test_scenario::ctx(&mut scenario),
        );
        let coin = create_test_coin(&mut scenario, 1500); // More than expected
        let clock = create_test_clock(&mut scenario);

        let _receipt = sui_payment_standard::process_payment_in_registry<SUI>(
            &mut registry,
            std::ascii::string(b"67890"), // salt
            1000, // payment_amount - less than coin value
            coin,
            BOB,
            &clock,
            test_scenario::ctx(&mut scenario),
        );
        test_utils::destroy(clock);
        test_utils::destroy(registry);
        test_utils::destroy(cap);
        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests that using identical payment parameters fails with EReceiptAlreadyExists error.
#[test, expected_failure(abort_code = 0, location = sui_payment_standard)]
fun test_duplicate_payment_hash_failure() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_payment_standard::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_payment_standard::Namespace>(&scenario);
        let (mut registry, cap) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"testregistry"),
            test_scenario::ctx(&mut scenario),
        );

        // Set config to enable payment record writing
        let config = sui_payment_standard::create_payment_record_config(
            0, // epoch_expiration_duration
        );
        sui_payment_standard::set_receipt_config(
            &mut registry,
            &cap,
            config,
            test_scenario::ctx(&mut scenario),
        );
        let coin1 = create_test_coin(&mut scenario, 1000);
        let coin2 = create_test_coin(&mut scenario, 1000);
        let clock = create_test_clock(&mut scenario);

        // First payment with specific parameters should succeed
        let _receipt1 = sui_payment_standard::process_payment_in_registry<SUI>(
            &mut registry,
            std::ascii::string(b"12345"),
            1000, // payment_amount
            coin1,
            BOB,
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        // Second payment with identical parameters should fail (same hash)
        let _receipt2 = sui_payment_standard::process_payment_in_registry<SUI>(
            &mut registry,
            std::ascii::string(b"12345"), // Same salt
            1000, // Same payment_amount
            coin2,
            BOB, // Same receiver
            &clock,
            test_scenario::ctx(&mut scenario),
        );
        test_utils::destroy(clock);
        test_utils::destroy(registry);
        test_utils::destroy(cap);
        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests that providing insufficient coin amount fails with EInsufficientAmount error.
#[test, expected_failure(abort_code = sui_payment_standard::EInsufficientAmount)]
fun test_insufficient_amount_failure() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    sui_payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);

    let mut namespace = scenario.take_shared<sui_payment_standard::Namespace>();
    let (mut registry, cap) = namespace.create_registry(
        b"testregistry".to_ascii_string(),
        scenario.ctx(),
    );
    let coin = create_test_coin(&mut scenario, 500); // Less than expected
    let clock = create_test_clock(&mut scenario);

    let _receipt = sui_payment_standard::process_payment_in_registry<SUI>(
        &mut registry,
        std::ascii::string(b"12345"),
        1000, // Expected 1000 but coin only has 500
        coin,
        BOB,
        &clock,
        test_scenario::ctx(&mut scenario),
    );
    abort
}

/// Tests processing multiple payments with different nonces successfully.
#[test]
fun test_multiple_different_nonces() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_payment_standard::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_payment_standard::Namespace>(&scenario);
        let (mut registry, cap) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"testregistry"),
            test_scenario::ctx(&mut scenario),
        );

        // Process multiple payments with different salts
        let clock = create_test_clock(&mut scenario);

        let coin1 = create_test_coin(&mut scenario, 1000);
        let _receipt1 = sui_payment_standard::process_payment_in_registry<SUI>(
            &mut registry,
            std::ascii::string(b"1"),
            1000,
            coin1,
            BOB,
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        let coin2 = create_test_coin(&mut scenario, 1500);
        let _receipt2 = sui_payment_standard::process_payment_in_registry<SUI>(
            &mut registry,
            std::ascii::string(b"2"),
            1500,
            coin2,
            CHARLIE,
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        let coin3 = create_test_coin(&mut scenario, 500);
        let _receipt3 = sui_payment_standard::process_payment_in_registry<SUI>(
            &mut registry,
            std::ascii::string(b"3"),
            500,
            coin3,
            BOB,
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        // All payments completed successfully with different nonces
        test_utils::destroy(clock);
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
        sui_payment_standard::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_payment_standard::Namespace>(&scenario);
        let (mut registry, cap) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"testregistry"),
            test_scenario::ctx(&mut scenario),
        );
        let coin = create_test_coin(&mut scenario, 1000);
        let clock = create_test_clock(&mut scenario);

        let _receipt = sui_payment_standard::process_payment_in_registry<SUI>(
            &mut registry,
            std::ascii::string(b"12345"),
            1000, // payment amount
            coin,
            BOB,
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        // Payment with zero payment amount completed successfully

        test_utils::destroy(clock);
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
        sui_payment_standard::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_payment_standard::Namespace>(&scenario);
        let (mut registry, cap) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"testregistry"),
            test_scenario::ctx(&mut scenario),
        );

        // Test with large salt value
        let coin = create_test_coin(&mut scenario, 1000);
        let clock = create_test_clock(&mut scenario);

        let _receipt = sui_payment_standard::process_payment_in_registry<SUI>(
            &mut registry,
            std::ascii::string(b"18446744073709551615"), // Large salt
            1000,
            coin,
            BOB,
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        // Payment with large nonce completed successfully
        test_utils::destroy(clock);
        test_utils::destroy(registry);
        test_utils::destroy(cap);
        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests successfully deleting an expired payment record (expiration duration = 0 epochs).
#[test]
fun test_delete_expired_payment_record_success() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_payment_standard::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_payment_standard::Namespace>(&scenario);
        let (mut registry, cap) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"testregistry"),
            test_scenario::ctx(&mut scenario),
        );

        // Set config to enable payment record writing with 0 epoch expiration
        let config = sui_payment_standard::create_payment_record_config(
            0, // epoch_expiration_duration
        );
        sui_payment_standard::set_receipt_config(
            &mut registry,
            &cap,
            config,
            test_scenario::ctx(&mut scenario),
        );
        let coin = create_test_coin(&mut scenario, 1000);
        let clock = create_test_clock(&mut scenario);

        let payment_id = std::ascii::string(b"12345");
        let payment_amount = 1000;
        let receiver = BOB;

        let _receipt = sui_payment_standard::process_payment_in_registry<SUI>(
            &mut registry,
            payment_id,
            payment_amount,
            coin,
            receiver,
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        // Create payment record key to delete the record
        let payment_record_key = sui_payment_standard::create_payment_key<SUI>(
            payment_id,
            payment_amount,
            receiver,
        );

        sui_payment_standard::delete_payment_record<SUI>(
            &mut registry,
            payment_record_key,
            test_scenario::ctx(&mut scenario),
        );
        test_utils::destroy(clock);
        test_utils::destroy(registry);
        test_utils::destroy(cap);
        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests that deleting a non-existent payment record fails with EPaymentRecordDoesNotExist error.
#[test, expected_failure(abort_code = 2, location = sui_payment_standard)]
fun test_delete_nonexistent_payment_record() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_payment_standard::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_payment_standard::Namespace>(&scenario);
        let (mut registry, cap) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"testregistry"),
            test_scenario::ctx(&mut scenario),
        );

        // Set config to enable payment record writing
        let config = sui_payment_standard::create_payment_record_config(
            1000, // epoch_expiration_duration
        );
        sui_payment_standard::set_receipt_config(
            &mut registry,
            &cap,
            config,
            test_scenario::ctx(&mut scenario),
        );

        let clock = create_test_clock(&mut scenario);

        // Create a fake payment record key for a non-existent record
        let fake_payment_record_key = sui_payment_standard::create_payment_key<SUI>(
            std::ascii::string(b"99999"),
            1000,
            BOB,
        );

        sui_payment_standard::delete_payment_record<SUI>(
            &mut registry,
            fake_payment_record_key,
            test_scenario::ctx(&mut scenario),
        );

        test_utils::destroy(clock);
        test_utils::destroy(registry);
        test_utils::destroy(cap);
        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests that deleting a payment record before expiration fails with EPaymentRecordHasNotExpired error.
#[test, expected_failure(abort_code = 3, location = sui_payment_standard)]
fun test_delete_payment_record_not_expired() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_payment_standard::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_payment_standard::Namespace>(&scenario);
        let (mut registry, cap) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"testregistry"),
            test_scenario::ctx(&mut scenario),
        );

        // Set config to enable payment record writing with large epoch expiration
        let config = sui_payment_standard::create_payment_record_config(
            10000, // epoch_expiration_duration
        );
        sui_payment_standard::set_receipt_config(
            &mut registry,
            &cap,
            config,
            test_scenario::ctx(&mut scenario),
        );
        let coin = create_test_coin(&mut scenario, 1000);
        let clock = create_test_clock(&mut scenario);

        let payment_id = std::ascii::string(b"12345");
        let payment_amount = 1000;
        let receiver = BOB;

        let _receipt = sui_payment_standard::process_payment_in_registry<SUI>(
            &mut registry,
            payment_id,
            payment_amount,
            coin,
            receiver,
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        // Create payment record key to delete the record
        let payment_record_key = sui_payment_standard::create_payment_key<SUI>(
            payment_id,
            payment_amount,
            receiver,
        );

        sui_payment_standard::delete_payment_record<SUI>(
            &mut registry,
            payment_record_key,
            test_scenario::ctx(&mut scenario),
        );
        test_utils::destroy(clock);
        test_utils::destroy(registry);
        test_utils::destroy(cap);
        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests that deleting a payment record succeeds when expiration duration is 0 epochs (immediate expiration).
#[test]
fun test_delete_payment_record_immediate_expiration() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_payment_standard::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_payment_standard::Namespace>(&scenario);
        let (mut registry, cap) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"testregistry"),
            test_scenario::ctx(&mut scenario),
        );

        // Set config to enable payment record writing with immediate expiration
        let config = sui_payment_standard::create_payment_record_config(
            0, // epoch_expiration_duration - 0 means immediate expiration
        );
        sui_payment_standard::set_receipt_config(
            &mut registry,
            &cap,
            config,
            test_scenario::ctx(&mut scenario),
        );
        let coin = create_test_coin(&mut scenario, 1000);
        let clock = create_test_clock(&mut scenario);

        let payment_id = std::ascii::string(b"12345");
        let payment_amount = 1000;
        let receiver = BOB;

        let _receipt = sui_payment_standard::process_payment_in_registry<SUI>(
            &mut registry,
            payment_id,
            payment_amount,
            coin,
            receiver,
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        // Create payment record key to delete the record
        let payment_record_key = sui_payment_standard::create_payment_key<SUI>(
            payment_id,
            payment_amount,
            receiver,
        );

        sui_payment_standard::delete_payment_record<SUI>(
            &mut registry,
            payment_record_key,
            test_scenario::ctx(&mut scenario),
        );
        test_utils::destroy(clock);
        test_utils::destroy(registry);
        test_utils::destroy(cap);
        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests that deleting a payment record fails when using 30 epoch expiration duration.
#[test, expected_failure(abort_code = 3, location = sui_payment_standard)]
fun test_30_epoch_expiration_duration() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_payment_standard::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_payment_standard::Namespace>(&scenario);
        let (mut registry, cap) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"testregistry"),
            test_scenario::ctx(&mut scenario),
        );

        // Set config to enable payment record writing with 30 epoch expiration
        let config = sui_payment_standard::create_payment_record_config(
            30, // epoch_expiration_duration (30 epochs)
        );
        sui_payment_standard::set_receipt_config(
            &mut registry,
            &cap,
            config,
            test_scenario::ctx(&mut scenario),
        );
        let coin = create_test_coin(&mut scenario, 1000);
        let clock = create_test_clock(&mut scenario);

        let payment_id = std::ascii::string(b"12345");
        let payment_amount = 1000;
        let receiver = BOB;

        let _receipt = sui_payment_standard::process_payment_in_registry<SUI>(
            &mut registry,
            payment_id,
            payment_amount,
            coin,
            receiver,
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        // Create payment record key to delete the record
        let payment_record_key = sui_payment_standard::create_payment_key<SUI>(
            payment_id,
            payment_amount,
            receiver,
        );

        sui_payment_standard::delete_payment_record<SUI>(
            &mut registry,
            payment_record_key,
            test_scenario::ctx(&mut scenario),
        );
        test_utils::destroy(clock);
        test_utils::destroy(registry);
        test_utils::destroy(cap);
        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests creating registry with valid alphanumeric names.
#[test]
fun test_valid_registry_names() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_payment_standard::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_payment_standard::Namespace>(&scenario);

        // Test various valid SuiNS-compliant names
        let (registry1, cap1) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"test123"),
            test_scenario::ctx(&mut scenario),
        );
        test_utils::destroy(registry1);
        test_utils::destroy(cap1);

        let (registry2, cap2) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"abc"),
            test_scenario::ctx(&mut scenario),
        );
        test_utils::destroy(registry2);
        test_utils::destroy(cap2);

        let (registry3, cap3) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"test-registry-123"),
            test_scenario::ctx(&mut scenario),
        );
        test_utils::destroy(registry3);
        test_utils::destroy(cap3);

        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests that creating registry with special characters fails.
#[test, expected_failure(abort_code = 7, location = sui_payment_standard)]
fun test_invalid_registry_name_special_chars() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_payment_standard::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_payment_standard::Namespace>(&scenario);

        // Should fail - contains underscore (not allowed in SuiNS)
        let (registry, cap) = sui_payment_standard::create_registry(
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

/// Tests that creating registry with too long name fails.
#[test, expected_failure(abort_code = 6, location = sui_payment_standard)]
fun test_invalid_registry_name_too_long() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_payment_standard::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_payment_standard::Namespace>(&scenario);

        // Should fail - 64 characters (exceeds 63 character SuiNS limit)
        let (registry, cap) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"1234567890123456789012345678901234567890123456789012345678901234"),
            test_scenario::ctx(&mut scenario),
        );
        test_utils::destroy(registry);
        test_utils::destroy(cap);

        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests that creating registry with empty name fails.
#[test, expected_failure(abort_code = 6, location = sui_payment_standard)]
fun test_invalid_registry_name_empty() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_payment_standard::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_payment_standard::Namespace>(&scenario);

        // Should fail - too short (less than 3 characters)
        let (registry, cap) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"ab"),
            test_scenario::ctx(&mut scenario),
        );
        test_utils::destroy(registry);
        test_utils::destroy(cap);

        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests setting payment record config as admin.
#[test]
fun test_set_config_success() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_payment_standard::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_payment_standard::Namespace>(&scenario);
        let (mut registry, cap) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"testregistry"),
            test_scenario::ctx(&mut scenario),
        );

        let config = sui_payment_standard::create_payment_record_config(
            1000, // epoch_expiration_duration
        );

        sui_payment_standard::set_receipt_config(
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
#[test, expected_failure(abort_code = 4, location = sui_payment_standard)]
fun test_set_config_unauthorized() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_payment_standard::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, BOB);
    {
        let mut namespace = test_scenario::take_shared<sui_payment_standard::Namespace>(&scenario);
        let (mut registry, bob_cap) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"testregistry"),
            test_scenario::ctx(&mut scenario),
        );
        test_scenario::return_shared(namespace);

        test_scenario::next_tx(&mut scenario, ALICE);
        {
            let mut namespace = test_scenario::take_shared<sui_payment_standard::Namespace>(
                &scenario,
            );
            let (alice_registry, alice_cap) = sui_payment_standard::create_registry(
                &mut namespace,
                std::ascii::string(b"aliceregistry"),
                test_scenario::ctx(&mut scenario),
            );
            test_utils::destroy(alice_registry);

            let config = sui_payment_standard::create_payment_record_config(
                1000, // epoch_expiration_duration
            );

            // ALICE tries to set config on BOB's registry with her cap - should fail
            sui_payment_standard::set_receipt_config(
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

/// Tests that creating registry with names starting with hyphen fails.
#[test, expected_failure(abort_code = 7, location = sui_payment_standard)]
fun test_invalid_registry_name_starts_with_hyphen() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_payment_standard::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_payment_standard::Namespace>(&scenario);

        // Should fail - starts with hyphen
        let (registry, cap) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"-testregistry"),
            test_scenario::ctx(&mut scenario),
        );
        test_utils::destroy(registry);
        test_utils::destroy(cap);

        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests that creating registry with names ending with hyphen fails.
#[test, expected_failure(abort_code = 7, location = sui_payment_standard)]
fun test_invalid_registry_name_ends_with_hyphen() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_payment_standard::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_payment_standard::Namespace>(&scenario);

        // Should fail - ends with hyphen
        let (registry, cap) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"testregistry-"),
            test_scenario::ctx(&mut scenario),
        );
        test_utils::destroy(registry);
        test_utils::destroy(cap);

        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests creating registry with valid hyphenated names.
#[test]
fun test_valid_registry_name_with_hyphens() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_payment_standard::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_payment_standard::Namespace>(&scenario);

        // Valid names with hyphens in the middle
        let (registry1, cap1) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"my-registry"),
            test_scenario::ctx(&mut scenario),
        );
        test_utils::destroy(registry1);
        test_utils::destroy(cap1);

        let (registry2, cap2) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"test-payment-system"),
            test_scenario::ctx(&mut scenario),
        );
        test_utils::destroy(registry2);
        test_utils::destroy(cap2);

        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests that creating registry with uppercase letters fails.
#[test, expected_failure(abort_code = 7, location = sui_payment_standard)]
fun test_invalid_registry_name_uppercase() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_payment_standard::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_payment_standard::Namespace>(&scenario);

        // Should fail - contains uppercase letters
        let (registry, cap) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"MyRegistry"),
            test_scenario::ctx(&mut scenario),
        );
        test_utils::destroy(registry);
        test_utils::destroy(cap);

        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests that empty nonce fails with EInvalidNonce error.
#[test, expected_failure(abort_code = 8, location = sui_payment_standard)]
fun test_empty_nonce_failure() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_payment_standard::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_payment_standard::Namespace>(&scenario);
        let (mut registry, cap) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"testregistry"),
            test_scenario::ctx(&mut scenario),
        );
        let coin = create_test_coin(&mut scenario, 1000);
        let clock = create_test_clock(&mut scenario);

        let _receipt = sui_payment_standard::process_payment_in_registry<SUI>(
            &mut registry,
            std::ascii::string(b""), // Empty nonce - should fail
            1000,
            coin,
            BOB,
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        test_utils::destroy(clock);
        test_utils::destroy(registry);
        test_utils::destroy(cap);
        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests that nonce longer than 36 characters fails with EInvalidNonce error.
#[test, expected_failure(abort_code = 8, location = sui_payment_standard)]
fun test_nonce_too_long_failure() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_payment_standard::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_payment_standard::Namespace>(&scenario);
        let (mut registry, cap) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"testregistry"),
            test_scenario::ctx(&mut scenario),
        );
        let coin = create_test_coin(&mut scenario, 1000);
        let clock = create_test_clock(&mut scenario);

        let _receipt = sui_payment_standard::process_payment_in_registry<SUI>(
            &mut registry,
            std::ascii::string(b"1234567890123456789012345678901234567"), // 37 characters - should fail
            1000,
            coin,
            BOB,
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        test_utils::destroy(clock);
        test_utils::destroy(registry);
        test_utils::destroy(cap);
        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests that valid nonce lengths (1 and 36 characters) work correctly.
#[test]
fun test_valid_nonce_lengths() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        sui_payment_standard::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let mut namespace = test_scenario::take_shared<sui_payment_standard::Namespace>(&scenario);
        let (mut registry, cap) = sui_payment_standard::create_registry(
            &mut namespace,
            std::ascii::string(b"testregistry"),
            test_scenario::ctx(&mut scenario),
        );
        let clock = create_test_clock(&mut scenario);

        // Test minimum length (1 character)
        let coin1 = create_test_coin(&mut scenario, 1000);
        let _receipt1 = sui_payment_standard::process_payment_in_registry<SUI>(
            &mut registry,
            std::ascii::string(b"1"), // 1 character - should work
            1000,
            coin1,
            BOB,
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        // Test maximum length (36 characters)
        let coin2 = create_test_coin(&mut scenario, 500);
        let _receipt2 = sui_payment_standard::process_payment_in_registry<SUI>(
            &mut registry,
            std::ascii::string(b"123456789012345678901234567890123456"), // 36 characters - should work
            500,
            coin2,
            CHARLIE,
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        test_utils::destroy(clock);
        test_utils::destroy(registry);
        test_utils::destroy(cap);
        test_scenario::return_shared(namespace);
    };

    test_scenario::end(scenario);
}

/// Tests the standalone process_payment function without registry.
#[test]
fun test_process_payment_standalone() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let coin = create_test_coin(&mut scenario, 1500);
        let clock = create_test_clock(&mut scenario);

        let _receipt = sui_payment_standard::process_payment<SUI>(
            std::ascii::string(b"standalone-payment"),
            1500,
            coin,
            BOB,
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        test_utils::destroy(clock);
    };

    test_scenario::end(scenario);
}

/// Tests the standalone process_payment function with invalid nonce.
#[test, expected_failure(abort_code = 8, location = sui_payment_standard)]
fun test_process_payment_standalone_invalid_nonce() {
    let mut scenario = setup_test_scenario();

    test_scenario::next_tx(&mut scenario, ALICE);
    {
        let coin = create_test_coin(&mut scenario, 1000);
        let clock = create_test_clock(&mut scenario);

        let _receipt = sui_payment_standard::process_payment<SUI>(
            std::ascii::string(b""), // Empty nonce - should fail
            1000,
            coin,
            BOB,
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        test_utils::destroy(clock);
    };

    test_scenario::end(scenario);
}
