#[test_only]
#[allow(unused_mut_ref, unused_variable, dead_code)]
module sui_payment_standard::payment_standard_tests;

use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::test_scenario::{Self, Scenario};
use sui::test_utils;
use sui_payment_standard::payment_standard::{Self, Namespace, PaymentRegistry, RegistryAdminCap};

const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;
const CHARLIE: address = @0xC;

// macro fun test_tx(|)

/// Sets up a new test scenario with ALICE as the initial sender.
///
/// # Returns
/// A new Scenario instance for testing
fun setup_test_scenario(): Scenario {
    let mut scenario = test_scenario::begin(ALICE);

    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    scenario
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
    coin::mint_for_testing<SUI>(amount, scenario.ctx())
}

/// Creates a test clock for testing time-dependent functionality.
///
/// # Parameters
/// * `scenario` - Test scenario to use for clock creation
///
/// # Returns
/// A Clock instance for testing
fun create_test_clock(scenario: &mut Scenario): Clock {
    clock::create_for_testing(scenario.ctx())
}

/// Tests creating a payment registry with no expiration duration.
#[test]
fun test_create_registry() {
    test_tx!(|scenario, _clock, _registry, namespace| {
        let (registry, cap) = namespace.create_registry(
            b"testregistry".to_ascii_string(),
            scenario.ctx(),
        );
        test_utils::destroy(registry);
        test_utils::destroy(cap);
    });
}

/// Tests processing a payment where the coin amount exactly matches the payment amount.
#[test]
fun test_successful_payment_exact_amount() {
    test_tx!(|scenario, clock, registry, namespace| {
        let coin = create_test_coin(scenario, 1000);
        let _receipt = registry.process_payment_in_registry<SUI>(
            b"12345".to_ascii_string(), // payment_id
            1000, // payment_amount
            coin,
            option::some(BOB),
            clock,
            scenario.ctx(),
        );
    });
}

/// Tests that providing more coin amount than payment amount fails.
#[test, expected_failure(abort_code = payment_standard::EIncorrectAmount)]
fun test_overpayment_failure() {
    test_tx!(|scenario, clock, registry, namespace| {
        let coin = create_test_coin(scenario, 1500);
        let _receipt = registry.process_payment_in_registry<SUI>(
            b"12345".to_ascii_string(), // payment_id
            1000, // payment_amount
            coin,
            option::some(BOB),
            clock,
            scenario.ctx(),
        );
    });
}

/// Tests that using identical payment parameters fails.
#[test, expected_failure(abort_code = payment_standard::EPaymentAlreadyExists)]
fun test_duplicate_payment_hash_failure() {
    test_tx!(|scenario, clock, registry, namespace| {
        let _receipt = registry.process_payment_in_registry<SUI>(
            b"12345".to_ascii_string(), // payment_id
            1000, // payment_amount
            create_test_coin(scenario, 1000),
            option::some(BOB),
            clock,
            scenario.ctx(),
        );

        let _receipt = registry.process_payment_in_registry<SUI>(
            b"12345".to_ascii_string(), // payment_id
            1000, // payment_amount
            create_test_coin(scenario, 1000),
            option::some(BOB),
            clock,
            scenario.ctx(),
        );
    });
}

/// Tests that providing insufficient coin amount fails
#[test, expected_failure(abort_code = payment_standard::EIncorrectAmount)]
fun test_insufficient_amount_failure() {
    test_tx!(|scenario, clock, registry, namespace| {
        let _receipt = registry.process_payment_in_registry<SUI>(
            b"12345".to_ascii_string(),
            1000, // Expected 1000 but coin only has 500
            create_test_coin(scenario, 500), // less than expected
            option::some(BOB),
            clock,
            scenario.ctx(),
        );
    });
}

/// Tests processing multiple payments with different nonces successfully.
#[test]
fun test_multiple_different_nonces() {
    test_tx!(|scenario, clock, registry, namespace| {
        let _receipt1 = registry.process_payment_in_registry<SUI>(
            b"1".to_ascii_string(),
            1000,
            create_test_coin(scenario, 1000),
            option::some(BOB),
            clock,
            scenario.ctx(),
        );

        let _receipt2 = registry.process_payment_in_registry<SUI>(
            b"2".to_ascii_string(),
            1500,
            create_test_coin(scenario, 1500),
            option::some(CHARLIE),
            clock,
            scenario.ctx(),
        );

        let _receipt3 = registry.process_payment_in_registry<SUI>(
            b"3".to_ascii_string(),
            500,
            create_test_coin(scenario, 500),
            option::some(BOB),
            clock,
            scenario.ctx(),
        );
    });
}

/// Tests processing a payment with maximum u64 nonce value.
#[test]
fun test_large_nonce_values() {
    test_tx!(|scenario, clock, registry, namespace| {
        let _receipt = registry.process_payment_in_registry<SUI>(
            b"18446744073709551615".to_ascii_string(),
            1000,
            create_test_coin(scenario, 1000),
            option::some(BOB),
            clock,
            scenario.ctx(),
        );
    });
}

/// Tests successfully deleting an expired payment record (expiration duration = 0 epochs).
#[test]
fun test_delete_expired_payment_record_success() {
    test_tx!(|scenario, clock, registry, namespace| {
        let _receipt = registry.process_payment_in_registry<SUI>(
            b"12345".to_ascii_string(),
            1000,
            create_test_coin(scenario, 1000),
            option::some(BOB),
            clock,
            scenario.ctx(),
        );

        let cap = scenario.take_from_sender<RegistryAdminCap>();

        registry.set_config_epoch_expiration_duration(
            &cap,
            0, // epoch_expiration_duration
            scenario.ctx(),
        );

        registry.delete_payment_record<SUI>(
            payment_standard::create_payment_key<SUI>(
                b"12345".to_ascii_string(),
                1000,
                BOB,
            ),
            scenario.ctx(),
        );
        scenario.return_to_sender(cap);
    });
}

/// Tests that deleting a non-existent payment record fails.
#[test, expected_failure(abort_code = payment_standard::EPaymentRecordDoesNotExist)]
fun test_delete_nonexistent_payment_record() {
    test_tx!(|scenario, clock, registry, namespace| {
        registry.delete_payment_record<SUI>(
            payment_standard::create_payment_key<SUI>(
                b"99999".to_ascii_string(),
                1000,
                BOB,
            ),
            scenario.ctx(),
        );
    });
}

/// Tests that deleting a payment record before expiration fails.
#[test, expected_failure(abort_code = payment_standard::EPaymentRecordHasNotExpired)]
fun test_delete_payment_record_not_expired() {
    test_tx!(|scenario, clock, registry, namespace| {
        let cap = scenario.take_from_sender<RegistryAdminCap>();
        registry.set_config_epoch_expiration_duration(
            &cap,
            10000, // epoch_expiration_duration
            scenario.ctx(),
        );
        scenario.return_to_sender(cap);

        let _receipt = registry.process_payment_in_registry<SUI>(
            b"12345".to_ascii_string(),
            1000,
            create_test_coin(scenario, 1000),
            option::some(BOB),
            clock,
            scenario.ctx(),
        );

        registry.delete_payment_record<SUI>(
            payment_standard::create_payment_key<SUI>(
                b"12345".to_ascii_string(),
                1000,
                BOB,
            ),
            scenario.ctx(),
        );
    });
}

/// Tests that deleting a payment record fails when using default expiration (30 epochs).
#[test, expected_failure(abort_code = payment_standard::EPaymentRecordHasNotExpired)]
fun test_30_epoch_expiration_duration() {
    test_tx!(|scenario, clock, registry, namespace| {
        let _receipt = registry.process_payment_in_registry<SUI>(
            b"12345".to_ascii_string(),
            1000,
            create_test_coin(scenario, 1000),
            option::some(BOB),
            clock,
            scenario.ctx(),
        );

        scenario.next_epoch(ALICE);

        registry.delete_payment_record<SUI>(
            payment_standard::create_payment_key<SUI>(
                b"12345".to_ascii_string(),
                1000,
                BOB,
            ),
            scenario.ctx(),
        );
    });
}

/// Tests creating registry with valid alphanumeric names.
#[test]
fun test_valid_registry_names() {
    payment_standard::validate_registry_name(b"test123".to_ascii_string());
    payment_standard::validate_registry_name(b"abc".to_ascii_string());
    payment_standard::validate_registry_name(b"test-registry-123".to_ascii_string());
}

/// Tests that creating registry with special characters fails.
#[test, expected_failure(abort_code = payment_standard::ERegistryNameContainsInvalidCharacters)]
fun test_invalid_registry_name_special_chars() {
    payment_standard::validate_registry_name(b"test_registry".to_ascii_string());
}

/// Tests that creating registry with too long name fails.
#[test, expected_failure(abort_code = payment_standard::ERegistryNameLengthIsNotAllowed)]
fun test_invalid_registry_name_too_long() {
    payment_standard::validate_registry_name(b"1234567890123456789012345678901234567890123456789012345678901234".to_ascii_string());
}

/// Tests that creating registry with empty name fails.
#[test, expected_failure(abort_code = payment_standard::ERegistryNameLengthIsNotAllowed)]
fun test_invalid_registry_name_empty() {
    payment_standard::validate_registry_name(b"".to_ascii_string());
}

/// Tests setting payment record config as admin.
#[test]
fun test_set_config_success() {
    test_tx!(|scenario, clock, registry, namespace| {
        let cap = scenario.take_from_sender<RegistryAdminCap>();
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
        scenario.return_to_sender(cap);
    });
}

/// Tests that setting config fails when caller is not admin.
#[test, expected_failure(abort_code = payment_standard::EUnauthorizedAdmin)]
fun test_set_config_unauthorized() {
    test_tx!(|scenario, clock, default_registry, namespace| {
        let (another_registry, another_cap) = namespace.create_registry(
            b"testregistry".to_ascii_string(),
            scenario.ctx(),
        );

        default_registry.set_config_epoch_expiration_duration(
            &another_cap,
            1000, // epoch_expiration_duration
            scenario.ctx(),
        );
        abort
    });
}

/// Tests that creating registry with names starting with hyphen fails.
#[test, expected_failure(abort_code = payment_standard::ERegistryNameContainsInvalidCharacters)]
fun test_invalid_registry_name_starts_with_hyphen() {
    test_tx!(|scenario, clock, registry, namespace| {
        // Should fail - starts with hyphen
        let (_registry, _cap) = namespace.create_registry(
            std::ascii::string(b"-testregistry"),
            scenario.ctx(),
        );

        abort
    });
}

/// Tests that creating registry with names ending with hyphen fails.
#[test, expected_failure(abort_code = payment_standard::ERegistryNameContainsInvalidCharacters)]
fun test_invalid_registry_name_ends_with_hyphen() {
    payment_standard::validate_registry_name(b"testregistry-".to_ascii_string());
}

/// Tests that creating registry with uppercase letters fails.
#[test, expected_failure(abort_code = payment_standard::ERegistryNameContainsInvalidCharacters)]
fun test_invalid_registry_name_uppercase() {
    payment_standard::validate_registry_name(b"MyRegistry".to_ascii_string());
}

/// Tests that empty nonce fails
#[test, expected_failure(abort_code = payment_standard::EInvalidNonce)]
fun test_empty_nonce_failure() {
    payment_standard::validate_nonce(&(b"".to_ascii_string()));
}

/// Tests that nonce longer than 36 characters fails.
#[test, expected_failure(abort_code = payment_standard::EInvalidNonce)]
fun test_nonce_too_long_failure() {
    payment_standard::validate_nonce(&(b"1234567890123456789012345678901234567".to_ascii_string()));
}

/// Tests the standalone process_ephemeral_payment function without registry.
#[test]
fun test_process_ephemeral_payment_standalone() {
    test_tx!(|scenario, clock, registry, namespace| {
        let _receipt = payment_standard::process_ephemeral_payment<SUI>(
            b"ephemeral-payment".to_ascii_string(),
            1500,
            create_test_coin(scenario, 1500),
            BOB,
            clock,
            scenario.ctx(),
        );
    });
}

/// Tests the standalone process_ephemeral_payment function with an invalid nonce.
#[test, expected_failure(abort_code = payment_standard::EInvalidNonce)]
fun test_process_ephemeral_payment_standalone_invalid_nonce() {
    test_tx!(|scenario, clock, registry, namespace| {
        let _receipt = payment_standard::process_ephemeral_payment<SUI>(
            b"".to_ascii_string(), // Empty nonce - should fail
            1000,
            create_test_coin(scenario, 1000),
            BOB,
            clock,
            scenario.ctx(),
        );

        abort
    })
}

/// Tests processing a payment with registry_managed_funds enabled and no receiver specified.
#[test]
fun test_registry_managed_funds_no_receiver() {
    test_tx!(|scenario, clock, registry, namespace| {
        let cap = scenario.take_from_sender<RegistryAdminCap>();

        registry.set_config_registry_managed_funds(
            &cap,
            true,
            scenario.ctx(),
        );
        // Process payment with no receiver (should default to registry)
        let _receipt = registry.process_payment_in_registry<SUI>(
            b"12345".to_ascii_string(),
            1000,
            create_test_coin(scenario, 1000),
            std::option::none(), // No receiver specified
            clock,
            scenario.ctx(),
        );

        // Withdraw the funds from the registry
        let withdrawn_coin = registry.withdraw_from_registry<SUI>(&cap, scenario.ctx());
        assert!(withdrawn_coin.value() == 1000, 0);

        transfer::public_transfer(withdrawn_coin, scenario.ctx().sender());

        scenario.return_to_sender(cap);
    })
}

/// Tests processing a payment with registry_managed_funds enabled and registry as receiver.
#[test]
fun test_registry_managed_funds_registry_as_receiver() {
    let mut scenario = setup_test_scenario();

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

    scenario.end();
}

/// Tests that providing a different receiver fails when registry_managed_funds is enabled.
#[test, expected_failure(abort_code = payment_standard::ERegistryMustBeReceiver)]
fun test_registry_managed_funds_invalid_receiver() {
    let mut scenario = setup_test_scenario();

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
        b"12345".to_ascii_string(),
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
        b"12345".to_ascii_string(),
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

    scenario.end();
}

/// Tests that withdrawing from registry requires admin capability.
#[test, expected_failure(abort_code = payment_standard::EUnauthorizedAdmin)]
fun test_registry_withdraw_unauthorized() {
    let mut scenario = setup_test_scenario();

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
        b"12345".to_ascii_string(),
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

/// Scaffold a test tx that returns:
/// 1. The test scenario
/// 2. A clock
/// 3. The "default" payment registry
/// 4. The `Namespace` object (to be able to create more registries.)
public macro fun test_tx($f: |&mut Scenario, &mut Clock, &mut PaymentRegistry, &mut Namespace|) {
    let mut scenario = test_scenario::begin(ALICE);
    let mut clock = clock::create_for_testing(scenario.ctx());
    payment_standard::init_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);

    let mut namespace = scenario.take_shared<Namespace>();
    let mut default_registry = scenario.take_shared<PaymentRegistry>();

    $f(
        &mut scenario,
        &mut clock,
        &mut default_registry,
        &mut namespace,
    );

    scenario.next_tx(ALICE);

    test_scenario::return_shared(default_registry);
    test_scenario::return_shared(namespace);
    clock.destroy_for_testing();

    scenario.end();
}
