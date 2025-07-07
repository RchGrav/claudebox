# ClaudeBox Part 2 Documentation

## Overview

This part contains the main execution logic of ClaudeBox, including:
- Docker build function
- The main() function that orchestrates all ClaudeBox operations
- Command-line argument parsing and routing
- Profile and package management
- Docker image building and management
- Project cleanup operations
- Various utility commands

## Key Functions

### 1. `run_docker_build()`
**Lines:** 1-11
**Purpose:** Executes Docker build with BuildKit enabled
**Parameters:**
- `$1` - Dockerfile path
- `$2` - Build context directory

**Key Features:**
- Uses DOCKER_BUILDKIT=1 for improved build performance
- Passes build arguments for user/group IDs, username, versions
- Supports rebuild timestamp for cache busting

### 2. `main()`
**Lines:** 13-1021
**Purpose:** Main entry point that handles all ClaudeBox commands and operations

**Major Sections:**

#### Initial Setup (Lines 14-77)
- Updates symlink
- Gets project folder name
- Sets IMAGE_NAME
- Checks Docker status and configures if needed
- Processes command-line arguments (rebuild, verbose flags)
- Sets up project variables and directories
- Handles help flags early

#### Command Routing (Lines 78-923)
The main function handles numerous commands:

##### Profile Management Commands
- **`profiles`** (Lines 80-89): Lists all available ClaudeBox profiles
- **`profile`** (Lines 111-205): Manages project profiles
  - Sub-commands: list, status, or profile names to install
  - Updates profile configuration file
  - Validates profile existence

##### Project Management Commands
- **`projects`** (Lines 91-109): Lists all ClaudeBox projects with size and path
- **`save`** (Lines 206-223): Saves default command-line flags
- **`install`** (Lines 224-242): Installs additional packages to the project

##### Docker/Container Commands
- **`shell`** (Lines 254-325): Opens interactive shell in container
  - Special "admin" mode that persists changes
  - Supports --enable-sudo and --disable-firewall flags
- **`update`** (Lines 327-421): Updates Claude and/or ClaudeBox
  - Special "update all" mode updates everything
  - Creates backups before updating
- **`config`, `mcp`, `migrate-installer`** (Lines 423-466): Various configuration commands

##### Utility Commands
- **`allowlist`** (Lines 468-507): Manages firewall allowlist for domains
- **`unlink`** (Lines 244-252): Removes claudebox symlink
- **`clean`** (Lines 509-705): Extensive cleanup options:
  - `clean all`: Complete Docker cleanup
  - `clean image`: Remove containers and image
  - `clean cache`: Remove build cache
  - `clean volumes`: Remove Docker volumes
  - `clean containers`: Remove containers only
  - `clean dangling`: Remove dangling images
  - `clean logs`: Clear container logs
  - `clean project`: Project-specific cleanup with sub-options
- **`undo`** (Lines 708-730): Restore oldest claudebox backup
- **`redo`** (Lines 732-754): Restore newest claudebox backup
- **`info`** (Lines 761-921): Displays comprehensive system information

#### Docker Image Building (Lines 924-1021)
- Checks if Docker image exists and is up-to-date
- Calculates build hash based on script and profiles
- Determines if rebuild is needed based on:
  - Script changes
  - Profile changes
  - Missing image
- Sets up build context and triggers Docker build

## Key Variables and Constants

### Global Variables Used
- `$PROJECT_DIR` - Current project directory
- `$IMAGE_NAME` - Docker image name (claudebox-{project-folder-name})
- `$PROJECT_CLAUDEBOX_DIR` - Project-specific ClaudeBox directory
- `$DOCKER_USER` - Docker container username
- `$USER_ID`, `$GROUP_ID` - User and group IDs for container
- `$NODE_VERSION` - Node.js version for container
- `$DELTA_VERSION` - Git-delta version
- `$VERBOSE` - Verbose output flag
- `$CLAUDEBOX_NO_CACHE` - Force rebuild flag

### Configuration Files
- `$HOME/.claudebox/default-flags` - Saved default command flags
- `$PROJECT_CLAUDEBOX_DIR/config.ini` - Project configuration (profiles, packages)
- `$PROJECT_CLAUDEBOX_DIR/allowlist` - Firewall allowlist
- `$HOME/.claudebox/.last_build_hash` - Track build changes
- `$HOME/.claudebox/backups/*` - Backup files for undo/redo

## Special Logic and Flows

### Docker Status Handling
The script checks Docker availability and handles three cases:
1. Docker not installed - triggers installation
2. Docker installed but not running - starts service
3. Docker requires sudo - configures non-root access

### Profile System
- Profiles are predefined development environment configurations
- Multiple profiles can be active simultaneously
- Profiles are stored in the project's config.ini file
- Changes to profiles trigger Docker image rebuild

### Build Hash System
- Calculates hash from script content and active profiles
- Stores hash to detect when rebuild is needed
- Prevents unnecessary rebuilds when nothing has changed

### Admin Shell Mode
- Special persistent shell mode accessed via `claudebox shell admin`
- Changes made in admin mode are committed back to the Docker image
- Automatically enables sudo and disables firewall in admin mode

### Update System
- Can update Claude, ClaudeBox script, or both
- Downloads from GitHub repository
- Creates backups before updating
- Supports undo/redo functionality

## Dependencies and Interactions

### External Dependencies
- Docker and Docker BuildKit
- Standard Unix utilities (curl/wget, awk, sed, grep)
- Git (for various operations)
- SystemD (for Docker service management on Linux)

### Function Dependencies (from other parts)
- `update_symlink()` - Updates claudebox command symlink
- `get_project_folder_name()` - Gets sanitized project folder name
- `check_docker()` - Checks Docker installation status
- `install_docker()` - Installs Docker if missing
- `configure_docker_nonroot()` - Sets up Docker for non-root access
- `show_help()` - Displays help information
- `get_all_profile_names()` - Lists available profiles
- `get_profile_description()` - Gets profile description
- `list_all_projects()` - Lists all ClaudeBox projects
- `get_profile_file_path()` - Gets profile configuration path
- `read_profile_section()` - Reads profile configuration
- `profile_exists()` - Checks if profile exists
- `update_profile_section()` - Updates profile configuration
- `read_config_value()` - Reads configuration values
- `resolve_project_path()` - Resolves project path
- `logo()` - Displays ClaudeBox logo
- `fillbar()` - Shows progress bar
- `run_claudebox_container()` - Runs Docker container
- `setup_shared_commands()` - Sets up shared command directory
- `setup_project_folder()` - Sets up project folder
- `setup_claude_agent_command()` - Sets up Claude agent command
- `create_build_files()` - Creates Docker build files

### Color/Output Functions Used
- `info()`, `warn()`, `error()`, `success()` - Colored output messages
- `cecho()` - Colored echo function
- Color constants: `$CYAN`, `$GREEN`, `$YELLOW`, `$RED`, `$PURPLE`, `$WHITE`, `$NC`

## Notes

1. The file appears to be incomplete, ending abruptly at line 1021 during the Docker build setup
2. The main() function is extensive and handles all command routing
3. Heavy use of Docker labels and metadata for tracking project state
4. Comprehensive error handling and user feedback throughout
5. Support for multiple projects with isolated configurations
6. Emphasis on cleanup and maintenance operations