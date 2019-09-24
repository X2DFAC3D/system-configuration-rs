#!/usr/bin/env bash

# Always have the latest version of bindgen and rustfmt installed before using this script.
# This script require GNU sed, and does not work with the default macOS sed: `brew install gnu-sed`.

set -eu

export DYLD_LIBRARY_PATH=$(rustc +stable --print sysroot)/lib

SDK_VERSION=`xcodebuild -sdk macosx -version SDKVersion`
SDK_PATH=`xcodebuild -sdk macosx -version Path`
FRAMEWORK_PATH="$SDK_PATH/System/Library/Frameworks/"

PREFERENCES_HEADER_PATH="$FRAMEWORK_PATH/SystemConfiguration.framework/Headers/SCPreferences.h"
DYNAMIC_STORE_HEADER_PATH="$FRAMEWORK_PATH/SystemConfiguration.framework/Headers/SCDynamicStore.h"
NETWORK_CONFIGURATION_HEADER_PATH="$FRAMEWORK_PATH/SystemConfiguration.framework/Headers/SCNetworkConfiguration.h"
SCHEMA_DEFINITIONS_HEADER_PATH="$FRAMEWORK_PATH/SystemConfiguration.framework/Headers/SCSchemaDefinitions.h"

PREFERENCES_BINDING_PATH="./system-configuration-sys/src/preferences.rs"
DYNAMIC_STORE_BINDING_PATH="./system-configuration-sys/src/dynamic_store.rs"
NETWORK_CONFIGURATION_BINDING_PATH="./system-configuration-sys/src/network_configuration.rs"
SCHEMA_DEFINITIONS_BINDING_PATH="./system-configuration-sys/src/schema_definitions.rs"

BINDGEN_VERSION=`bindgen --version`

echo "Using macOS SDK at: $SDK_PATH"
echo "Using $BINDGEN_VERSION"
echo ""

function cleanup_binding() {
    local binding_path="$1"

    # `Option` is in the Rust standard prelude. No need to use full path, it's just verbose.
    sed -i 's/::core::option::Option/Option/g' "$binding_path"

    # The bindings that need these types will import them directly into scope with `--raw line`
    sed -i 's/::std::os::raw:://g' "$binding_path"

    # Most low level types should not be `Copy` nor `Clone`. And `Debug` usually don't make much
    # sense, since they are usually just pointers/binary data.
    sed -i '/#\[derive(Debug, Copy, Clone)\]/d' "$binding_path"

    # Change struct bodies to (c_void);
    #   Search regex: {\n +_unused: \[u8; 0],\n}
    #   Replace string: (c_void);\n
    sed -i -e '/^pub struct .* {$/ {
        N;N
        s/ {\n *_unused: \[u8; 0\],\n}/(c_void);\n/
    }' "$binding_path"

    # Remove all }\nextern "C" { to condense code a bit
    #   Search regex: }\nextern "C" {
    #   Replace string:
    sed -i -e '/^extern "C" {$/ {
        :loop
        n
        /^}$/! b loop
        /^}$/ {
            N
            t reset_condition_flags
            :reset_condition_flags
            s/}\nextern "C" {//
            t loop
        }
    }' "$binding_path"

    rustfmt +nightly "$binding_path"
}

BINDGEN_COMMON_ARGUMENTS=(
    --no-doc-comments
    --use-core
    --no-layout-tests
    --raw-line "// Generated using:"
    --raw-line "// $BINDGEN_VERSION"
    --raw-line "// macOS SDK $SDK_VERSION."
    --raw-line ""
)

echo "Generating bindings for $PREFERENCES_HEADER_PATH"
bindgen \
    "${BINDGEN_COMMON_ARGUMENTS[@]}" \
    --whitelist-function "SCPreferences.*" \
    --blacklist-type "(__)?CF.*" \
    --blacklist-type "Boolean" \
    --blacklist-type "dispatch_queue_[ts]" \
    --blacklist-type "(AuthorizationOpaqueRef|__SCPreferences)" \
    --raw-line "use core::ffi::c_void;" \
    --raw-line "use core_foundation_sys::array::CFArrayRef;" \
    --raw-line "use core_foundation_sys::base::{Boolean, CFIndex, CFAllocatorRef, CFTypeID};" \
    --raw-line "use core_foundation_sys::data::CFDataRef;" \
    --raw-line "use core_foundation_sys::string::CFStringRef;" \
    --raw-line "use core_foundation_sys::propertylist::CFPropertyListRef;" \
    --raw-line "use core_foundation_sys::runloop::CFRunLoopRef;" \
    --raw-line "" \
    --raw-line "use dispatch_queue_t;" \
    --raw-line "" \
    --raw-line "pub type AuthorizationOpaqueRef = c_void;" \
    --raw-line "pub type __SCPreferences = c_void;" \
    -o $PREFERENCES_BINDING_PATH \
    $PREFERENCES_HEADER_PATH -- \
    -I$SDK_PATH/usr/include \
    -F$FRAMEWORK_PATH

cleanup_binding $PREFERENCES_BINDING_PATH

echo ""
echo ""
echo "Generating bindings for $DYNAMIC_STORE_HEADER_PATH"
sleep 2

bindgen \
    "${BINDGEN_COMMON_ARGUMENTS[@]}" \
    --whitelist-function "SCDynamicStore.*" \
    --whitelist-var "kSCDynamicStore.*" \
    --blacklist-type "(__)?CF.*" \
    --blacklist-type "Boolean" \
    --blacklist-type "dispatch_queue_[ts]" \
    --raw-line "use core::ffi::c_void;" \
    --raw-line "use core_foundation_sys::array::CFArrayRef;" \
    --raw-line "use core_foundation_sys::base::{Boolean, CFIndex, CFAllocatorRef, CFTypeID};" \
    --raw-line "use core_foundation_sys::string::CFStringRef;" \
    --raw-line "use core_foundation_sys::dictionary::CFDictionaryRef;" \
    --raw-line "use core_foundation_sys::propertylist::CFPropertyListRef;" \
    --raw-line "use core_foundation_sys::runloop::CFRunLoopSourceRef;" \
    --raw-line "" \
    --raw-line "use dispatch_queue_t;" \
    -o $DYNAMIC_STORE_BINDING_PATH \
    $DYNAMIC_STORE_HEADER_PATH -- \
    -I$SDK_PATH/usr/include \
    -F$FRAMEWORK_PATH

cleanup_binding $DYNAMIC_STORE_BINDING_PATH

echo ""
echo ""
echo "Generating bindings for $NETWORK_CONFIGURATION_HEADER_PATH"
sleep 2

bindgen \
    "${BINDGEN_COMMON_ARGUMENTS[@]}" \
    --whitelist-function "SCNetwork.*" \
    --whitelist-function "SCBondInterface.*" \
    --whitelist-var "kSC(NetworkInterface|BondStatus).*" \
    --blacklist-type "dispatch_queue_[ts]" \
    --blacklist-type "(__)?CF.*" \
    --blacklist-type "__SC.*" \
    --blacklist-type "Boolean" \
    --blacklist-type "(sockaddr|socklen_t|sa_family_t|__darwin_socklen_t|__uint.*_t)" \
    --blacklist-type "(__)?SCPreferences.*" \
    --raw-line "use core::ffi::c_void;" \
    --raw-line "use core_foundation_sys::array::CFArrayRef;" \
    --raw-line "use core_foundation_sys::base::{Boolean, CFIndex, CFAllocatorRef, CFTypeID};" \
    --raw-line "use core_foundation_sys::string::CFStringRef;" \
    --raw-line "use core_foundation_sys::dictionary::CFDictionaryRef;" \
    --raw-line "use core_foundation_sys::runloop::CFRunLoopRef;" \
    --raw-line "" \
    --raw-line "use dispatch_queue_t;" \
    --raw-line "use libc::{c_char, c_int, sockaddr, socklen_t};" \
    --raw-line "use preferences::SCPreferencesRef;" \
    --raw-line "" \
    --raw-line "pub type __SCNetworkReachability = c_void;" \
    --raw-line "pub type __SCNetworkConnection = c_void;" \
    --raw-line "pub type __SCNetworkInterface = c_void;" \
    --raw-line "pub type __SCBondStatus = c_void;" \
    --raw-line "pub type __SCNetworkProtocol = c_void;" \
    --raw-line "pub type __SCNetworkService = c_void;" \
    --raw-line "pub type __SCNetworkSet = c_void;" \
    -o $NETWORK_CONFIGURATION_BINDING_PATH \
    $NETWORK_CONFIGURATION_HEADER_PATH -- \
    -I$SDK_PATH/usr/include \
    -F$FRAMEWORK_PATH

cleanup_binding $NETWORK_CONFIGURATION_BINDING_PATH

echo ""
echo ""
echo "Generating bindings for $SCHEMA_DEFINITIONS_HEADER_PATH"
sleep 2

bindgen \
    "${BINDGEN_COMMON_ARGUMENTS[@]}" \
    --whitelist-var "kSC.*" \
    --blacklist-type "(__)?CF.*" \
    --raw-line "use core_foundation_sys::string::CFStringRef;" \
    --raw-line "" \
    -o $SCHEMA_DEFINITIONS_BINDING_PATH \
    $SCHEMA_DEFINITIONS_HEADER_PATH -- \
    -I$SDK_PATH/usr/include \
    -F$FRAMEWORK_PATH

cleanup_binding $SCHEMA_DEFINITIONS_BINDING_PATH
