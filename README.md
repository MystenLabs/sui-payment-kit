# Sui Payment Standard

A robust, open-source payment processing standard for the Sui blockchain that provides secure payment verification, receipt management, and duplicate prevention.

## Overview

The Sui Payment Standard is a Move smart contract framework that enables developers to integrate secure, verifiable payments into their Sui applications. It provides a flexible architecture for payment processing with optional receipt persistence, configurable expiration policies, and built-in duplicate prevention.

### Key Features

- **🔒 Secure Payment Processing**: Built-in duplicate prevention and exact amount verification
- **📝 Flexible Receipt Management**: Optional receipt persistence with configurable expiration
- **⚡ Event-Driven Architecture**: All payments emit events for off-chain tracking
- **🎛️ Admin Controls**: Capability-based access control for registry management
- **🧩 Modular Design**: Extensible configuration system for future enhancements
- **💰 Multi-Coin Support**: Generic implementation supports any Sui coin type

## How It Works

### Architecture

The Sui Payment Standard consists of three main components:

1. **Payment Processing Core**: Handles coin transfers and validation
2. **Registry System**: Optional persistent storage for payment receipts
3. **Configuration Layer**: Dynamic, upgradeable configuration management

### Payment Flows

#### 1. Simple Payment (Event-Only)

For applications that only need payment events without record persistence:

```move
use sui_payment_standard::payment_standard;

// Process a simple payment
let receipt = payment_standard::process_ephemeral_payment<SUI>(
    b"order_123".to_ascii_string(),   // unique payment ID (nonce)
    1000000,                          // amount in MIST (1 SUI = 1B MIST)
    coin,                             // Coin<SUI> object
    @0xrecipient,                     // recipient address
    &clock,                           // Clock object for timestamps
    &mut ctx
);
```

#### 2. Registry-Based Payment

For applications requiring payment record storage:

```move
// One-time setup: Create a registry
let (mut registry, admin_cap) = payment_standard::create_registry(
    &mut namespace,
    b"my_marketplace".to_ascii_string(),
    &mut ctx
);

// Configure registry policies (optional)
// Set epoch expiration duration (e.g., 30 epochs)
payment_standard::set_config_epoch_expiration_duration(
    &mut registry,
    &admin_cap,
    30,  // receipts expire after 30 epochs
    &mut ctx
);

// Enable registry-managed funds (optional)
payment_standard::set_config_registry_managed_funds(
    &mut registry,
    &admin_cap,
    true,  // registry holds funds instead of direct transfer
    &mut ctx
);

// Process payments through the registry
let receipt = payment_standard::process_registry_payment<SUI>(
    &mut registry,
    b"order_456".to_ascii_string(),   // unique payment ID (nonce)
    2500000,                          // amount in MIST
    coin,                             // Coin<SUI> object
    option::some(@0xrecipient),       // optional receiver (None if registry-managed)
    &clock,                           // Clock object for timestamps
    &mut ctx
);
```

### Duplicate Prevention

The standard prevents duplicate payments using a composite key derived from:

- Payment ID (nonce)
- Amount
- Coin type
- Receiver address

This ensures the same payment cannot be processed twice.

### Receipt Management

Receipt expiration can be configured in two different ways:

1. **No Persistence**: Events only, no storage overhead
2. **Auto-Expiring**: Receipts expire after a configured number of epochs (default is 30 epochs)

Clean up expired receipts to optimize storage:

```move
// Create a payment key for the receipt you want to delete
let payment_key = payment_standard::create_payment_key<SUI>(
    b"order_456".to_ascii_string(),   // nonce
    2500000,                          // payment amount
    @0xrecipient                      // receiver address
);

// Delete the expired payment record
payment_standard::delete_payment_record<SUI>(
    &mut registry,
    payment_key,
    &mut ctx
);
```

### Fund Management

For registries configured to manage funds, administrators can withdraw collected payments:

```move
// Withdraw all SUI funds from the registry
let withdrawn_coins = payment_standard::withdraw_from_registry<SUI>(
    &mut registry,
    &admin_cap,
    &mut ctx
);

// Transfer to desired address or use as needed
transfer::public_transfer(withdrawn_coins, @0xadmin_wallet);
```

## API Reference

### Core Functions

| Function                                 | Description                                  |
| ---------------------------------------- | -------------------------------------------- |
| `process_ephemeral_payment<T>()`         | Process a simple payment with event emission |
| `process_registry_payment<T>()`          | Process payment through a registry           |
| `create_registry()`                      | Create a new payment registry                |
| `set_config_epoch_expiration_duration()` | Set receipt expiration in epochs             |
| `set_config_registry_managed_funds()`    | Configure fund management mode               |
| `delete_payment_record<T>()`             | Remove expired payment records               |
| `withdraw_from_registry<T>()`            | Withdraw registry-managed funds (admin only) |
| `create_payment_key<T>()`                | Create a key for payment record operations   |

### Error Codes

| Name                                     | Message                                                                                  |
| ---------------------------------------- | ---------------------------------------------------------------------------------------- |
| `EPaymentAlreadyExists`                  | Duplicate payment detected                                                               |
| `EIncorrectAmount`                       | Payment amount mismatch                                                                  |
| `EPaymentRecordDoesNotExist`             | Payment record not found                                                                 |
| `EPaymentRecordHasNotExpired`            | Payment record has not yet expired                                                       |
| `EUnauthorizedAdmin`                     | Unauthorized: Invalid admin capability                                                   |
| `ERegistryAlreadyExists`                 | Registry with this name already exists                                                   |
| `ERegistryNameLengthIsNotAllowed`        | Registry name length is not allowed                                                      |
| `ERegistryNameContainsInvalidCharacters` | Registry name contains invalid characters                                                |
| `EInvalidNonce`                          | Nonce is invalid                                                                         |
| `ERegistryMustBeReceiver`                | Registry is flagged to manage funds. Receiver must be either None or the registry itself |
| `EReceiverMustBeProvided`                | Receiver must be provided when a registry does not manage funds                          |
| `ERegistryBalanceDoesNotExist`           | Registry balance for this coin type does not exist                                       |

## Use Cases

- **E-commerce Platforms**: Track customer payments and order fulfillment
- **Subscription Services**: Manage recurring payments with receipt tracking
- **Digital Marketplaces**: Process payments between buyers and sellers
- **DeFi Applications**: Integrate payment verification into financial protocols
- **Gaming Platforms**: Handle in-game purchases and microtransactions

## Security Considerations

- **Admin Capabilities**: Store `RegistryAdminCap` objects securely
- **Payment Validation**: Always verify amounts match business logic requirements
- **Unique IDs**: Use cryptographically secure methods for generating payment IDs
- **Gas Optimization**: Consider storage costs when enabling receipt persistence
- **Access Control**: Implement proper access controls in integrating applications
