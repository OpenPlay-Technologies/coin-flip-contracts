#!/bin/bash

# Manage Coin Flip Game Version Allow/Disallow
# This script allows or disallows a specific version for a Coin Flip game instance

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

# Function to show usage
show_usage() {
    echo ""
    echo "Usage: $0 <game_instance_id> <action> <version>"
    echo ""
    echo "Arguments:"
    echo "  game_instance_id  - Hexadecimal address of the game instance"
    echo "  action            - 'allow' or 'disallow'"
    echo "  version           - Version number (u64) to allow or disallow"
    echo ""
    echo "Examples:"
    echo "  $0 0xabc123... allow 2"
    echo "  $0 0xabc123... disallow 1"
    echo ""
}

# Check if we're in the right directory
if [ ! -f "packages/coin_flip/Move.toml" ]; then
    print_error "This script must be run from the openplay-framework root directory"
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

# Validate arguments
if [ $# -ne 3 ]; then
    print_error "Invalid number of arguments"
    show_usage
    exit 1
fi

GAME_INSTANCE_ID="$1"
ACTION="$2"
VERSION="$3"

# Validate game instance ID (should start with 0x and be hexadecimal)
if [[ ! "$GAME_INSTANCE_ID" =~ ^0x[0-9a-fA-F]+$ ]]; then
    print_error "Invalid game instance ID format. Must be a hexadecimal address starting with 0x"
    exit 1
fi

# Validate action
if [ "$ACTION" != "allow" ] && [ "$ACTION" != "disallow" ]; then
    print_error "Invalid action: $ACTION"
    print_error "Action must be either 'allow' or 'disallow'"
    show_usage
    exit 1
fi

# Validate version is a positive integer
if ! [[ "$VERSION" =~ ^[0-9]+$ ]] || [ "$VERSION" -le 0 ]; then
    print_error "Version must be a positive integer"
    exit 1
fi

# Get active environment
ACTIVE_ENV=$(get_active_env)

print_status "Active environment: $ACTIVE_ENV"
print_status "Game Instance ID: $GAME_INSTANCE_ID"
print_status "Action: $ACTION"
print_status "Version: $VERSION"

# Load latest coin flip package state
if [ -f "outputs/$ACTIVE_ENV/latest_coin_flip.env" ]; then
    print_status "Loading latest coin flip deployment state..."
    source "outputs/$ACTIVE_ENV/latest_coin_flip.env"
    print_success "Loaded coin flip package environment variables"
else
    print_error "Coin flip package not deployed. Run ./scripts/deploy-coin-flip.sh first."
    exit 1
fi

# Validate that we have the required variables
if [ -z "$CURRENT_coin_flip_PACKAGE_ID" ] || [ "$CURRENT_coin_flip_PACKAGE_ID" = "null" ]; then
    print_error "Coin flip package ID not found. Cannot proceed."
    exit 1
fi

if [ -z "$coin_flip_CAP" ] || [ "$coin_flip_CAP" = "null" ]; then
    print_error "Coin flip cap not found. Cannot proceed."
    exit 1
fi

# Set package variables for convenience
COIN_FLIP_PACKAGE_ID="$CURRENT_coin_flip_PACKAGE_ID"
COIN_FLIP_CAP="$coin_flip_CAP"

print_status "Using Coin Flip Package: $COIN_FLIP_PACKAGE_ID"
print_status "Using Coin Flip Cap: $COIN_FLIP_CAP"

# Determine the function to call based on action
if [ "$ACTION" = "allow" ]; then
    FUNCTION_NAME="admin_allow_version"
    ACTION_DESCRIPTION="allowing"
    ACTION_DESCRIPTION_CAP="Allowing"
else
    FUNCTION_NAME="admin_disallow_version"
    ACTION_DESCRIPTION="disallowing"
    ACTION_DESCRIPTION_CAP="Disallowing"
fi

print_status "$ACTION_DESCRIPTION_CAP version $VERSION for game instance $GAME_INSTANCE_ID..."

# Call the appropriate function
TRANSACTION_OUTPUT=$(sui client ptb \
    --move-call "$COIN_FLIP_PACKAGE_ID::game::$FUNCTION_NAME" @$GAME_INSTANCE_ID @$COIN_FLIP_CAP $VERSION \
    --json)

# Check if transaction was successful
if echo "$TRANSACTION_OUTPUT" | jq -e '.effects.status.status == "success"' > /dev/null; then
    print_success "Version $VERSION ${ACTION}ed successfully for game instance $GAME_INSTANCE_ID!"
else
    print_error "Failed to $ACTION version $VERSION for game instance $GAME_INSTANCE_ID"
    echo "$TRANSACTION_OUTPUT" | jq '.effects.status'
    exit 1
fi

# Print summary
echo ""
print_success "Coin Flip game version management completed successfully!"
echo ""
print_status "Summary:"
echo "  Game Instance ID: $GAME_INSTANCE_ID"
echo "  Action: $ACTION"
echo "  Version: $VERSION"
echo "  Coin Flip Package ID: $COIN_FLIP_PACKAGE_ID"
echo ""

