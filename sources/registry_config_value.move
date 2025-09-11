// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module sui_payment_standard::registry_config_value;

use std::ascii;
use std::string;
use std::type_name::TypeName;

const EInvalidRegistryConfigType: u64 = 0;

public enum RegistryConfigValue has copy, drop, store {
    U64(u64),
    Address(address),
    String(string::String),
    AsciiString(ascii::String),
    Bool(bool),
    Bytes(vector<u8>),
    Type(TypeName),
}

public(package) fun new_u64(value: u64): RegistryConfigValue {
    RegistryConfigValue::U64(value)
}

public(package) fun new_address(value: address): RegistryConfigValue {
    RegistryConfigValue::Address(value)
}

public(package) fun new_string(value: string::String): RegistryConfigValue {
    RegistryConfigValue::String(value)
}

public(package) fun new_ascii_string(value: ascii::String): RegistryConfigValue {
    RegistryConfigValue::AsciiString(value)
}

public(package) fun new_bool(value: bool): RegistryConfigValue {
    RegistryConfigValue::Bool(value)
}

public(package) fun new_bytes(value: vector<u8>): RegistryConfigValue {
    RegistryConfigValue::Bytes(value)
}

public(package) fun new_type(value: TypeName): RegistryConfigValue {
    RegistryConfigValue::Type(value)
}

public(package) fun as_u64(value: RegistryConfigValue): u64 {
    match (value) {
        RegistryConfigValue::U64(num) => num,
        _ => abort EInvalidRegistryConfigType,
    }
}

public(package) fun as_address(value: RegistryConfigValue): address {
    match (value) {
        RegistryConfigValue::Address(addr) => addr,
        _ => abort EInvalidRegistryConfigType,
    }
}

public(package) fun as_string(value: RegistryConfigValue): string::String {
    match (value) {
        RegistryConfigValue::String(str) => str,
        _ => abort EInvalidRegistryConfigType,
    }
}

public(package) fun as_ascii_string(value: RegistryConfigValue): ascii::String {
    match (value) {
        RegistryConfigValue::AsciiString(str) => str,
        _ => abort EInvalidRegistryConfigType,
    }
}

public(package) fun as_bool(value: RegistryConfigValue): bool {
    match (value) {
        RegistryConfigValue::Bool(val) => val,
        _ => abort EInvalidRegistryConfigType,
    }
}

public(package) fun as_bytes(value: RegistryConfigValue): vector<u8> {
    match (value) {
        RegistryConfigValue::Bytes(bytes) => bytes,
        _ => abort EInvalidRegistryConfigType,
    }
}

public(package) fun as_type(value: RegistryConfigValue): TypeName {
    match (value) {
        RegistryConfigValue::Type(type_name) => type_name,
        _ => abort EInvalidRegistryConfigType,
    }
}
