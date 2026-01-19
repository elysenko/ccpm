#!/bin/bash
# ensure-github-repo.sh - Ensure GitHub repository exists for project
#
# Usage:
#   ./ensure-github-repo.sh [repo-name]
#
# If repo-name is not provided, uses current directory name.
# Creates repo if it doesn't exist, sets up remote origin.

set -e

REPO_NAME="${1:-$(basename "$(pwd)")}"

# Show help
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
  cat << 'EOF'
Ensure GitHub Repository Exists

Usage:
  ./ensure-github-repo.sh [repo-name]

Arguments:
  repo-name   Name for the repository (default: current directory name)

Behavior:
  1. Checks if repo exists in your GitHub account
  2. Creates repo if it doesn't exist
  3. Sets up remote origin if not configured
  4. Initializes git if needed

Examples:
  ./ensure-github-repo.sh
  ./ensure-github-repo.sh my-project

Requires: gh CLI authenticated (gh auth login)
EOF
  exit 0
fi

# Check if gh is available
if ! command -v gh &> /dev/null; then
  echo "❌ GitHub CLI (gh) not found"
  echo ""
  echo "Install: https://cli.github.com/"
  exit 1
fi

# Check gh authentication
if ! gh auth status &> /dev/null; then
  echo "❌ GitHub CLI not authenticated"
  echo ""
  echo "Run: gh auth login"
  exit 1
fi

# Get current GitHub username
GH_USER=$(gh api user --jq '.login' 2>/dev/null)
if [[ -z "$GH_USER" ]]; then
  echo "❌ Could not determine GitHub username"
  exit 1
fi

FULL_REPO="$GH_USER/$REPO_NAME"

echo "=== Ensure GitHub Repository ==="
echo ""
echo "Repository: $FULL_REPO"
echo ""

# Check if repo already exists
if gh repo view "$FULL_REPO" &> /dev/null; then
  echo "✓ Repository exists: https://github.com/$FULL_REPO"

  # Check if we have a remote origin set
  current_origin=$(git remote get-url origin 2>/dev/null || echo "")

  if [[ -z "$current_origin" ]]; then
    echo ""
    echo "Setting up remote origin..."
    git remote add origin "https://github.com/$FULL_REPO.git"
    echo "✓ Remote origin added"
  elif [[ "$current_origin" != *"$FULL_REPO"* ]]; then
    echo ""
    echo "⚠️  Current origin: $current_origin"
    echo "   Expected: https://github.com/$FULL_REPO.git"
    echo ""
    read -p "Update origin to $FULL_REPO? (y/n): " update_origin
    if [[ "$update_origin" == "y" ]]; then
      git remote set-url origin "https://github.com/$FULL_REPO.git"
      echo "✓ Remote origin updated"
    fi
  else
    echo "✓ Remote origin already configured"
  fi
else
  echo "Repository does not exist. Creating..."
  echo ""

  # Initialize git if needed
  if [[ ! -d ".git" ]]; then
    echo "Initializing git repository..."
    git init
    echo ""
  fi

  # Create the repository
  # --private by default, --public if user prefers
  read -p "Create as private repository? (y/n): " is_private

  if [[ "$is_private" == "y" ]]; then
    gh repo create "$REPO_NAME" --private --source=. --remote=origin
  else
    gh repo create "$REPO_NAME" --public --source=. --remote=origin
  fi

  echo ""
  echo "✅ Repository created: https://github.com/$FULL_REPO"
fi

echo ""

# Check if we have any commits
if git rev-parse HEAD &> /dev/null; then
  # Check if we need to push
  if git remote get-url origin &> /dev/null; then
    # Check if remote has any commits
    if ! git ls-remote --heads origin main &> /dev/null && ! git ls-remote --heads origin master &> /dev/null; then
      echo "Remote is empty. Push initial commit?"
      read -p "(y/n): " do_push
      if [[ "$do_push" == "y" ]]; then
        # Determine default branch name
        default_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")
        git push -u origin "$default_branch"
        echo "✓ Pushed to origin/$default_branch"
      fi
    else
      echo "✓ Remote has commits"
    fi
  fi
else
  echo "No commits yet. Create initial commit after adding files."
fi

echo ""
echo "Repository ready: https://github.com/$FULL_REPO"
