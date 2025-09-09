module sui_payment_standard::config_value;

use std::ascii;
use std::string;
use std::type_name::TypeName;

const EInvalidConfigType: u64 = 0;

public enum ConfigValue has copy, drop, store {
    U64(u64),
    Address(address),
    String(string::String),
    AsciiString(ascii::String),
    Bool(bool),
    Bytes(vector<u8>),
    Type(TypeName),
}

public(package) fun new_u64(value: u64): ConfigValue {
    ConfigValue::U64(value)
}

public(package) fun new_address(value: address): ConfigValue {
    ConfigValue::Address(value)
}

public(package) fun new_string(value: string::String): ConfigValue {
    ConfigValue::String(value)
}

public(package) fun new_ascii_string(value: ascii::String): ConfigValue {
    ConfigValue::AsciiString(value)
}

public(package) fun new_bool(value: bool): ConfigValue {
    ConfigValue::Bool(value)
}

public(package) fun new_bytes(value: vector<u8>): ConfigValue {
    ConfigValue::Bytes(value)
}

public(package) fun new_type(value: TypeName): ConfigValue {
    ConfigValue::Type(value)
}

public(package) fun as_u64(value: ConfigValue): u64 {
    match (value) {
        ConfigValue::U64(num) => num,
        _ => abort EInvalidConfigType,
    }
}

public(package) fun as_address(value: ConfigValue): address {
    match (value) {
        ConfigValue::Address(addr) => addr,
        _ => abort EInvalidConfigType,
    }
}

public(package) fun as_string(value: ConfigValue): string::String {
    match (value) {
        ConfigValue::String(str) => str,
        _ => abort EInvalidConfigType,
    }
}

public(package) fun as_ascii_string(value: ConfigValue): ascii::String {
    match (value) {
        ConfigValue::AsciiString(str) => str,
        _ => abort EInvalidConfigType,
    }
}

public(package) fun as_bool(value: ConfigValue): bool {
    match (value) {
        ConfigValue::Bool(val) => val,
        _ => abort EInvalidConfigType,
    }
}

public(package) fun as_bytes(value: ConfigValue): vector<u8> {
    match (value) {
        ConfigValue::Bytes(bytes) => bytes,
        _ => abort EInvalidConfigType,
    }
}

public(package) fun as_type(value: ConfigValue): TypeName {
    match (value) {
        ConfigValue::Type(type_name) => type_name,
        _ => abort EInvalidConfigType,
    }
}
