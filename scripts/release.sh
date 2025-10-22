# ============================================================================
# scripts/release.sh
# Release script for version bumping and tagging
# ============================================================================

#!/usr/bin/env bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Functions
error() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

info() {
    echo -e "${GREEN}$1${NC}"
}

warn() {
    echo -e "${YELLOW}$1${NC}"
}

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    error "Not in a git repository"
fi

# Check for uncommitted changes
if [[ -n $(git status -s) ]]; then
    error "You have uncommitted changes. Please commit or stash them first."
fi

# Get current version from git tags
CURRENT_VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
CURRENT_VERSION=${CURRENT_VERSION#v}

IFS='.' read -r -a VERSION_PARTS <<< "$CURRENT_VERSION"
MAJOR=${VERSION_PARTS[0]:-0}
MINOR=${VERSION_PARTS[1]:-0}
PATCH=${VERSION_PARTS[2]:-0}

# Determine new version based on argument
BUMP_TYPE=${1:-patch}

case $BUMP_TYPE in
    major)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        ;;
    minor)
        MINOR=$((MINOR + 1))
        PATCH=0
        ;;
    patch)
        PATCH=$((PATCH + 1))
        ;;
    *)
        error "Invalid bump type: $BUMP_TYPE. Use: major, minor, or patch"
        ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"

info "Current version: $CURRENT_VERSION"
info "New version: $NEW_VERSION"

# Confirm
read -p "Create release v$NEW_VERSION? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    warn "Release cancelled"
    exit 0
fi

# Run tests
info "Running tests..."
if ! make test; then
    error "Tests failed. Aborting release."
fi

# Run checks
info "Running checks..."
if ! make check; then
    error "Checks failed. Aborting release."
fi

# Update CHANGELOG
info "Updating CHANGELOG.md..."
TODAY=$(date +%Y-%m-%d)
sed -i.bak "s/## \[Unreleased\]/## [Unreleased]\n\n## [$NEW_VERSION] - $TODAY/" CHANGELOG.md
rm CHANGELOG.md.bak

# Commit changes
git add CHANGELOG.md
git commit -m "chore: release v$NEW_VERSION"

# Create tag
git tag -a "v$NEW_VERSION" -m "Release v$NEW_VERSION"

info "Release v$NEW_VERSION created successfully!"
info "Push changes with: git push && git push --tags"

