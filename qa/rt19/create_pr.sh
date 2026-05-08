#!/bin/bash
set -e

# ============================================================
#  create_pr.sh — Create PR from current feature branch → dev
#  Usage: ./create_pr.sh ["PR Title"] ["PR Body"]
# ============================================================

# Ensure gh is installed
if ! command -v gh &> /dev/null; then
    echo "GitHub CLI (gh) could not be found. Please install it with 'brew install gh'."
    exit 1
fi

CURRENT_BRANCH=$(git branch --show-current)

# If on dev, create a timestamped branch from dev (legacy behavior)
if [ "$CURRENT_BRANCH" = "dev" ]; then
    TIMESTAMP=$(date +"%m%d%y_%H%M")
    NEW_BRANCH="fix/PR_${TIMESTAMP}"
    echo "On dev — creating timestamped branch: $NEW_BRANCH"
    git checkout -b "$NEW_BRANCH"
    git push origin "$NEW_BRANCH"
    CURRENT_BRANCH="$NEW_BRANCH"
fi

# Don't allow PR from main
if [ "$CURRENT_BRANCH" = "main" ]; then
    echo "Error: Cannot create PR from 'main'. Switch to a feature branch first."
    exit 1
fi

# Push the current branch
echo "Pushing $CURRENT_BRANCH to origin..."
git push origin "$CURRENT_BRANCH" 2>/dev/null || git push --set-upstream origin "$CURRENT_BRANCH"

# Create PR to dev
TIMESTAMP=$(date +"%m%d%y_%H%M")
TITLE=${1:-"Merge $CURRENT_BRANCH → dev ($TIMESTAMP)"}
BODY=${2:-"## Summary
PR from \`$CURRENT_BRANCH\` into \`dev\` as of $TIMESTAMP.

## Checklist
- [ ] QA tests pass
- [ ] No hardcoded secrets/URLs
- [ ] Code reviewed"}

echo ""
echo "Creating PR: $CURRENT_BRANCH → dev"
gh pr create --base dev --head "$CURRENT_BRANCH" --title "$TITLE" --body "$BODY" --assignee "@me"

# Switch back to dev
echo ""
echo "Switching back to dev..."
git checkout dev
echo "✅ PR created. Merge it on GitHub, then 'git pull origin dev' to get the changes."
