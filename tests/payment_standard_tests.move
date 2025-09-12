#[test_only]
module sui_payment_standard::payment_standard_tests;

use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::test_scenario::{Self, Scenario};
use sui::test_utils;
use sui_payment_standard::payment_standard;

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

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);
    let (registry, cap) = namespace.create_registry(
        b"testregistry".to_ascii_string(),
        scenario.ctx(),
    );

    test_utils::destroy(registry);
    test_utils::destroy(cap);
    test_scenario::return_shared(namespace);

    test_scenario::end(scenario);
}

/// Tests processing a payment where the coin amount exactly matches the payment amount.
#[test]
fun test_successful_payment_exact_amount() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);
    let (mut registry, cap) = namespace.create_registry(
        b"testregistry".to_ascii_string(),
        scenario.ctx(),
    );
    let coin = create_test_coin(&mut scenario, 1000);
    let clock = create_test_clock(&mut scenario);

    let _receipt = registry.process_payment_in_registry<SUI>(
        std::ascii::string(b"12345"), // payment_id
        1000, // payment_amount
        coin,
        std::option::some(BOB),
        &clock,
        scenario.ctx(),
    );

    // Payment completed successfully - nonce is now recorded
    test_utils::destroy(clock);
    test_utils::destroy(registry);
    test_utils::destroy(cap);
    test_scenario::return_shared(namespace);

    test_scenario::end(scenario);
}

/// Tests that providing more coin amount than payment amount fails.
#[test, expected_failure(abort_code = payment_standard::EIncorrectAmount)]
fun test_overpayment_failure() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());
    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);
    let (mut registry, _cap) = namespace.create_registry(
        b"testregistry".to_ascii_string(),
        scenario.ctx(),
    );
    let coin = create_test_coin(&mut scenario, 1500); // More than expected
    let clock = create_test_clock(&mut scenario);

    let _receipt = registry.process_payment_in_registry<SUI>(
        std::ascii::string(b"67890"), // nonce
        1000, // payment_amount - less than coin value
        coin,
        std::option::some(BOB),
        &clock,
        scenario.ctx(),
    );

    abort
}

/// Tests that using identical payment parameters fails.
#[test, expected_failure(abort_code = payment_standard::EPaymentAlreadyExists)]
fun test_duplicate_payment_hash_failure() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = scenario.take_shared<payment_standard::Namespace>();
    let (mut registry, cap) = namespace.create_registry(
        b"testregistry".to_ascii_string(),
        scenario.ctx(),
    );

    // Set config to enable payment record writing
    registry.set_config_epoch_expiration_duration(
        &cap,
        0, // epoch_expiration_duration
        scenario.ctx(),
    );
    registry.set_config_registry_managed_funds(
        &cap,
        false, // registry_managed_funds
        scenario.ctx(),
    );

    let coin1 = create_test_coin(&mut scenario, 1000);
    let coin2 = create_test_coin(&mut scenario, 1000);
    let clock = create_test_clock(&mut scenario);

    // First payment with specific parameters should succeed
    let _receipt1 = registry.process_payment_in_registry<SUI>(
        std::ascii::string(b"12345"),
        1000, // payment_amount
        coin1,
        std::option::some(BOB),
        &clock,
        scenario.ctx(),
    );

    // Second payment with identical parameters should fail (same hash)
    let _receipt2 = registry.process_payment_in_registry<SUI>(
        std::ascii::string(b"12345"), // Same nonce
        1000, // Same payment_amount
        coin2,
        std::option::some(BOB), // Same receiver
        &clock,
        scenario.ctx(),
    );

    abort
}

/// Tests that providing insufficient coin amount fails
#[test, expected_failure(abort_code = payment_standard::EIncorrectAmount)]
fun test_insufficient_amount_failure() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);

    let mut namespace = scenario.take_shared<payment_standard::Namespace>();
    let (mut registry, _cap) = namespace.create_registry(
        b"testregistry".to_ascii_string(),
        scenario.ctx(),
    );
    let coin = create_test_coin(&mut scenario, 500); // Less than expected
    let clock = create_test_clock(&mut scenario);

    let _receipt = registry.process_payment_in_registry<SUI>(
        std::ascii::string(b"12345"),
        1000, // Expected 1000 but coin only has 500
        coin,
        std::option::some(BOB),
        &clock,
        scenario.ctx(),
    );

    abort
}

/// Tests processing multiple payments with different nonces successfully.
#[test]
fun test_multiple_different_nonces() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);
    let (mut registry, cap) = namespace.create_registry(
        b"testregistry".to_ascii_string(),
        scenario.ctx(),
    );

    // Process multiple payments with different nonce values
    let clock = create_test_clock(&mut scenario);

    let coin1 = create_test_coin(&mut scenario, 1000);
    let _receipt1 = registry.process_payment_in_registry<SUI>(
        std::ascii::string(b"1"),
        1000,
        coin1,
        std::option::some(BOB),
        &clock,
        scenario.ctx(),
    );

    let coin2 = create_test_coin(&mut scenario, 1500);
    let _receipt2 = registry.process_payment_in_registry<SUI>(
        std::ascii::string(b"2"),
        1500,
        coin2,
        std::option::some(CHARLIE),
        &clock,
        scenario.ctx(),
    );

    let coin3 = create_test_coin(&mut scenario, 500);
    let _receipt3 = registry.process_payment_in_registry<SUI>(
        std::ascii::string(b"3"),
        500,
        coin3,
        std::option::some(BOB),
        &clock,
        scenario.ctx(),
    );

    // All payments completed successfully with different nonces
    test_utils::destroy(clock);
    test_utils::destroy(registry);
    test_utils::destroy(cap);
    test_scenario::return_shared(namespace);

    test_scenario::end(scenario);
}

/// Tests processing a payment with zero payment amount (entire amount becomes tip).
#[test]
fun test_zero_payment_amount() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);
    let (mut registry, cap) = namespace.create_registry(
        b"testregistry".to_ascii_string(),
        scenario.ctx(),
    );
    let coin = create_test_coin(&mut scenario, 1000);
    let clock = create_test_clock(&mut scenario);

    let _receipt = registry.process_payment_in_registry<SUI>(
        std::ascii::string(b"12345"),
        1000, // payment amount
        coin,
        std::option::some(BOB),
        &clock,
        scenario.ctx(),
    );

    // Payment with zero payment amount completed successfully

    test_utils::destroy(clock);
    test_utils::destroy(registry);
    test_utils::destroy(cap);
    test_scenario::return_shared(namespace);

    test_scenario::end(scenario);
}

/// Tests processing a payment with maximum u64 nonce value.
#[test]
fun test_large_nonce_values() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);
    let (mut registry, cap) = namespace.create_registry(
        b"testregistry".to_ascii_string(),
        scenario.ctx(),
    );

    // Test with large nonce value
    let coin = create_test_coin(&mut scenario, 1000);
    let clock = create_test_clock(&mut scenario);

    let _receipt = registry.process_payment_in_registry<SUI>(
        std::ascii::string(b"18446744073709551615"), // Large nonce
        1000,
        coin,
        std::option::some(BOB),
        &clock,
        scenario.ctx(),
    );

    // Payment with large nonce completed successfully
    test_utils::destroy(clock);
    test_utils::destroy(registry);
    test_utils::destroy(cap);
    test_scenario::return_shared(namespace);

    test_scenario::end(scenario);
}

/// Tests successfully deleting an expired payment record (expiration duration = 0 epochs).
#[test]
fun test_delete_expired_payment_record_success() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);
    let (mut registry, cap) = namespace.create_registry(
        b"testregistry".to_ascii_string(),
        scenario.ctx(),
    );

    // Set config to enable payment record writing with 0 epoch expiration
    registry.set_config_epoch_expiration_duration(
        &cap,
        0, // epoch_expiration_duration
        scenario.ctx(),
    );
    registry.set_config_registry_managed_funds(
        &cap,
        false, // registry_managed_funds
        scenario.ctx(),
    );

    let coin = create_test_coin(&mut scenario, 1000);
    let clock = create_test_clock(&mut scenario);

    let payment_id = std::ascii::string(b"12345");
    let payment_amount = 1000;
    let receiver = BOB;

    let _receipt = registry.process_payment_in_registry<SUI>(
        payment_id,
        payment_amount,
        coin,
        std::option::some(receiver),
        &clock,
        scenario.ctx(),
    );

    // Create payment record key to delete the record
    let payment_record_key = payment_standard::create_payment_key<SUI>(
        payment_id,
        payment_amount,
        receiver,
    );

    registry.delete_payment_record<SUI>(
        payment_record_key,
        scenario.ctx(),
    );
    test_utils::destroy(clock);
    test_utils::destroy(registry);
    test_utils::destroy(cap);
    test_scenario::return_shared(namespace);

    test_scenario::end(scenario);
}

/// Tests that deleting a non-existent payment record fails.
#[test, expected_failure(abort_code = payment_standard::EPaymentRecordDoesNotExist)]
fun test_delete_nonexistent_payment_record() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);
    let (mut registry, cap) = namespace.create_registry(
        b"testregistry".to_ascii_string(),
        scenario.ctx(),
    );

    // Set config to enable payment record writing
    registry.set_config_epoch_expiration_duration(
        &cap,
        1000, // epoch_expiration_duration
        scenario.ctx(),
    );
    registry.set_config_registry_managed_funds(
        &cap,
        false, // registry_managed_funds
        scenario.ctx(),
    );

    // Create a fake payment record key for a non-existent record
    let fake_payment_record_key = payment_standard::create_payment_key<SUI>(
        std::ascii::string(b"99999"),
        1000,
        BOB,
    );

    registry.delete_payment_record<SUI>(
        fake_payment_record_key,
        scenario.ctx(),
    );

    abort
}

/// Tests that deleting a payment record before expiration fails.
#[test, expected_failure(abort_code = payment_standard::EPaymentRecordHasNotExpired)]
fun test_delete_payment_record_not_expired() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);
    let (mut registry, cap) = namespace.create_registry(
        b"testregistry".to_ascii_string(),
        scenario.ctx(),
    );

    // Set config to enable payment record writing with large epoch expiration
    registry.set_config_epoch_expiration_duration(
        &cap,
        10000, // epoch_expiration_duration
        scenario.ctx(),
    );
    registry.set_config_registry_managed_funds(
        &cap,
        false, // registry_managed_funds
        scenario.ctx(),
    );
    let coin = create_test_coin(&mut scenario, 1000);
    let clock = create_test_clock(&mut scenario);

    let payment_id = std::ascii::string(b"12345");
    let payment_amount = 1000;
    let receiver = BOB;

    let _receipt = registry.process_payment_in_registry<SUI>(
        payment_id,
        payment_amount,
        coin,
        std::option::some(receiver),
        &clock,
        scenario.ctx(),
    );

    // Create payment record key to delete the record
    let payment_record_key = payment_standard::create_payment_key<SUI>(
        payment_id,
        payment_amount,
        receiver,
    );

    registry.delete_payment_record<SUI>(
        payment_record_key,
        scenario.ctx(),
    );

    abort
}

/// Tests that deleting a payment record succeeds when expiration duration is 0 epochs (immediate expiration).
#[test]
fun test_delete_payment_record_immediate_expiration() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);
    let (mut registry, cap) = namespace.create_registry(
        b"testregistry".to_ascii_string(),
        scenario.ctx(),
    );

    // Set config to enable payment record writing with immediate expiration
    registry.set_config_epoch_expiration_duration(
        &cap,
        0, // epoch_expiration_duration - 0 means immediate expiration
        scenario.ctx(),
    );
    registry.set_config_registry_managed_funds(
        &cap,
        false, // registry_managed_funds
        scenario.ctx(),
    );
    let coin = create_test_coin(&mut scenario, 1000);
    let clock = create_test_clock(&mut scenario);

    let payment_id = std::ascii::string(b"12345");
    let payment_amount = 1000;
    let receiver = BOB;

    let _receipt = registry.process_payment_in_registry<SUI>(
        payment_id,
        payment_amount,
        coin,
        std::option::some(receiver),
        &clock,
        scenario.ctx(),
    );

    // Create payment record key to delete the record
    let payment_record_key = payment_standard::create_payment_key<SUI>(
        payment_id,
        payment_amount,
        receiver,
    );

    registry.delete_payment_record<SUI>(
        payment_record_key,
        scenario.ctx(),
    );

    test_utils::destroy(clock);
    test_utils::destroy(registry);
    test_utils::destroy(cap);
    test_scenario::return_shared(namespace);

    test_scenario::end(scenario);
}

/// Tests that deleting a payment record fails when using 30 epoch expiration duration.
#[test, expected_failure(abort_code = payment_standard::EPaymentRecordHasNotExpired)]
fun test_30_epoch_expiration_duration() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);
    let (mut registry, cap) = namespace.create_registry(
        b"testregistry".to_ascii_string(),
        scenario.ctx(),
    );

    // Set config to enable payment record writing with 30 epoch expiration
    registry.set_config_epoch_expiration_duration(
        &cap,
        30, // epoch_expiration_duration (30 epochs)
        scenario.ctx(),
    );
    registry.set_config_registry_managed_funds(
        &cap,
        false, // registry_managed_funds
        scenario.ctx(),
    );
    let coin = create_test_coin(&mut scenario, 1000);
    let clock = create_test_clock(&mut scenario);

    let payment_id = std::ascii::string(b"12345");
    let payment_amount = 1000;
    let receiver = BOB;

    let _receipt = registry.process_payment_in_registry<SUI>(
        payment_id,
        payment_amount,
        coin,
        std::option::some(receiver),
        &clock,
        scenario.ctx(),
    );

    // Create payment record key to delete the record
    let payment_record_key = payment_standard::create_payment_key<SUI>(
        payment_id,
        payment_amount,
        receiver,
    );

    registry.delete_payment_record<SUI>(
        payment_record_key,
        scenario.ctx(),
    );

    abort
}

/// Tests creating registry with valid alphanumeric names.
#[test]
fun test_valid_registry_names() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);

    // Test various valid SuiNS-compliant names
    let (registry1, cap1) = namespace.create_registry(
        std::ascii::string(b"test123"),
        scenario.ctx(),
    );
    test_utils::destroy(registry1);
    test_utils::destroy(cap1);

    let (registry2, cap2) = namespace.create_registry(
        std::ascii::string(b"abc"),
        scenario.ctx(),
    );
    test_utils::destroy(registry2);
    test_utils::destroy(cap2);

    let (registry3, cap3) = namespace.create_registry(
        std::ascii::string(b"test-registry-123"),
        scenario.ctx(),
    );
    test_utils::destroy(registry3);
    test_utils::destroy(cap3);

    test_scenario::return_shared(namespace);

    test_scenario::end(scenario);
}

/// Tests that creating registry with special characters fails.
#[test, expected_failure(abort_code = payment_standard::ERegistryNameContainsInvalidCharacters)]
fun test_invalid_registry_name_special_chars() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);

    // Should fail - contains underscore (not allowed in SuiNS)
    let (_registry, _cap) = namespace.create_registry(
        std::ascii::string(b"test_registry"),
        scenario.ctx(),
    );

    abort
}

/// Tests that creating registry with too long name fails.
#[test, expected_failure(abort_code = payment_standard::ERegistryNameLengthIsNotAllowed)]
fun test_invalid_registry_name_too_long() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);

    // Should fail - 64 characters (exceeds 63 character SuiNS limit)
    let (_registry, _cap) = namespace.create_registry(
        std::ascii::string(b"1234567890123456789012345678901234567890123456789012345678901234"),
        scenario.ctx(),
    );

    abort
}

/// Tests that creating registry with empty name fails.
#[test, expected_failure(abort_code = payment_standard::ERegistryNameLengthIsNotAllowed)]
fun test_invalid_registry_name_empty() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);

    // Should fail - too short (less than 3 characters)
    let (_registry, _cap) = namespace.create_registry(
        std::ascii::string(b"ab"),
        scenario.ctx(),
    );

    abort
}

/// Tests setting payment record config as admin.
#[test]
fun test_set_config_success() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);
    let (mut registry, cap) = namespace.create_registry(
        b"testregistry".to_ascii_string(),
        scenario.ctx(),
    );

    registry.set_config_epoch_expiration_duration(
        &cap,
        1000, // epoch_expiration_duration
        scenario.ctx(),
    );
    registry.set_config_registry_managed_funds(
        &cap,
        false, // registry_managed_funds
        scenario.ctx(),
    );

    test_utils::destroy(registry);
    test_utils::destroy(cap);
    test_scenario::return_shared(namespace);

    test_scenario::end(scenario);
}

/// Tests that setting config fails when caller is not admin.
#[test, expected_failure(abort_code = payment_standard::EUnauthorizedAdmin)]
fun test_set_config_unauthorized() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(BOB);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);
    let (mut registry, _bob_cap) = namespace.create_registry(
        b"testregistry".to_ascii_string(),
        scenario.ctx(),
    );

    test_scenario::return_shared(namespace);

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(
        &scenario,
    );
    let (alice_registry, alice_cap) = namespace.create_registry(
        std::ascii::string(b"aliceregistry"),
        scenario.ctx(),
    );
    test_utils::destroy(alice_registry);

    // ALICE tries to set config on BOB's registry with her cap - should fail
    registry.set_config_epoch_expiration_duration(
        &alice_cap,
        1000, // epoch_expiration_duration
        scenario.ctx(),
    );

    abort
}

/// Tests that creating registry with names starting with hyphen fails.
#[test, expected_failure(abort_code = payment_standard::ERegistryNameContainsInvalidCharacters)]
fun test_invalid_registry_name_starts_with_hyphen() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);

    // Should fail - starts with hyphen
    let (_registry, _cap) = namespace.create_registry(
        std::ascii::string(b"-testregistry"),
        scenario.ctx(),
    );

    abort
}

/// Tests that creating registry with names ending with hyphen fails.
#[test, expected_failure(abort_code = payment_standard::ERegistryNameContainsInvalidCharacters)]
fun test_invalid_registry_name_ends_with_hyphen() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);

    // Should fail - ends with hyphen
    let (_registry, _cap) = namespace.create_registry(
        std::ascii::string(b"testregistry-"),
        scenario.ctx(),
    );

    abort
}

/// Tests creating registry with valid hyphenated names.
#[test]
fun test_valid_registry_name_with_hyphens() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);

    // Valid names with hyphens in the middle
    let (registry1, cap1) = namespace.create_registry(
        b"my-registry".to_ascii_string(),
        scenario.ctx(),
    );
    test_utils::destroy(registry1);
    test_utils::destroy(cap1);

    let (registry2, cap2) = namespace.create_registry(
        std::ascii::string(b"test-payment-system"),
        scenario.ctx(),
    );
    test_utils::destroy(registry2);
    test_utils::destroy(cap2);

    test_scenario::return_shared(namespace);

    test_scenario::end(scenario);
}

/// Tests that creating registry with uppercase letters fails.
#[test, expected_failure(abort_code = payment_standard::ERegistryNameContainsInvalidCharacters)]
fun test_invalid_registry_name_uppercase() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);

    // Should fail - contains uppercase letters
    let (_registry, _cap) = namespace.create_registry(
        std::ascii::string(b"MyRegistry"),
        scenario.ctx(),
    );

    abort
}

/// Tests that empty nonce fails
#[test, expected_failure(abort_code = payment_standard::EInvalidNonce)]
fun test_empty_nonce_failure() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);
    let (mut registry, _cap) = namespace.create_registry(
        b"testregistry".to_ascii_string(),
        scenario.ctx(),
    );
    let coin = create_test_coin(&mut scenario, 1000);
    let clock = create_test_clock(&mut scenario);

    let _receipt = registry.process_payment_in_registry<SUI>(
        std::ascii::string(b""), // Empty nonce - should fail
        1000,
        coin,
        std::option::some(BOB),
        &clock,
        scenario.ctx(),
    );

    abort
}

/// Tests that nonce longer than 36 characters fails.
#[test, expected_failure(abort_code = payment_standard::EInvalidNonce)]
fun test_nonce_too_long_failure() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);
    let (mut registry, _cap) = namespace.create_registry(
        b"testregistry".to_ascii_string(),
        scenario.ctx(),
    );
    let coin = create_test_coin(&mut scenario, 1000);
    let clock = create_test_clock(&mut scenario);

    let _receipt = registry.process_payment_in_registry<SUI>(
        std::ascii::string(b"1234567890123456789012345678901234567"), // 37 characters - should fail
        1000,
        coin,
        std::option::some(BOB),
        &clock,
        scenario.ctx(),
    );

    abort
}

/// Tests that valid nonce lengths (1 and 36 characters) work correctly.
#[test]
fun test_valid_nonce_lengths() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);
    let (mut registry, cap) = namespace.create_registry(
        b"testregistry".to_ascii_string(),
        scenario.ctx(),
    );
    let clock = create_test_clock(&mut scenario);

    // Test minimum length (1 character)
    let coin1 = create_test_coin(&mut scenario, 1000);
    let _receipt1 = registry.process_payment_in_registry<SUI>(
        std::ascii::string(b"1"), // 1 character - should work
        1000,
        coin1,
        std::option::some(BOB),
        &clock,
        scenario.ctx(),
    );

    // Test maximum length (36 characters)
    let coin2 = create_test_coin(&mut scenario, 500);
    let _receipt2 = registry.process_payment_in_registry<SUI>(
        std::ascii::string(b"123456789012345678901234567890123456"), // 36 characters - should work
        500,
        coin2,
        std::option::some(CHARLIE),
        &clock,
        scenario.ctx(),
    );

    test_utils::destroy(clock);
    test_utils::destroy(registry);
    test_utils::destroy(cap);
    test_scenario::return_shared(namespace);

    test_scenario::end(scenario);
}

/// Tests the standalone process_ephemeral_payment function without registry.
#[test]
fun test_process_ephemeral_payment_standalone() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    let coin = create_test_coin(&mut scenario, 1500);
    let clock = create_test_clock(&mut scenario);

    let _receipt = payment_standard::process_ephemeral_payment<SUI>(
        std::ascii::string(b"ephemeral-payment"),
        1500,
        coin,
        BOB,
        &clock,
        scenario.ctx(),
    );

    test_utils::destroy(clock);

    test_scenario::end(scenario);
}

/// Tests the standalone process_ephemeral_payment function with an invalid nonce.
#[test, expected_failure(abort_code = payment_standard::EInvalidNonce)]
fun test_process_ephemeral_payment_standalone_invalid_nonce() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    let coin = create_test_coin(&mut scenario, 1000);
    let clock = create_test_clock(&mut scenario);

    let _receipt = payment_standard::process_ephemeral_payment<SUI>(
        std::ascii::string(b""), // Empty nonce - should fail
        1000,
        coin,
        BOB,
        &clock,
        scenario.ctx(),
    );

    abort
}


/// Tests processing a payment with registry_managed_funds enabled and no receiver specified.
#[test]
fun test_registry_managed_funds_no_receiver() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);
    let (mut registry, cap) = namespace.create_registry(
        b"testregistry".to_ascii_string(),
        scenario.ctx(),
    );

    // Enable registry managed funds
    registry.set_config_registry_managed_funds(
        &cap,
        true,
        scenario.ctx(),
    );

    let coin = create_test_coin(&mut scenario, 1000);
    let clock = create_test_clock(&mut scenario);

    // Process payment with no receiver (should default to registry)
    let _receipt = registry.process_payment_in_registry<SUI>(
        std::ascii::string(b"12345"),
        1000,
        coin,
        std::option::none(), // No receiver specified
        &clock,
        scenario.ctx(),
    );

    // Withdraw the funds from the registry
    let withdrawn_coin = registry.withdraw_from_registry<SUI>(&cap, scenario.ctx());
    assert!(withdrawn_coin.value() == 1000, 0);

    test_utils::destroy(withdrawn_coin);
    test_utils::destroy(clock);
    test_utils::destroy(registry);
    test_utils::destroy(cap);
    test_scenario::return_shared(namespace);

    test_scenario::end(scenario);
}

/// Tests processing a payment with registry_managed_funds enabled and registry as receiver.
#[test]
fun test_registry_managed_funds_registry_as_receiver() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);
    let (mut registry, cap) = namespace.create_registry(
        b"testregistry".to_ascii_string(),
        scenario.ctx(),
    );

    // Enable registry managed funds
    registry.set_config_registry_managed_funds(
        &cap,
        true,
        scenario.ctx(),
    );

    let registry_address = object::id_address(&registry);
    let coin = create_test_coin(&mut scenario, 2000);
    let clock = create_test_clock(&mut scenario);

    // Process payment with registry as receiver
    let _receipt = registry.process_payment_in_registry<SUI>(
        std::ascii::string(b"67890"),
        2000,
        coin,
        std::option::some(registry_address), // Registry as receiver
        &clock,
        scenario.ctx(),
    );

    // Withdraw the funds from the registry
    let withdrawn_coin = registry.withdraw_from_registry<SUI>(&cap, scenario.ctx());
    assert!(withdrawn_coin.value() == 2000, 0);

    test_utils::destroy(withdrawn_coin);
    test_utils::destroy(clock);
    test_utils::destroy(registry);
    test_utils::destroy(cap);
    test_scenario::return_shared(namespace);

    test_scenario::end(scenario);
}

/// Tests that providing a different receiver fails when registry_managed_funds is enabled.
#[test, expected_failure(abort_code = payment_standard::ERegistryMustBeReceiver)]
fun test_registry_managed_funds_invalid_receiver() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);
    let (mut registry, cap) = namespace.create_registry(
        b"testregistry".to_ascii_string(),
        scenario.ctx(),
    );

    // Enable registry managed funds
    registry.set_config_registry_managed_funds(
        &cap,
        true,
        scenario.ctx(),
    );

    let coin = create_test_coin(&mut scenario, 1000);
    let clock = create_test_clock(&mut scenario);

    // Process payment with different receiver (should fail)
    let _receipt = registry.process_payment_in_registry<SUI>(
        std::ascii::string(b"12345"),
        1000,
        coin,
        std::option::some(BOB), // Different receiver - should fail
        &clock,
        scenario.ctx(),
    );

    abort
}

/// Tests that receiver must be provided when registry_managed_funds is disabled.
#[test, expected_failure(abort_code = payment_standard::EReceiverMustBeProvided)]
fun test_receiver_required_when_funds_not_managed() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);
    let (mut registry, cap) = namespace.create_registry(
        b"testregistry".to_ascii_string(),
        scenario.ctx(),
    );

    // Explicitly disable registry managed funds
    registry.set_config_registry_managed_funds(
        &cap,
        false,
        scenario.ctx(),
    );

    let coin = create_test_coin(&mut scenario, 1000);
    let clock = create_test_clock(&mut scenario);

    // Process payment with no receiver (should fail when funds not managed)
    let _receipt = registry.process_payment_in_registry<SUI>(
        std::ascii::string(b"12345"),
        1000,
        coin,
        std::option::none(), // No receiver - should fail
        &clock,
        scenario.ctx(),
    );

    abort
}

/// Tests processing multiple payments and withdrawing accumulated funds.
#[test]
fun test_registry_managed_funds_multiple_payments() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);
    let (mut registry, cap) = namespace.create_registry(
        b"testregistry".to_ascii_string(),
        scenario.ctx(),
    );

    // Enable registry managed funds
    registry.set_config_registry_managed_funds(
        &cap,
        true,
        scenario.ctx(),
    );

    let clock = create_test_clock(&mut scenario);

    // Process multiple payments
    let coin1 = create_test_coin(&mut scenario, 1000);
    let _receipt1 = registry.process_payment_in_registry<SUI>(
        std::ascii::string(b"payment1"),
        1000,
        coin1,
        std::option::none(),
        &clock,
        scenario.ctx(),
    );

    let coin2 = create_test_coin(&mut scenario, 2000);
    let _receipt2 = registry.process_payment_in_registry<SUI>(
        std::ascii::string(b"payment2"),
        2000,
        coin2,
        std::option::none(),
        &clock,
        scenario.ctx(),
    );

    let coin3 = create_test_coin(&mut scenario, 1500);
    let _receipt3 = registry.process_payment_in_registry<SUI>(
        std::ascii::string(b"payment3"),
        1500,
        coin3,
        std::option::none(),
        &clock,
        scenario.ctx(),
    );

    // Withdraw all accumulated funds
    let withdrawn_coin = registry.withdraw_from_registry<SUI>(&cap, scenario.ctx());
    assert!(withdrawn_coin.value() == 4500, 0); // 1000 + 2000 + 1500

    test_utils::destroy(withdrawn_coin);
    test_utils::destroy(clock);
    test_utils::destroy(registry);
    test_utils::destroy(cap);
    test_scenario::return_shared(namespace);

    test_scenario::end(scenario);
}

/// Tests that withdrawing from registry requires admin capability.
#[test, expected_failure(abort_code = payment_standard::EUnauthorizedAdmin)]
fun test_registry_withdraw_unauthorized() {
    let mut scenario = setup_test_scenario();

    scenario.next_tx(ALICE);
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    let mut namespace = test_scenario::take_shared<payment_standard::Namespace>(&scenario);
    let (_alice_registry, alice_cap) = namespace.create_registry(
        b"aliceregistry".to_ascii_string(),
        scenario.ctx(),
    );
    
    scenario.next_tx(BOB);
    let (mut bob_registry, _bob_cap) = namespace.create_registry(
        b"bobregistry".to_ascii_string(),
        scenario.ctx(),
    );

    // Enable registry managed funds on Bob's registry
    bob_registry.set_config_registry_managed_funds(
        &_bob_cap,
        true,
        scenario.ctx(),
    );

    let coin = create_test_coin(&mut scenario, 1000);
    let clock = create_test_clock(&mut scenario);

    // Process payment to Bob's registry
    let _receipt = bob_registry.process_payment_in_registry<SUI>(
        std::ascii::string(b"12345"),
        1000,
        coin,
        std::option::none(),
        &clock,
        scenario.ctx(),
    );

    // Try to withdraw from Bob's registry using Alice's cap (should fail)
    let _withdrawn = bob_registry.withdraw_from_registry<SUI>(&alice_cap, scenario.ctx());

    abort
}
