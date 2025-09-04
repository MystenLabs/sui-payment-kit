# SUI Pay

A secure payment processing system built on the Sui blockchain that provides reliable payment verification and receipt management.

## Technical Overview

SUI Pay is a Move smart contract that enables secure, verifiable payments on the Sui network with built-in duplicate prevention and optional receipt persistence. The system is designed around payment registries that can be configured with custom policies for receipt management and expiration.

### PaymentRegistry

- **Purpose**: Container for payment receipts with configurable policies
- **Features**:
  - Unique registry identification via derived objects
  - Admin-controlled configuration through `RegistryAdminCap`
  - Dynamic field storage for receipts and configurations

### RegistryAdminCap

- **Purpose**: Administrative capability object for registry management
- **Permissions**:
  - Configure receipt policies
  - Set expiration rules

### PaymentReceipt

- **Purpose**: Immutable record of completed payments
- **Fields**:
  - `payment_id`: Unique identifier for the payment
  - `payment_amount`: Amount transferred in the payment
  - `receiver`: Recipient address
  - `coin_type`: Type of coin used (e.g., SUI)
  - `timestamp_ms`: Payment timestamp

### Configs

**Purpose**: Configurable policy owned by the Registry. Each configuration is independently stored in a Dynamic Field for greater modularity and upgradability. This provides the ability to add additional configurations without breaking existing Registries and their previously set configurations.

#### Receipt Config

- `write_receipts`: Whether to persist receipts in registry
- `receipt_expiration_duration_ms`: Optional expiration time for receipts. `None` implies receipts never expire.

### Key Features

#### Duplicate Prevention

- Uses composite keys (`PaymentKey`) derived from payment parameters
- Prevents duplicate payments with identical: `payment_id`, `amount`, `coin_type`, and `receiver`

#### Exact Amount Verification

- Enforces exact payment amounts to prevent overpayment/underpayment
- Validates coin value matches expected payment amount

#### Derived Address Registries

- Registries leverage Derived Addresses, allowing for easy lockup via a string based identifier

#### Configurable Receipt Management

- Optional receipt persistence in registries
- Configurable expiration policies
- Admin-controlled settings per registry

#### Receipt Expiration and Cleanup

- Time-based receipt expiration
- Manual cleanup of expired receipts
- Storage optimization through receipt removal

### Payment Processing Flow

1. **Registry Creation** (Optional)

   ```move
   create_registry(&mut namespace, name, ctx) -> (PaymentRegistry, RegistryAdminCap)
   ```

2. **Configuration** (Optional)

   ```move
   registry.set_receipt_config(&cap, config, ctx)
   ```

3. **Payment Processing**

   - **Simple Payment**: `process_payment()` - emits event only
   - **Registry Payment**: `process_payment_in_registry()` - optionally persists receipt

4. **Receipt Management**
   ```move
   close_expired_receipt(&mut registry, key, ctx)
   ```

### Error Codes

| Code | Constant                 | Description                              |
| ---- | ------------------------ | ---------------------------------------- |
| 0    | `EReceiptAlreadyExists`  | Duplicate payment attempt                |
| 1    | `EIncorrectAmount`       | Coin value doesn't match expected amount |
| 2    | `EReceiptDoesNotExist`   | Receipt not found for cleanup            |
| 3    | `EReceiptHasNotExpired`  | Attempting to close non-expired receipt  |
| 4    | `EUnauthorizedAdmin`     | Invalid admin capability                 |
| 5    | `ERegistryAlreadyExists` | Registry name collision                  |

## Usage

### Prerequisites

- Sui CLI installed and configured
- Access to Sui testnet or mainnet
- Move compiler available

### Building the Contract

```bash
sui move build
```

### Testing

```bash
sui move test
```

The test suite covers:

- Basic payment processing
- Duplicate prevention
- Amount validation
- Receipt expiration
- Admin authorization
- Error conditions

### Deployment

1. **Deploy the contract**:

   ```bash
   sui client publish --gas-budget 100000000
   ```

2. **Note the Package ID** from the deployment output for integration

### Integration Examples

#### Simple Payment (Event-Only)

```move
// Process payment without registry
sui_pay::process_payment<SUI>(
    ascii::string(b"payment_123"),  // payment_id
    1000,                           // amount in MIST
    coin,                           // Coin<SUI> object
    @0xrecipient,                   // recipient address
    &mut ctx
);
```

#### Registry-Based Payment

```move
// 1. Create registry (one-time setup)
let (mut registry, admin_cap) = sui_pay::create_registry(
    &mut namespace,
    ascii::string(b"my_store"),
    &mut ctx
);

// 2. Configure receipt policy (optional)
let config = sui_pay::create_receipt_config(
    true,                    // write receipts
    option::some(86400000)   // 24-hour expiration
);
sui_pay::set_receipt_config(&mut registry, &admin_cap, config, &mut ctx);

// 3. Process payments
let receipt = sui_pay::process_payment_in_registry<SUI>(
    ascii::string(b"order_456"),
    2500,
    coin,
    @0xbuyer,
    &mut registry,
    &mut ctx
);
```

#### Receipt Cleanup

```move
// Clean up expired receipts
let payment_key = sui_pay::create_payment_key(
    ascii::string(b"order_456"),
    2500,
    ascii::string(b"0x2::sui::SUI"),
    @0xbuyer
);

sui_pay::close_expired_receipt(
    &mut registry,
    payment_key,
    &mut ctx
);
```

### Configuration Options

#### Receipt Policies

- **Disabled**: `create_receipt_config(false, option::none())`
  - No receipt persistence, events only
- **Persistent**: `create_receipt_config(true, option::none())`
  - Permanent receipt storage, manual cleanup only
- **Expiring**: `create_receipt_config(true, option::some(duration_ms))`
  - Automatic expiration after specified time

### Security Considerations

- **Admin Capabilities**: Store `RegistryAdminCap` securely
- **Payment Validation**: Always verify payment amounts match expectations
- **Unique Payment IDs**: Use truly unique identifiers to prevent conflicts
- **Gas Management**: Consider gas costs for receipt storage and cleanup
- **Access Control**: Registry admin capabilities provide full configuration control

### License

[License information to be added]
