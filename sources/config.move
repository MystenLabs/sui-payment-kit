// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module payment_kit::config;

use std::ascii;
use std::string;
use std::type_name::TypeName;

const EInvalidRegistryConfigType: u64 = 0;

public enum Value has copy, drop, store {
    U64(u64),
    Address(address),
    String(string::String),
    AsciiString(ascii::String),
    Bool(bool),
    Bytes(vector<u8>),
    Type(TypeName),
}

public(package) fun new_u64(value: u64): Value {
    Value::U64(value)
}

public(package) fun new_address(value: address): Value {
    Value::Address(value)
}

public(package) fun new_string(value: string::String): Value {
    Value::String(value)
}

public(package) fun new_ascii_string(value: ascii::String): Value {
    Value::AsciiString(value)
}

public(package) fun new_bool(value: bool): Value {
    Value::Bool(value)
}

public(package) fun new_bytes(value: vector<u8>): Value {
    Value::Bytes(value)
}

public(package) fun new_type(value: TypeName): Value {
    Value::Type(value)
}

public(package) fun as_u64(value: Value): u64 {
    match (value) {
        Value::U64(num) => num,
        _ => abort EInvalidRegistryConfigType,
    }
}

public(package) fun as_address(value: Value): address {
    match (value) {
        Value::Address(addr) => addr,
        _ => abort EInvalidRegistryConfigType,
    }
}

public(package) fun as_string(value: Value): string::String {
    match (value) {
        Value::String(str) => str,
        _ => abort EInvalidRegistryConfigType,
    }
}

public(package) fun as_ascii_string(value: Value): ascii::String {
    match (value) {
        Value::AsciiString(str) => str,
        _ => abort EInvalidRegistryConfigType,
    }
}

public(package) fun as_bool(value: Value): bool {
    match (value) {
        Value::Bool(val) => val,
        _ => abort EInvalidRegistryConfigType,
    }
}

public(package) fun as_bytes(value: Value): vector<u8> {
    match (value) {
        Value::Bytes(bytes) => bytes,
        _ => abort EInvalidRegistryConfigType,
    }
}

public(package) fun as_type(value: Value): TypeName {
    match (value) {
        Value::Type(type_name) => type_name,
        _ => abort EInvalidRegistryConfigType,
    }
}
