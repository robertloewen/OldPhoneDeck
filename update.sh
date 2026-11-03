#!/bin/bash
# Pulls updates (from your fork and the original repo), rebuilds, and restarts the background service.
#   ./update.sh            update from origin + upstream, then rebuild and restart
#   ./update.sh --no-pull  only rebuild and restart (after your own local changes)
set -euo pipefail
cd "$(dirname "$0")"

SERVICE="gui/$(id -u)/com.robertloewen.oldphonedeck"

if [[ "${1:-}" != "--no-pull" ]]; then
    if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
        echo "✗ Uncommitted changes, commit or stash them first (or use --no-pull)." >&2
        exit 1
    fi
    branch=$(git branch --show-current)
    echo "→ Updating $branch"
    git pull --ff-only origin "$branch"
    if git remote get-url upstream >/dev/null 2>&1; then
        git fetch upstream
        new=$(git rev-list --count HEAD..upstream/main)
        if [[ "$new" -gt 0 ]]; then
            echo "→ Merging $new new commit(s) from the original repo"
            if ! git merge --no-edit upstream/main; then
                git merge --abort
                echo "✗ Merge conflict with the original repo, nothing changed. Resolve it manually." >&2
                exit 1
            fi
            git push origin "$branch"
        else
            echo "→ Original repo has nothing new"
        fi
    fi
fi

echo "→ Building"
swift build -c release 2>&1 | grep -E "error|Build complete" || true
[[ ${PIPESTATUS[0]} -eq 0 ]] || { echo "✗ Build failed, service left running on the old version." >&2; exit 1; }

echo "→ Restarting service"
launchctl kickstart -k "$SERVICE"
sleep 2
token=$(cat ~/.oldphonedeck/token)
if curl -fs -o /dev/null "http://localhost:8045/info?k=$token"; then
    echo "✓ OldPhoneDeck is running. Reload the page on the iPhone."
    echo "  If Take note stops sending: toggle oldphonedeck off/on in Device Control and Data Access."
else
    echo "✗ Service is not responding, see ~/Library/Logs/OldPhoneDeck.log" >&2
    exit 1
fi
