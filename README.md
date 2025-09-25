# Sui Payment Kit

A robust, open-source payment processing toolkit for the Sui blockchain that provides secure payment verification, receipt management, and duplicate prevention.

## Overview

The Sui Payment Kit is a Move smart contract framework that enables developers to integrate secure, verifiable payments into their Sui applications. It provides a flexible architecture for payment processing with optional receipt persistence, configurable expiration policies, and built-in duplicate prevention.

### Key Features

- **Secure Payment Processing**: Built-in duplicate prevention and exact amount verification
- **Payment Regitries**: Registries can be leveraged to custody payments, manage receipt lifetime, etc
- **Flexible Receipt Management**: Optional receipt persistence with configurable expiration
- **Event-Driven Architecture**: All payments emit events for off-chain tracking
- **Admin Controls**: Capability-based access control for registry management
- **Modular Design**: Extensible configuration system for future enhancements
- **Multi-Coin Support**: Generic implementation supports any Sui coin type

## How It Works

The Sui Payment Kit consists of three main components:

1. **Payment Processing Core**: Handles coin transfers and validation
2. **Registry System**: Optional persistent storage for payment receipts
3. **Configuration Layer**: Dynamic, upgradeable registry configuration management

### Duplicate Prevention

Sui Payment Kit prevents duplicate payments using a composite key derived from:

- `Payment ID (nonce)`
- `Amount`
- `Coin Type`
- `Receiver Address`

This ensures the same payment cannot be processed twice.

_Duplicate prevention is only enforced when processing payments via a `PaymentRegistry`. If duplicate prevention is not necessary there is an Ephemeral payment option._
