# Compute CRC-32 of a 32-bit word (big-endian) or of an arbitrary string.
# Usage:
#   crc32_word   0x1234ABCD    → decimal CRC32 of those four bytes
#   crc32_string "foo/bar"    → CRC32 of the literal string
crc32_word() {
  # $1 may be 0xHEX or decimal
  # normalize to exactly 8 hex digits
  local val=$1 hex
  # strip optional 0x prefix, convert decimal→hex if needed
  if [[ $val =~ ^0[xX] ]]; then
    hex=${val#0x}
  else
    printf -v hex '%08X' "$val"
  fi
  # make sure it's 8 digits
  hex=$(printf '%08s' "$hex" | tr ' ' '0')
  # turn into binary bytes and run cksum
  printf '%s' "$hex" | xxd -r -p | cksum | cut -d' ' -f1
}

crc32_string() {
  # CRC32 of arbitrary bytes of $1
  printf '%s' "$1" | cksum | cut -d' ' -f1
}

# Generate Docker-safe name:
#   $1 = filesystem path
#   $2 = descendant index (0 = parent, 1 = first child, etc.)
# Output: <slug>_<8-hex-of-crc>
generate_container_name() {
  local path="$1" idx="${2:-0}"
  local slug="${path#/}"; slug="${slug//\//_}"; slug="${slug//[^a-zA-Z0-9_]/_}"

  # parent CRC from the literal path string
  local parent_crc; parent_crc=$(crc32_string "$path")

  # walk CRC-chain idx times
  local cur=$parent_crc i
  for (( i=0; i<idx; i++ )); do
    cur=$(crc32_word "$cur")
  done

  # format as 8-digit uppercase hex
  printf '%s_%08X\n' "$slug" "$cur"
}
