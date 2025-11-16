#!/bin/bash

# Upgrade Coin Flip Package
# This script upgrades the coin_flip package using the original upgrade capability

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to get active environment
get_active_env() {
    sui client active-env 2>/dev/null || echo "unknown"
}

# Function to generate timestamp
get_timestamp() {
    date +"%Y%m%d_%H%M%S"
}

# Function to save version history
save_version_history() {
    local env="$1"
    local version="$2"
    local package_id="$3"
    local output_dir="outputs/$env"
    local versions_file="$output_dir/versions.txt"
    
    # Create output directory if it doesn't exist
    mkdir -p "$output_dir"
    
    # Create versions file if it doesn't exist
    if [ ! -f "$versions_file" ]; then
        > "$versions_file"
    fi
    
    # Append version entry: version_number:package_id
    echo "${version}:${package_id}" >> "$versions_file"
    print_success "Saved version $version to history: $package_id"
}

# Function to get next version number
get_next_version() {
    local env="$1"
    local output_dir="outputs/$env"
    local versions_file="$output_dir/versions.txt"
    
    if [ ! -f "$versions_file" ]; then
        echo "1"
    else
        # Get the last version number and increment
        local last_version=$(tail -n 1 "$versions_file" | cut -d':' -f1)
        if [ -z "$last_version" ]; then
            echo "1"
        else
            echo $((last_version + 1))
        fi
    fi
}

# Function to save upgrade output to files
save_upgrade_output() {
    local env="$1"
    local timestamp="$2"
    local version="$3"
    local output_dir="outputs/$env"
    local base_filename="coin_flip_${timestamp}"
    
    # Create environment-specific directory if it doesn't exist
    mkdir -p "$output_dir"
    
    # Save environment variables
    local env_file="$output_dir/${base_filename}.env"
    save_env_vars "$env_file" \
        "CURRENT_COIN_FLIP_PACKAGE_ID" \
        "ORIGINAL_COIN_FLIP_PACKAGE_ID" \
        "COIN_FLIP_CAP" \
        "COIN_FLIP_UPGRADE_CAP" \
        "COIN_FLIP_VERSION"
    
    # Create latest symlink for easy access
    local latest_env="$output_dir/latest_coin_flip.env"
    
    ln -sf "${base_filename}.env" "$latest_env"
    
    print_success "Latest symlinks created for easy access"
}

# Function to save environment variables to a file
save_env_vars() {
    local env_file="$1"
    shift
    local vars=("$@")
    
    print_status "Saving environment variables to $env_file"
    
    # Create or overwrite the env file
    > "$env_file"
    
    for var in "${vars[@]}"; do
        if [ -n "${!var}" ]; then
            echo "export $var=\"${!var}\"" >> "$env_file"
            print_success "Saved $var=${!var}"
        else
            print_warning "Variable $var is empty, skipping"
        fi
    done
    
    print_success "Environment variables saved to $env_file"
    print_status "To load these variables in your shell, run: source $env_file"
}

# Check if we're in the right directory
if [ ! -f "package/Move.toml" ]; then
    print_error "This script must be run from the coin-flip-contracts root directory"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    print_error "jq is required but not installed. Please install jq first."
    exit 1
fi

# Check if sui client is available
if ! command -v sui &> /dev/null; then
    print_error "sui client is not available. Please ensure Sui is installed and in your PATH."
    exit 1
fi

# Get active environment and timestamp
ACTIVE_ENV=$(get_active_env)
TIMESTAMP=$(get_timestamp)

print_status "Active environment: $ACTIVE_ENV"
print_status "Upgrade timestamp: $TIMESTAMP"

# Load latest state to get upgrade capability
if [ -f "outputs/$ACTIVE_ENV/latest_coin_flip.env" ]; then
    print_status "Loading latest deployment state..."
    source "outputs/$ACTIVE_ENV/latest_coin_flip.env"
    print_success "Loaded coin flip package environment variables"
else
    print_error "Coin flip package not deployed. Run ./scripts/deploy-package.sh first."
    exit 1
fi

# Validate that we have the required variables
if [ -z "$COIN_FLIP_UPGRADE_CAP" ] || [ "$COIN_FLIP_UPGRADE_CAP" = "null" ]; then
    print_error "Upgrade capability not found. Cannot proceed with upgrade."
    exit 1
fi

if [ -z "$ORIGINAL_COIN_FLIP_PACKAGE_ID" ] || [ "$ORIGINAL_COIN_FLIP_PACKAGE_ID" = "null" ]; then
    print_error "Original package ID not found. Cannot proceed with upgrade."
    exit 1
fi

# Preserve original values (ORIGINAL_* stays the same, but we need to track previous CURRENT for display)
ORIGINAL_UPGRADE_CAP="$COIN_FLIP_UPGRADE_CAP"
ORIGINAL_PACKAGE_ID="$ORIGINAL_COIN_FLIP_PACKAGE_ID"
PREVIOUS_PACKAGE_ID="${CURRENT_COIN_FLIP_PACKAGE_ID:-$ORIGINAL_COIN_FLIP_PACKAGE_ID}"
ORIGINAL_CAP="$COIN_FLIP_CAP"

# Get next version number
NEXT_VERSION=$(get_next_version "$ACTIVE_ENV")
print_status "Upgrading to version $NEXT_VERSION"

print_status "Upgrading Coin Flip package..."
print_status "Using upgrade capability: $ORIGINAL_UPGRADE_CAP"

# Change to the coin flip package directory
cd package

# Upgrade the package and capture the JSON output
print_status "Upgrading package..."
UPGRADE_OUTPUT=$(sui client upgrade --upgrade-capability "$ORIGINAL_UPGRADE_CAP" --json)

# Check if upgrade was successful
if echo "$UPGRADE_OUTPUT" | jq -e '.effects.status.status == "success"' > /dev/null; then
    print_success "Package upgraded successfully!"
else
    print_error "Package upgrade failed!"
    echo "$UPGRADE_OUTPUT" | jq '.effects.status'
    exit 1
fi

# Extract package information from the upgrade output
print_status "Extracting package information..."

# Extract new package ID from the published object
NEW_PACKAGE_ID=$(echo "$UPGRADE_OUTPUT" | jq -r '.objectChanges[] | select(.type == "published") | .packageId')

# Validate extracted values
if [ -z "$NEW_PACKAGE_ID" ] || [ "$NEW_PACKAGE_ID" = "null" ]; then
    print_error "Failed to extract new package ID"
    exit 1
fi

# Update version variables
COIN_FLIP_VERSION="$NEXT_VERSION"
CURRENT_COIN_FLIP_PACKAGE_ID="$NEW_PACKAGE_ID"
# Keep original values unchanged
ORIGINAL_COIN_FLIP_PACKAGE_ID="$ORIGINAL_PACKAGE_ID"
COIN_FLIP_CAP="$ORIGINAL_CAP"
COIN_FLIP_UPGRADE_CAP="$ORIGINAL_UPGRADE_CAP"

# Export variables for current session
export CURRENT_COIN_FLIP_PACKAGE_ID
export ORIGINAL_COIN_FLIP_PACKAGE_ID
export COIN_FLIP_VERSION
export COIN_FLIP_CAP
export COIN_FLIP_UPGRADE_CAP

# Return to root directory
cd ..

# Save version history
save_version_history "$ACTIVE_ENV" "$COIN_FLIP_VERSION" "$NEW_PACKAGE_ID"

# Save all upgrade outputs to files
save_upgrade_output "$ACTIVE_ENV" "$TIMESTAMP" "$COIN_FLIP_VERSION"

# Print summary
echo ""
print_success "Coin Flip upgrade completed successfully!"
echo ""
print_status "Upgrade Summary:"
echo "  Version: $COIN_FLIP_VERSION"
echo "  Previous Package ID: $PREVIOUS_PACKAGE_ID"
echo "  New Package ID: $CURRENT_COIN_FLIP_PACKAGE_ID"
echo "  Original Package ID: $ORIGINAL_COIN_FLIP_PACKAGE_ID"
echo "  Cap: $COIN_FLIP_CAP"
echo "  Upgrade Cap: $COIN_FLIP_UPGRADE_CAP"
echo ""
print_status "Environment variables are now available in your current shell session."

