#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  DEPRECATED — DO NOT USE THIS FILE                                     ║
# ║                                                                        ║
# ║  The canonical Felt Sense seed script lives in the RuntimeAI repo:     ║
# ║    RuntimeAI/Engagements/Feltsense/seed_feltsense_demo.sh              ║
# ║                                                                        ║
# ║  This stub auto-redirects to the canonical version.                    ║
# ║  If you need to modify seeding, edit the RuntimeAI version ONLY.       ║
# ╚══════════════════════════════════════════════════════════════════════════╝

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Auto-detect RuntimeAI companion repo
CANONICAL=""
for candidate in "$PROJECT_ROOT/../runtimeai-productdocs" "$PROJECT_ROOT/../../runtimeai-productdocs"; do
    if [ -f "$candidate/11-engagements/Feltsense/seed_feltsense_demo.sh" ]; then
        CANONICAL="$(cd "$candidate" && pwd)/11-engagements/Feltsense/seed_feltsense_demo.sh"
        break
    fi
done

if [ -n "$CANONICAL" ]; then
    echo "→ Redirecting to canonical seed: $CANONICAL"
    exec bash "$CANONICAL" "$@"
else
    echo "⚠️  Canonical seed not found. Expected at: runtimeai-productdocs/11-engagements/Feltsense/seed_feltsense_demo.sh"
    echo "    Set RUNTIMEAI_DIR or ensure the runtimeai-productdocs repo is a sibling directory."
    exit 1
fi
