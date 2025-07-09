# ClaudeBox Refactoring Fixes

## Critical Issues and Solutions

### 1. Variable Scoping in `run_claudebox_container` (lib/docker.sh:149)

**Issue**: The function uses `$project_folder_name` which is not defined in scope.

**Fix**: The variable should be passed or derived from the environment:

```bash
# In run_claudebox_container function, replace line 149:
-e "CLAUDEBOX_PROJECT_NAME=$project_folder_name"
# With:
-e "CLAUDEBOX_PROJECT_NAME=${CLAUDEBOX_PROJECT_NAME:-$(basename "$PROJECT_CLAUDEBOX_DIR")}"
```

### 2. Image Name Consistency

**Issue**: Docker image names must be consistent across all slots in a project.

**Current behavior**:
- `get_image_name()` uses the parent folder name
- But the parent folder name includes a CRC hash which may change

**Fix**: Ensure image name is based on the parent directory consistently:

```bash
# In lib/project.sh, update get_image_name():
get_image_name() {
    local parent_folder_name=$(basename "$(get_parent_dir "${PROJECT_DIR}")")
    printf 'claudebox-%s' "${parent_folder_name}"
}
```

### 3. Shell Command Error Handling

**Issue**: `_cmd_shell` doesn't properly handle missing slots.

**Fix**: Add proper error checking:

```bash
# In lib/commands.sh:374-378, replace:
project_folder_name=$(get_project_folder_name "$PROJECT_DIR"  || echo "NONE")

if [[ "$project_folder_name" == "NONE" ]]; then
    error "No container slots available. Please run 'claudebox create' to create a container slot."
fi
```

### 4. Documentation Update

**Issue**: CLAUDE.md incorrectly states slot management is in lib/docker.sh

**Fix**: Update CLAUDE.md line 54:
```
- Slot detection and management in `lib/project.sh`
```

### 5. Lock File Cleanup

**Issue**: Lock files may not be cleaned up on container errors.

**Fix**: Add trap for cleanup in run_claudebox_container:

```bash
# Add after line 163 in lib/docker.sh:
if [[ "$run_mode" != "pipe" ]]; then
    trap "rm -f '$lock_file'" EXIT
    echo $$ > "$lock_file"
fi
```

### 6. Create Command Flow

**Issue**: The `create` command flow is confusing - it creates a slot but then tries to use a different image name.

**Fix**: Ensure consistent image naming:
1. All slots in a project share the same Docker image
2. The image name is based on the parent directory name
3. Authentication is per-slot, not per-image

### 7. Missing PROJECT_CLAUDEBOX_DIR Export

**Issue**: Several commands don't properly export PROJECT_CLAUDEBOX_DIR before calling functions that need it.

**Fix**: Ensure it's set whenever we have a slot name:

```bash
# Add after getting project_folder_name:
if [[ -n "$project_folder_name" ]] && [[ "$project_folder_name" != "NONE" ]]; then
    PROJECT_CLAUDEBOX_DIR="$PROJECT_PARENT_DIR/$project_folder_name"
    export PROJECT_CLAUDEBOX_DIR
fi
```

### 8. Slot Selection Menu

**Issue**: When multiple slots exist, there's no way to choose which one to use.

**Recommendation**: Add a slot selection mechanism when multiple unlocked slots are available.

## Testing Recommendations

1. Test creating multiple slots:
   ```bash
   claudebox create  # Create slot 1
   claudebox create  # Create slot 2
   claudebox slots   # List all slots
   ```

2. Test concurrent usage:
   ```bash
   # Terminal 1
   claudebox shell
   
   # Terminal 2  
   claudebox shell  # Should use different slot
   ```

3. Test error cases:
   ```bash
   # Remove all slots
   rm -rf ~/.claudebox/projects/*/
   claudebox shell  # Should show helpful error
   ```

## Implementation Priority

1. **Critical**: Fix variable scoping in run_claudebox_container
2. **Critical**: Fix shell command error handling  
3. **Important**: Ensure consistent image naming
4. **Important**: Add proper lock file cleanup
5. **Nice to have**: Add slot selection menu
6. **Documentation**: Update CLAUDE.md

## Next Steps

1. Apply the critical fixes first
2. Test multi-slot functionality thoroughly
3. Consider adding a `claudebox switch <slot>` command
4. Add integration tests for multi-slot scenarios

## UI/UX Improvements Implemented

### Enhanced User Experience

1. **Professional No-Slots Menu** (`show_no_slots_menu`)
   - Clear visual hierarchy with ASCII art header
   - Grouped commands by category
   - Helpful descriptions and examples
   - Prominent call-to-action for new users

2. **Welcome Screen for First-Time Users** (`show_welcome_screen`)
   - Friendly introduction to ClaudeBox
   - Key features overview
   - Quick start guide
   - Press Enter to continue flow

3. **Building Progress Screen** (`show_building_screen`)
   - Clear indication of what's happening
   - Expected actions listed
   - Time expectation set

4. **Enhanced Profiles Display** (`_cmd_profiles`)
   - Profiles grouped by category (Languages, Frameworks, Tools)
   - Visual indicators for enabled profiles
   - Clear usage examples

5. **Improved Slots Listing** (`list_project_slots`)
   - Professional layout with borders
   - Status icons (🟢 Active, ⚪ Available, 🔒 Stale Lock, 💀 Dead)
   - Authentication status clearly shown
   - Summary statistics
   - Contextual tips based on slot state

6. **Projects Overview Enhancement** (`_cmd_projects`)
   - Clear legend explaining icons
   - Better formatting with visual separators
   - Helpful next steps for new users

### Color Scheme

- Added `DIM` color for subtle text
- Consistent use of colors:
  - `CYAN` - Headers and branding
  - `WHITE` - Section titles
  - `GREEN` - Commands and success
  - `YELLOW` - Warnings and tips
  - `DIM` - Descriptions and secondary info
  - `RED` - Errors

### Design Principles

1. **Clear Information Hierarchy** - Most important info stands out
2. **Contextual Help** - Tips appear when relevant
3. **Professional Appearance** - Polished, not cluttered
4. **Consistent Formatting** - Similar screens follow same patterns
5. **User Guidance** - Always show next steps