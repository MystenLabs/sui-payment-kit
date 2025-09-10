// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module sui_payment_standard::payment_standard;

use std::ascii::String;
use std::type_name;
use sui::balance::Balance;
use sui::clock::Clock;
use sui::coin::Coin;
use sui::derived_object;
use sui::dynamic_field as df;
use sui::event;
use sui::vec_map::{Self, VecMap};
use sui_payment_standard::config_value::{Self, ConfigValue};

const EIncorrectAmount: u64 = 1;
const EPaymentRecordDoesNotExist: u64 = 2;
const EPaymentAlreadyExists: u64 = 3;
const EPaymentRecordHasNotExpired: u64 = 3;
const EUnauthorizedAdmin: u64 = 4;
const ERegistryAlreadyExists: u64 = 5;
const ERegistryNameLengthIsNotAllowed: u64 = 6;
const ERegistryNameContainsInvalidCharacters: u64 = 7;
const EInvalidNonce: u64 = 8;
const ERegistryMustBeReceiver: u64 = 9;
const EReceiverMustBeProvided: u64 = 10;
const ERegistryBalanceDoesNotExist: u64 = 11;

const DEFAULT_EPOCH_EXPIRATION_DURATION: u64 = 30;

const DEFAULT_REGISTRY_NAME: vector<u8> = b"payment-registry";

const EPOCH_EXPIRATION_DURATION_KEY: vector<u8> = b"epoch_expiration_duration";
const REGISTRY_MANAGED_FUNDS_KEY: vector<u8> = b"registry_managed_funds";

public struct Namespace has key {
    id: UID,
}

public struct PaymentRegistry has key {
    id: UID,
    cap_id: ID,
    config: VecMap<String, ConfigValue>,
}

public struct RegistryAdminCap has key, store {
    id: UID,
    registry_id: ID,
}

public struct PaymentReceipt has copy, drop, store {
    payment_type: PaymentType,
    nonce: String,
    payment_amount: u64,
    receiver: address,
    coin_type: String,
    timestamp_ms: u64,
}

public enum PaymentType has copy, drop, store {
    Ephemeral,
    Registry(ID),
}

public struct PaymentKey<phantom T> has copy, drop, store {
    nonce: String,
    payment_amount: u64,
    receiver: address,
}

public struct PaymentRecord has copy, drop, store {
    epoch_at_time_of_record: u64,
}

public struct BalanceKey<phantom T>() has copy, drop, store;

/// Configurations are sets of additional functionality that can be assigned to a PaymentRegistry.
/// They are stored in a DynamicField within the registry, under their respective key structs.
public struct RegistryConfigKey() has copy, drop, store;

/// Initializes the module, creating and sharing the Namespace object.
fun init(ctx: &mut TxContext) {
    let mut namespace = Namespace { id: object::new(ctx) };
    let (registry, cap) = namespace.create_registry(DEFAULT_REGISTRY_NAME.to_ascii_string(), ctx);

    transfer::share_object(namespace);
    transfer::transfer(cap, ctx.sender());
    registry.share();
}

/// Creates a new payment registry
///
/// # Parameters
/// * `namespace` - The Namespace object under which to create the registry
/// * `name` - The name of the registry. Must be unique within the namespace.
///
/// # Returns
/// A new PaymentRegistry instance
public fun create_registry(
    namespace: &mut Namespace,
    name: String,
    ctx: &mut TxContext,
): (PaymentRegistry, RegistryAdminCap) {
    validate_registry_name(name);

    // If a name is provided, ensure no existing registry with that name exists
    assert!(!derived_object::exists(&namespace.id, name), ERegistryAlreadyExists);
    let uid = derived_object::claim(&mut namespace.id, name);

    let cap = RegistryAdminCap {
        id: object::new(ctx),
        registry_id: uid.to_inner(),
    };

    (
        PaymentRegistry {
            id: uid,
            cap_id: object::id(&cap),
            config: vec_map::empty(),
        },
        cap,
    )
}

/// Processes a payment (without the use of a Registry), emitting a payment receipt event.
///
/// # Parameters
/// * `nonce` - Unique nonce for the payment
/// * `payment_amount` - Expected payment amount
/// * `coin` - Coin to be transferred
/// * `receiver` - Address of the payment receiver
/// * `clock` - Reference to the Clock object
///
/// # Aborts
/// * If the coin amount does not match the expected payment amount
/// * If a receipt with the same payment parameters already exists in the registry
///
/// # Returns
/// The payment receipt
public fun process_ephemeral_payment<T>(
    nonce: String,
    payment_amount: u64,
    coin: Coin<T>,
    receiver: address,
    clock: &Clock,
    _ctx: &mut TxContext,
): PaymentReceipt {
    let receipt = PaymentType::Ephemeral.internal_create_receipt(
        &coin,
        payment_amount,
        nonce,
        receiver,
        clock,
    );

    // Transfer the coin to the receiver.
    transfer::public_transfer(coin, receiver);

    // return the receipt for PTB consumption.
    receipt
}

/// Processes a payment via a payment registry, writing a receipt to the registry.
///
/// # Parameters
/// * `nonce` - Unique nonce for the payment
/// * `payment_amount` - Expected payment amount
/// * `coin` - Coin to be transferred
/// * `receiver` - (Mutable) Address of the payment receiver
/// * `registry` - Payment registry to write the receipt to
///
/// # Aborts
/// * If a receipt with the same payment parameters already exists in the registry
/// * If the coin amount does not match the expected payment amount
///
/// # Returns
/// The payment receipt
public fun process_payment_in_registry<T>(
    registry: &mut PaymentRegistry,
    nonce: String,
    payment_amount: u64,
    coin: Coin<T>,
    mut receiver: Option<address>,
    clock: &Clock,
    ctx: &mut TxContext,
): PaymentReceipt {
    let funds_managed_by_registry = registry
        .config
        .try_get(&REGISTRY_MANAGED_FUNDS_KEY.to_ascii_string())
        .is_some_and!(|val| (*val).as_bool());

    // Validate receiver requirements based on registry configuration BEFORE consuming it
    if (funds_managed_by_registry) {
        assert!(
            receiver.is_none() || receiver.is_some_and!(|r| r == registry.id.to_address()),
            ERegistryMustBeReceiver,
        );
    } else {
        assert!(receiver.is_some(), EReceiverMustBeProvided);
    };

    // Extract the actual receiver address for use in receipt and transfer
    let actual_receiver = receiver.extract_or!(registry.id.to_address());

    let receipt = PaymentType::Registry(registry.id.to_inner()).internal_create_receipt(
        &coin,
        payment_amount,
        nonce,
        actual_receiver,
        clock,
    );

    if (funds_managed_by_registry) {
        registry.collect_payment(coin);
    } else {
        // Transfer the coin to the receiver.
        transfer::public_transfer(coin, actual_receiver);
    };

    registry.write_payment_record<T>(receipt, ctx);

    // Return the receipt for consumption
    receipt
}

/// If the registry is configured to manage funds, withdraw all funds of the specified coin from the registry.
///
/// # Parameters
/// * `registry` - Payment registry to withdraw funds from
/// * `cap` - Admin capability for the registry
///
/// # Aborts
/// * If the caller does not have the admin capability for the registry
/// * If there are no funds of the specified coin type in the registry
public fun withdraw_from_registry<T>(
    registry: &mut PaymentRegistry,
    cap: &RegistryAdminCap,
    ctx: &mut TxContext,
): Coin<T> {
    assert!(cap.is_valid_for(registry), EUnauthorizedAdmin);
    let key = BalanceKey<T>();

    assert!(df::exists_(&registry.id, key), ERegistryBalanceDoesNotExist);
    df::borrow_mut<_, Balance<T>>(&mut registry.id, key).withdraw_all().into_coin(ctx)
}

/// Removes an expired Payment Record from the Registry.
///
/// # Parameters
/// * `registry` - Payment registry containing the receipt
/// * `payment_key` - Hash of payment parameters used as the key for the PaymentRecord
///
/// # Aborts
/// * If receipt with payment hash does not exist
/// * If receipt has not yet expired (when expiration is enabled)
public fun delete_payment_record<T>(
    registry: &mut PaymentRegistry,
    payment_key: PaymentKey<T>,
    ctx: &mut TxContext,
) {
    assert!(df::exists_(&registry.id, payment_key), EPaymentRecordDoesNotExist);

    let expiration_duration = registry
        .config
        .try_get(&EPOCH_EXPIRATION_DURATION_KEY.to_ascii_string())
        .map!(|val| val.as_u64())
        .destroy_or!(DEFAULT_EPOCH_EXPIRATION_DURATION);

    let payment_record: &PaymentRecord = df::borrow(
        &registry.id,
        payment_key,
    );

    let expiration_epoch = payment_record.epoch_at_time_of_record + expiration_duration;

    assert!(ctx.epoch() >= expiration_epoch, EPaymentRecordHasNotExpired);

    df::remove<_, PaymentRecord>(
        &mut registry.id,
        payment_key,
    );
}

/// Creates a PaymentKey from payment parameters.
///
/// # Parameters
/// * `nonce` - Unique nonce for the payment
/// * `payment_amount` - Expected payment amount
/// * `receiver` - Address of the payment receiver
public fun create_payment_key<T>(
    nonce: String,
    payment_amount: u64,
    receiver: address,
): PaymentKey<T> {
    PaymentKey {
        nonce,
        payment_amount,
        receiver,
    }
}

/// Sets the `epoch_expiration_duration` for the configuration.
public fun set_config_epoch_expiration_duration(
    registry: &mut PaymentRegistry,
    cap: &RegistryAdminCap,
    epoch_expiration_duration: u64,
    _ctx: &mut TxContext,
) {
    assert!(cap.is_valid_for(registry), EUnauthorizedAdmin);

    registry.upsert_config(
        EPOCH_EXPIRATION_DURATION_KEY.to_ascii_string(),
        config_value::new_u64(epoch_expiration_duration),
    );
}

public fun set_config_registry_managed_funds(
    registry: &mut PaymentRegistry,
    cap: &RegistryAdminCap,
    registry_managed_funds: bool,
    _ctx: &mut TxContext,
) {
    assert!(cap.is_valid_for(registry), EUnauthorizedAdmin);
    registry.upsert_config(
        REGISTRY_MANAGED_FUNDS_KEY.to_ascii_string(),
        config_value::new_bool(registry_managed_funds),
    );
}

/// Enforce that a registry will always be shared.
/// # Parameters
/// * `registry` - The PaymentRegistry to share
public fun share(registry: PaymentRegistry) {
    transfer::share_object(registry);
}

/// Validate the inputs & produce a receipt.
fun internal_create_receipt<T>(
    payment_type: PaymentType,
    coin: &Coin<T>,
    payment_amount: u64,
    nonce: String,
    receiver: address,
    clock: &Clock,
): PaymentReceipt {
    let coin_type = type_name::with_defining_ids<T>().into_string();
    // If the coin amount does not match the expected payment amount, abort.
    // This ensures that the caller cannot accidentally overpay or underpay.
    assert!(coin.value() == payment_amount, EIncorrectAmount);
    validate_nonce(&nonce);

    let timestamp_ms = clock.timestamp_ms();

    let receipt = PaymentReceipt {
        payment_type,
        nonce,
        payment_amount,
        receiver,
        coin_type,
        timestamp_ms,
    };

    // Emit the receipt event.
    event::emit(receipt);

    receipt
}

/// Writes a payment record to a dynamic field in the registry.
fun write_payment_record<T>(
    registry: &mut PaymentRegistry,
    receipt: PaymentReceipt,
    ctx: &TxContext,
) {
    let key = receipt.to_payment_record_key<T>();
    assert!(!df::exists_(&registry.id, key), EPaymentAlreadyExists);

    // Store only the current epoch in the dynamic field to save space
    // The epoch is used for expiration checks
    let payment_record = PaymentRecord {
        epoch_at_time_of_record: ctx.epoch(),
    };

    df::add(
        &mut registry.id,
        key,
        payment_record,
    );
}

/// Converts a PaymentReceipt into a PaymentKey for storage/retrieval of the corresponding PaymentRecord.
fun to_payment_record_key<T>(receipt: &PaymentReceipt): PaymentKey<T> {
    PaymentKey {
        nonce: receipt.nonce,
        payment_amount: receipt.payment_amount,
        receiver: receipt.receiver,
    }
}

/// If the registry is configured to manage funds, collects a payment into the registry's balance.
fun collect_payment<T>(registry: &mut PaymentRegistry, coin: Coin<T>) {
    let key = BalanceKey<T>();
    if (df::exists_(&registry.id, key)) {
        df::borrow_mut<_, Balance<T>>(&mut registry.id, key).join(coin.into_balance());
    } else {
        df::add(&mut registry.id, key, coin.into_balance());
    }
}

fun upsert_config(registry: &mut PaymentRegistry, key: String, value: ConfigValue) {
    if (registry.config.contains(&key)) {
        registry.config.remove(&key);
    };

    registry.config.insert(key, value);
}

/// Checks if the provided admin capability is valid for the given registry.
fun is_valid_for(cap: &RegistryAdminCap, registry: &PaymentRegistry): bool {
    cap.registry_id == object::id(registry)
}

/// Validates that a registry name conforms to SuiNS standards:
fun validate_registry_name(name: String) {
    assert!(name.length() >= 3 && name.length() <= 63, ERegistryNameLengthIsNotAllowed);

    let bytes = name.as_bytes();
    let len = bytes.length();

    // Check each character follows SuiNS standards (letters, digits, hyphens)
    let mut i = 0;
    while (i < len) {
        let c = *bytes.borrow(i);
        assert!(
            (c >= 97 && c <= 122) || // lowercase a-z
            (c >= 48 && c <= 57) ||  // digits 0-9
            (c == 45), // hyphen -
            ERegistryNameContainsInvalidCharacters,
        );
        i = i + 1;
    };

    // Names cannot start or end with hyphen
    assert!(*bytes.borrow(0) != 45, ERegistryNameContainsInvalidCharacters);
    assert!(*bytes.borrow(len - 1) != 45, ERegistryNameContainsInvalidCharacters);
}

/// Validates that a nonce is non-empty and does not exceed 36 characters.
fun validate_nonce(nonce: &String) {
    assert!(nonce.length() > 0 && nonce.length() <= 36, EInvalidNonce);
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}
