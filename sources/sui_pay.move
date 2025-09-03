module sui_pay::sui_pay;

use std::ascii::String;
use std::type_name;
use sui::coin::{Self, Coin};
use sui::derived_object;
use sui::dynamic_field as df;
use sui::event;

const EPaymentAlreadyExists: u64 = 0;
const EIncorrectAmount: u64 = 1;
const EReceiptDoesNotExist: u64 = 2;
const EReceiptHasNotExpired: u64 = 3;
const EUnauthorizedAdmin: u64 = 4;
const ERegistryAlreadyExists: u64 = 5;

public struct Namespace has key {
    id: UID,
}

public struct RegistryAdminCap has key, store {
    id: UID,
    registry_id: ID,
}

public struct PaymentRegistry has key {
    id: UID,
    cap_id: ID,
}

public struct PaymentReceipt has copy, drop, store {
    payment_id: String,
    payment_amount: u64,
    receiver: address,
    coin_type: String,
    timestamp_ms: u64,
}

public struct PaymentKey has copy, drop, store {
    payment_id: String,
    payment_amount: u64,
    coin_type: String,
    receiver: address,
}

/// Configurations are sets of additional functionality that can be assigned to a PaymentRegistry.
/// They are stored in a DynamicField within the registry, under their respective key structs.
public struct ReceiptConfigKey() has copy, drop, store;

/// ReceiptConfig control whether receipts are written to the registry, and if so, whether they expire.
public struct ReceiptConfig has copy, drop, store {
    write_receipts: bool,
    receipt_expiration_duration_ms: Option<u64>,
}

/// Initializes the module, creating and sharing the Namespace object.
fun init(ctx: &mut TxContext) {
    transfer::share_object(Namespace { id: sui::object::new(ctx) });
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
    // TODO - Do we want to enforce any rules on the name?

    // If a name is provided, ensure no existing registry with that name exists
    assert!(!derived_object::exists(&namespace.id, name), ERegistryAlreadyExists);
    let uid = derived_object::claim(&mut namespace.id, name);

    let cap = RegistryAdminCap {
        id: sui::object::new(ctx),
        registry_id: uid.to_inner(),
    };

    (
        PaymentRegistry {
            id: uid,
            cap_id: cap.id.to_inner(),
        },
        cap,
    )
}

public fun set_receipt_config(
    registry: &mut PaymentRegistry,
    cap: &RegistryAdminCap,
    receipt_config: ReceiptConfig,
    _ctx: &mut TxContext,
) {
    assert!(registry.cap_id == object::id(cap), EUnauthorizedAdmin);

    let key = ReceiptConfigKey();

    df::remove_if_exists<ReceiptConfigKey, ReceiptConfig>(&mut registry.id, key);
    df::add(
        &mut registry.id,
        key,
        receipt_config,
    );
}

/// Writes a payment receipt to a dynamic field in the registry.
///
/// # Parameters
/// * `receipt`  - Receipt to write
/// * `registry` - Payment registry to write the receipt to
///
/// # Aborts
/// * If a receipt with the same payment parameters already exists in the registry
public fun write_payment_receipt(registry: &mut PaymentRegistry, receipt: PaymentReceipt) {
    let key = receipt.to_key();
    assert!(!df::exists_(&registry.id, key), EPaymentAlreadyExists);
    df::add(
        &mut registry.id,
        key,
        receipt,
    );
}

/// Processes a payment (without the use of a Registry), emitting a payment receipt event.
///
/// # Parameters
/// * `payment_id` - Unique payment_id for the payment
/// * `payment_amount` - Expected payment amount
/// * `coin` - Coin to be transferred
/// * `receiver` - Address of the payment receiver
///
/// # Aborts
/// * If the coin amount does not match the expected payment amount
/// * If a receipt with the same payment parameters already exists in the registry
///
/// # Returns
/// The payment receipt
public fun process_payment<T>(
    payment_id: String,
    payment_amount: u64,
    coin: Coin<T>,
    receiver: address,
    _ctx: &mut TxContext,
): PaymentReceipt {
    let coin_type = type_name::into_string(
        type_name::with_defining_ids<T>(),
    );

    // If the coin amount does not match the expected payment amount, abort.
    // This ensures that the caller cannot accidentally overpay or underpay.
    let actual_amount = coin::value(&coin);
    assert!(actual_amount == payment_amount, EIncorrectAmount);

    let timestamp_ms = sui::tx_context::epoch_timestamp_ms(_ctx);

    transfer::public_transfer(coin, receiver);

    event::emit(PaymentReceipt {
        payment_id,
        payment_amount,
        receiver,
        coin_type,
        timestamp_ms,
    });

    PaymentReceipt {
        payment_id,
        payment_amount,
        receiver,
        coin_type,
        timestamp_ms,
    }
}

/// Processes a payment via a payment registry, writing a receipt to the registry.
///
/// # Parameters
/// * `payment_id` - Unique payment_id for the payment
/// * `payment_amount` - Expected payment amount
/// * `coin` - Coin to be transferred
/// * `receiver` - Address of the payment receiver
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
    payment_id: String,
    payment_amount: u64,
    coin: Coin<T>,
    receiver: address,
    _ctx: &mut TxContext,
): PaymentReceipt {
    let receipt = process_payment(
        payment_id,
        payment_amount,
        coin,
        receiver,
        _ctx,
    );

    // If the registry has a receipt config with write_receipts set, write the receipt to the registry.
    let receipt_config_opt = get_receipt_config(registry);
    if (option::is_some(&receipt_config_opt)) {
        let receipt_config_ref: &ReceiptConfig = option::borrow(&receipt_config_opt);
        if (receipt_config_ref.write_receipts) {
            write_payment_receipt(registry, receipt);
        }
    };

    event::emit(
        receipt,
    );

    receipt
}

/// Removes an expired receipt from the registry.
///
/// # Parameters
/// * `registry` - Payment registry containing the receipt
/// * `payment_hash` - Hash of payment parameters identifying the receipt to close
///
/// # Aborts
/// * If receipt with payment hash does not exist
/// * If receipt has not yet expired (when expiration is enabled)
public fun close_expired_receipt(
    registry: &mut PaymentRegistry,
    key: PaymentKey,
    ctx: &mut TxContext,
) {
    assert!(df::exists_(&registry.id, key), EReceiptDoesNotExist);

    // If expiration duration is set, check if the receipt has expired
    // If expiration is disabled (None), receipts can never be closed immediately
    let receipt_config_opt = get_receipt_config(registry);
    if (option::is_some(&receipt_config_opt)) {
        let receipt_config_ref = option::borrow(&receipt_config_opt);
        let expiration_duration_opt = receipt_config_ref.receipt_expiration_duration_ms;
        if (option::is_some(&expiration_duration_opt)) {
            let payment_data: &PaymentReceipt = df::borrow(
                &registry.id,
                key,
            );
            let current_time = sui::tx_context::epoch_timestamp_ms(ctx);
            let expiration_duration = *option::borrow(&expiration_duration_opt);
            let expiration_time = payment_data.timestamp_ms + expiration_duration;

            assert!(current_time >= expiration_time, EReceiptHasNotExpired);

            df::remove<PaymentKey, PaymentReceipt>(
                &mut registry.id,
                key,
            );
        };
    }
}

fun to_key(receipt: &PaymentReceipt): PaymentKey {
    PaymentKey {
        payment_id: receipt.payment_id,
        payment_amount: receipt.payment_amount,
        coin_type: receipt.coin_type,
        receiver: receipt.receiver,
    }
}

fun get_receipt_config(registry: &PaymentRegistry): Option<ReceiptConfig> {
    let receipt_config_key = ReceiptConfigKey();
    if (df::exists_(&registry.id, receipt_config_key)) {
        let config: &ReceiptConfig = df::borrow(
            &registry.id,
            receipt_config_key,
        );
        option::some(*config)
    } else {
        option::none()
    }
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
public fun create_payment_key(
    payment_id: String,
    payment_amount: u64,
    coin_type: String,
    receiver: address,
): PaymentKey {
    PaymentKey {
        payment_id,
        payment_amount,
        coin_type,
        receiver,
    }
}

#[test_only]
public fun create_receipt_config(
    write_receipts: bool,
    receipt_expiration_duration_ms: Option<u64>,
): ReceiptConfig {
    ReceiptConfig {
        write_receipts,
        receipt_expiration_duration_ms,
    }
}
