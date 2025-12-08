#!/bin/bash

# Claim Fees from Coin Flip Game House
# This script calls admin_claim_fees and transfers the coin to the sender

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

# Check if we're in the right directory
if [ ! -f "package/Move.toml" ]; then
    print_error "This script must be run from the coin-flip-contracts root directory"
    exit 1
fi

# Check if sui client is available
if ! command -v sui &> /dev/null; then
    print_error "sui client is not available. Please ensure Sui is installed and in your PATH."
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    print_error "jq is required but not installed. Please install jq first."
    exit 1
fi

# Get active environment
ACTIVE_ENV=$(get_active_env)
print_status "Active environment: $ACTIVE_ENV"

# Load coin flip environment variables
if [ -f "outputs/$ACTIVE_ENV/latest_coin_flip.env" ]; then
    source "outputs/$ACTIVE_ENV/latest_coin_flip.env"
    print_success "Loaded coin flip package environment variables"
else
    print_error "Coin flip package not deployed. Run ./scripts/deploy-package.sh first."
    exit 1
fi

# Check if package variables are loaded
if [ -z "$CURRENT_COIN_FLIP_PACKAGE_ID" ] || [ -z "$COIN_FLIP_CAP" ]; then
    print_error "Required package variables not loaded. Ensure coin flip package is deployed."
    exit 1
fi

# Set package variables for convenience
COIN_FLIP_PACKAGE_ID="$CURRENT_COIN_FLIP_PACKAGE_ID"

# Handle command line arguments
if [ $# -lt 1 ]; then
    print_error "Usage: $0 <house_id> [game_id]"
    print_status "Example: $0 0x123...abc"
    print_status "         $0 0x123...abc 0x456...def"
    print_status ""
    print_status "If game_id is not provided, the script will try to load it from the latest game env file."
    exit 1
fi

HOUSE_ID="$1"
GAME_ID="$2"

# If game_id not provided, try to load from latest game env file
if [ -z "$GAME_ID" ]; then
    # Try to find the latest game env file
    if [ -f "outputs/$ACTIVE_ENV/latest_coin_flip_game.env" ]; then
        source "outputs/$ACTIVE_ENV/latest_coin_flip_game.env"
        if [ -n "$COIN_FLIP_GAME_ID" ]; then
            GAME_ID="$COIN_FLIP_GAME_ID"
            print_status "Loaded game ID from latest game env file: $GAME_ID"
        fi
    fi
    
    # If still not found, try to find any game env file
    if [ -z "$GAME_ID" ]; then
        LATEST_GAME_ENV=$(ls -t outputs/$ACTIVE_ENV/coin_flip_game_*.env 2>/dev/null | head -1)
        if [ -n "$LATEST_GAME_ENV" ]; then
            source "$LATEST_GAME_ENV"
            if [ -n "$COIN_FLIP_GAME_ID" ]; then
                GAME_ID="$COIN_FLIP_GAME_ID"
                print_status "Loaded game ID from $LATEST_GAME_ENV: $GAME_ID"
            fi
        fi
    fi
    
    if [ -z "$GAME_ID" ]; then
        print_error "Game ID not provided and could not be loaded from env files."
        print_error "Please provide game_id as the second argument or ensure a game env file exists."
        exit 1
    fi
fi

print_status "Claiming fees from house..."
print_status "  House ID: $HOUSE_ID"
print_status "  Game ID: $GAME_ID"
print_status "  Package ID: $COIN_FLIP_PACKAGE_ID"

# Call admin_claim_fees and transfer the coin to sender
print_status "Executing claim fees transaction..."
CLAIM_OUTPUT=$(sui client ptb \
    --move-call sui::tx_context::sender \
    --assign sender \
    --move-call $COIN_FLIP_PACKAGE_ID::game::admin_claim_fees @$COIN_FLIP_CAP @$GAME_ID @$HOUSE_ID \
    --assign fees_coin \
    --transfer-objects [fees_coin] sender \
    --json)

# Check if claim was successful
if echo "$CLAIM_OUTPUT" | jq -e '.effects.status.status == "success"' > /dev/null; then
    print_success "Fees claimed successfully!"
else
    print_error "Failed to claim fees!"
    echo "$CLAIM_OUTPUT" | jq '.effects.status'
    exit 1
fi

# Extract the coin object ID that was transferred
# Try to find it in created objects first, then in transferred objects
COIN_ID=$(echo "$CLAIM_OUTPUT" | jq -r '.objectChanges[] | select(.type == "created" and (.objectType | contains("::coin::Coin<0x2::sui::SUI>"))) | .objectId')

# If not found in created, try transferred objects
if [ -z "$COIN_ID" ] || [ "$COIN_ID" = "null" ]; then
    COIN_ID=$(echo "$CLAIM_OUTPUT" | jq -r '.objectChanges[] | select(.type == "transferred" and (.objectType | contains("::coin::Coin<0x2::sui::SUI>"))) | .objectId')
fi

# Extract the amount if available
if [ -n "$COIN_ID" ] && [ "$COIN_ID" != "null" ]; then
    # Try to get coin balance
    COIN_BALANCE=$(sui client object "$COIN_ID" --json 2>/dev/null | jq -r '.data.content.fields.balance // "unknown"' 2>/dev/null || echo "unknown")
    
    print_success "Coin transferred to sender: $COIN_ID"
    if [ "$COIN_BALANCE" != "unknown" ] && [ -n "$COIN_BALANCE" ]; then
        COIN_BALANCE_SUI=$(echo "scale=9; $COIN_BALANCE/1000000000" | bc 2>/dev/null || echo "$COIN_BALANCE")
        print_status "  Balance: $COIN_BALANCE_SUI SUI"
    fi
else
    print_warning "Could not extract coin ID from transaction output"
    print_status "Transaction was successful, but coin details could not be extracted"
fi

# Print summary
echo ""
print_success "Fee claim completed successfully!"
echo ""
print_status "Transaction Summary:"
echo "  House ID: $HOUSE_ID"
echo "  Game ID: $GAME_ID"
if [ -n "$COIN_ID" ] && [ "$COIN_ID" != "null" ]; then
    echo "  Coin ID: $COIN_ID"
fi
echo ""

