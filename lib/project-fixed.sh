#!/usr/bin/env bash
# Fixed CRC32 functions that work on Mac and Linux without xxd
# ============================================================================
# CRC32 Functions
# ============================================================================

# Compute CRC-32 of a string (for chaining)
crc32_word() {
    local val=$1
    # Simply hash the value as a string - no need for hex conversion
    printf '%s' "$val" | cksum | cut -d' ' -f1
}

# Compute CRC-32 of an arbitrary string; returns decimal 0..2^32-1
crc32_string() {
    printf '%s' "$1" | cksum | cut -d' ' -f1
}

# Compute CRC-32 of a file
crc32_file() {
    if [[ -f "$1" ]]; then
        cksum "$1" | cut -d' ' -f1
    else
        echo "0"
    fi
}