#!/usr/bin/env bash
#
# generate_project_containers.sh
#
# Pure Bash script to slugify a filesystem path into a parent project_container folder,
# manage creation of container slots, reuse dead slots, robustly link a shared profiles.ini,
# handle concurrent counter updates, and verify symlink integrity.

# Compute CRC-32 of a 32-bit word (big-endian or decimal input)
crc32_word() {
  local val=$1 hex
  if [[ $val =~ ^0[xX] ]]; then
    hex=${val#0x}
  else
    printf -v hex '%08X' "$val"
  fi
  hex=$(printf '%08s' "$hex" | tr ' ' '0')
  printf '%s' "$hex" | xxd -r -p | cksum | cut -d' ' -f1
}

# Compute CRC-32 of an arbitrary string; returns decimal 0..2^32-1
crc32_string() {
  printf '%s' "$1" | cksum | cut -d' ' -f1
}

# Slugify a filesystem path: strip leading '/', replace '/'→'_', remove unsafe chars
slugify_path() {
  local path=${1#/}
  path=${path//\//_}
  printf '%s' "${path//[^a-zA-Z0-9_]/_}"
}

# Generate a container name for a given path and index
generate_container_name() {
  local path="$1" idx="$2"
  local slug; slug=$(slugify_path "$path")
  local base_crc; base_crc=$(crc32_string "$path")
  local cur=$base_crc
  for ((i=0; i<idx; i++)); do
    cur=$(crc32_word "$cur")
  done
  printf '%s_%08X' "$slug" "$cur"
}

# Compute parent project directory: demo/<slug>_<crc-of-index-0>
get_parent_dir() {
  echo "demo/$(generate_container_name "$1" 0)"
}

# Verify and (re)create profiles.ini symlink in all slots
verify_symlinks() {
  local parent="$1"
  for dir in "$parent"/*/; do
    [[ -d "$dir" ]] || continue
    local link="$dir/profiles.ini"
    if [[ ! -L "$link" ]] || [[ ! -e "$link" ]]; then
      ln -sfn "../profiles.ini" "$link"
    fi
  done
}

# Initialize project directory: create parent, counter, central profiles.ini, and verify children
init_project_dir() {
  local path="$1" parent
  parent=$(get_parent_dir "$path")
  mkdir -p "$parent"
  # initialize counter if missing
  [[ -f "$parent/.project_container_counter" ]] || printf '1' > "$parent/.project_container_counter"
  # ensure central profiles.ini
  [[ -f "$parent/profiles.ini" ]] || touch "$parent/profiles.ini"
  # ensure child symlinks are valid
  verify_symlinks "$parent"
}

# Read/write per-project counter with locking
read_counter() {
  local p="$1" val=1
  [[ -f "$p/.project_container_counter" ]] && read -r val < "$p/.project_container_counter"
  echo "$val"
}
write_counter() {
  local p="$1" val="$2"
  printf '%d' "$val" > "$p/.project_container_counter"
}

# Acquire/release a lock on the counter via mkdir
lock_counter() {
  local p="$1" lockdir="$p/.counter.lock"
  while ! mkdir "$lockdir" 2>/dev/null; do
    sleep 0.05
  done
}
unlock_counter() {
  local p="$1" lockdir="$p/.counter.lock"
  rmdir "$lockdir"
}

# Create or reuse a container slot:
# - Reuse missing "dead" slots first
# - Otherwise create next new slot
# - Symlink shared profiles.ini
# - Protect counter updates with lock
create_container() {
  local path="$1" parent idx max name dir
  init_project_dir "$path"
  parent=$(get_parent_dir "$path")

  # lock counter and read max
  lock_counter "$parent"
  max=$(read_counter "$parent")

  # attempt dead-slot reuse
  for ((idx=0; idx<max; idx++)); do
    name=$(generate_container_name "$path" "$idx")
    dir="$parent/$name"
    if [[ ! -d "$dir" ]]; then
      mkdir -p "$dir"
      ln -sfn "../profiles.ini" "$dir/profiles.ini"
      unlock_counter "$parent"
      echo "$name"
      return
    fi
  done

  # no dead slot: provision new at index=max
  idx=$max
  name=$(generate_container_name "$path" "$idx")
  dir="$parent/$name"
  mkdir -p "$dir"
  ln -sfn "../profiles.ini" "$dir/profiles.ini"
  write_counter "$parent" $((max + 1))
  unlock_counter "$parent"
  echo "$name"
}

# Determine next container to start (skipping in-use & stale locks)
determine_next_start_container() {
  local path="$1" parent max idx name dir lockfile pid
  parent=$(get_parent_dir "$path")
  max=$(read_counter "$parent")
  for ((idx=0; idx<max; idx++)); do
    name=$(generate_container_name "$path" "$idx")
    dir="$parent/$name"
    # dead slot => ready
    [[ -d "$dir" ]] || { echo "$name"; return 0; }
    lockfile="$dir/lock"
    # unlocked slot => ready
    [[ -f "$lockfile" ]] || { echo "$name"; return 0; }
    pid=$(<"$lockfile")
    # stale lock => ready
    if ! ps -p "$pid" > /dev/null; then
      rm -f "$lockfile"
      echo "$name"; return 0
    fi
  done
  return 1
}

# Demo: creation, reuse, symlink verification, start determination
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  local path="/home/user/project" parent name next
  echo "Demo: managing slots for $path"

  echo "Creating 5 slots (with dead-slot reuse)"
  for _ in {1..5}; do
    name=$(create_container "$path")
    echo "  Slot: $(get_parent_dir "$path")/$name"
  done

  echo
  parent=$(get_parent_dir "$path")
  # simulate dead slot at idx=2
  name=$(generate_container_name "$path" 2)
  echo "Simulating dead slot removal: $name"
  rm -rf "$parent/$name"

  echo
  echo "Recreating profiles.ini to test symlink integrity"
  rm -f "$parent/profiles.ini"
  touch "$parent/profiles.ini"
  init_project_dir "$path"
  echo "Verified symlinks."

  echo
  echo "Reusing dead slot via create_container:"
  name=$(create_container "$path")
  echo "  Reused: $(get_parent_dir "$path")/$name"

  echo
  echo "Next container to start (skipping in-use/stale)"
  if next=$(determine_next_start_container "$path"); then
    echo "  Next start: $next"
  else
    echo "  No available slot"
  fi
fi
