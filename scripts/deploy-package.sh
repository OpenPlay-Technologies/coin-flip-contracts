#!/bin/bash

# Deploy Coin Flip Package
# This script deploys the coin_flip package and extracts important IDs to environment variables

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

# Function to save deployment output to files
save_deployment_output() {
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
        "COIN_FLIP_VERSION" \
        "IMMUTABLE_TX_DIGEST"
    
    # Create latest symlink for easy access
    local latest_env="$output_dir/latest_coin_flip.env"
    
    ln -sf "${base_filename}.env" "$latest_env"
    
    print_success "Latest symlinks created for easy access"
    
    # Do not write any root-level files; env files live only under outputs
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
print_status "Deployment timestamp: $TIMESTAMP"

# If restore flag is provided, restore state and exit
if [ "$1" = "--restore" ]; then
    # Try to restore from outputs latest env
    if [ -f "outputs/$ACTIVE_ENV/latest_coin_flip.env" ]; then
        print_status "Restoring state from outputs/$ACTIVE_ENV/latest_coin_flip.env"
        source "outputs/$ACTIVE_ENV/latest_coin_flip.env"
        print_success "State restored successfully"
        
        # Print current state
        echo ""
        print_status "Current Coin Flip State:"
        echo "  CURRENT_COIN_FLIP_PACKAGE_ID: ${CURRENT_COIN_FLIP_PACKAGE_ID:-'Not set'}"
        echo "  ORIGINAL_COIN_FLIP_PACKAGE_ID: ${ORIGINAL_COIN_FLIP_PACKAGE_ID:-'Not set'}"
        echo "  COIN_FLIP_VERSION: ${COIN_FLIP_VERSION:-'Not set'}"
        echo "  COIN_FLIP_CAP: ${COIN_FLIP_CAP:-'Not set'}"
        echo "  COIN_FLIP_UPGRADE_CAP: ${COIN_FLIP_UPGRADE_CAP:-'Not set'}"
    else
        print_error "No state file found. Run deployment first."
        exit 1
    fi
    exit 0
fi

print_status "Deploying Coin Flip package..."

# Change to the coin flip package directory
cd package

# Deploy the package and capture the JSON output
print_status "Publishing package..."
DEPLOYMENT_OUTPUT=$(sui client publish --json)

# Check if deployment was successful
if echo "$DEPLOYMENT_OUTPUT" | jq -e '.effects.status.status == "success"' > /dev/null; then
    print_success "Package deployed successfully!"
else
    print_error "Package deployment failed!"
    echo "$DEPLOYMENT_OUTPUT" | jq '.effects.status'
    exit 1
fi

# Extract package information from the deployment output
print_status "Extracting package information..."

# Extract package ID
NEW_PACKAGE_ID=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.objectChanges[] | select(.type == "published") | .packageId')

# Extract cap (owned by the sender)
COIN_FLIP_CAP=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.objectChanges[] | select(.objectType != null and (.objectType | contains("::game::CoinFlipCap"))) | .objectId')

# Extract upgrade cap (owned by the sender)
COIN_FLIP_UPGRADE_CAP=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.objectChanges[] | select(.objectType != null and (.objectType | contains("::package::UpgradeCap"))) | .objectId')

# Validate extracted values
if [ -z "$NEW_PACKAGE_ID" ] || [ "$NEW_PACKAGE_ID" = "null" ]; then
    print_error "Failed to extract package ID"
    exit 1
fi

if [ -z "$COIN_FLIP_CAP" ] || [ "$COIN_FLIP_CAP" = "null" ]; then
    print_error "Failed to extract cap ID"
    exit 1
fi

if [ -z "$COIN_FLIP_UPGRADE_CAP" ] || [ "$COIN_FLIP_UPGRADE_CAP" = "null" ]; then
    print_error "Failed to extract upgrade cap ID"
    exit 1
fi

# Make package immutable by destroying the upgrade capability
print_status "Making package immutable by destroying upgrade capability..."
# Note: We don't use 2>&1 here because sui client may print warnings to stderr
# that would corrupt the JSON output (e.g., client/server version mismatch warnings)
IMMUTABLE_OUTPUT=$(sui client call \
    --package 0x2 \
    --module 'package' \
    --function 'make_immutable' \
    --args "$COIN_FLIP_UPGRADE_CAP" \
    --json)

# Check if the make_immutable call was successful
if echo "$IMMUTABLE_OUTPUT" | jq -e '.effects.status.status == "success"' > /dev/null 2>&1; then
    print_success "Package is now immutable - upgrade capability destroyed!"
    # Extract transaction digest
    IMMUTABLE_TX_DIGEST=$(echo "$IMMUTABLE_OUTPUT" | jq -r '.digest')
else
    print_error "Failed to make package immutable!"
    # Show the raw output first to help debug any parsing issues
    echo "Raw output:"
    echo "$IMMUTABLE_OUTPUT"
    echo ""
    echo "Parsed status (if available):"
    echo "$IMMUTABLE_OUTPUT" | jq '.effects.status' 2>/dev/null || echo "(Could not parse JSON)"
    exit 1
fi

# Get version number (this is a new deployment, so version 1)
COIN_FLIP_VERSION=1

# For initial deployment, both CURRENT and ORIGINAL are the same
CURRENT_COIN_FLIP_PACKAGE_ID="$NEW_PACKAGE_ID"
ORIGINAL_COIN_FLIP_PACKAGE_ID="$NEW_PACKAGE_ID"

# Export variables for current session
export CURRENT_COIN_FLIP_PACKAGE_ID
export ORIGINAL_COIN_FLIP_PACKAGE_ID
export COIN_FLIP_VERSION
export COIN_FLIP_CAP
export COIN_FLIP_UPGRADE_CAP
export IMMUTABLE_TX_DIGEST

# Return to root directory
cd ..

# Save version history
save_version_history "$ACTIVE_ENV" "$COIN_FLIP_VERSION" "$NEW_PACKAGE_ID"

# Save all deployment outputs to files
save_deployment_output "$ACTIVE_ENV" "$TIMESTAMP" "$COIN_FLIP_VERSION"

# Print summary
echo ""
print_success "Coin Flip deployment completed successfully!"
echo ""
print_status "Deployment Summary:"
echo "  Version: $COIN_FLIP_VERSION"
echo "  Current Package ID: $CURRENT_COIN_FLIP_PACKAGE_ID"
echo "  Original Package ID: $ORIGINAL_COIN_FLIP_PACKAGE_ID"
echo "  Cap: $COIN_FLIP_CAP"
echo "  Upgrade Cap: $COIN_FLIP_UPGRADE_CAP (Destroyed - package is now immutable)"
echo "  Immutable Tx: $IMMUTABLE_TX_DIGEST"
echo ""
print_status "Environment variables are now available in your current shell session."

