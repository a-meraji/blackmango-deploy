#!/usr/bin/env bash
set -euo pipefail

# Pulls the THREE separate git repos that make up this project. There is intentionally NO
# single "all-in-one" repo — backend, frontend and deploy are independent repositories that
# happen to live side by side under APP_ROOT:
#
#   $APP_ROOT/backend    (git@github.com:amirhoseinqd/blackmango-backend.git)
#   $APP_ROOT/frontend   (git@github.com:a-meraji/bigblackmango.git)
#   $APP_ROOT/deploy     (git@github.com:a-meraji/blackmango-deploy.git)  ← this script lives here
#
# Run it from anywhere; it resolves the sibling repos relative to its own location.
#
#   ./deploy/scripts/pull_all.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="${APP_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"

pull_repo() {
  local name="$1"
  local dir="${APP_ROOT}/${name}"
  if [[ ! -d "${dir}/.git" ]]; then
    echo "WARN: ${dir} is not a git repo — skipping (clone it first)."
    return 0
  fi
  printf '\n==> git pull %s\n' "${name}"
  git -C "${dir}" pull --ff-only
}

# Pull backend + frontend first; pull deploy LAST so a change to these scripts only takes
# effect on the next run (never mid-execution of this very file).
pull_repo backend
pull_repo frontend
pull_repo deploy

echo
echo "All three repos up to date under ${APP_ROOT}."
