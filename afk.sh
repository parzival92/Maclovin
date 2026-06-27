#!/usr/bin/env bash
#
# afk.sh — "Away From Keyboard" issue runner.
#
# For each selected open GitHub issue, this script:
#   1. cuts a fresh branch off the base branch (default: main),
#   2. has Claude Code implement the issue headlessly,
#   3. verifies the build,
#   4. commits + pushes, and opens a PR whose body says "Closes #<n>",
#   5. links the PR back to the issue (comment + `has-pr` label).
#
# You review and approve the PR. When you MERGE it, GitHub auto-closes the
# issue (via "Closes #<n>"). Approval alone does not close an issue — merging
# does — so this script wires the close to the merge.
#
# Usage:
#   ./afk.sh 3 4 5           # process specific issue numbers
#   ./afk.sh                 # process all open issues labeled "$AFK_LABEL"
#   AFK_DRY_RUN=1 ./afk.sh   # show what would happen, change nothing
#
# Config (env vars):
#   AFK_BASE      base branch to branch from / target with PRs   (default: main)
#   AFK_LABEL     label used to select issues when none passed    (default: afk)
#   AFK_MODEL     model for the Claude runner (e.g. opus, sonnet) (default: CLI default)
#   AFK_DRY_RUN   if set to 1, plan only; no branches/PRs/edits   (default: unset)
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

BASE="${AFK_BASE:-main}"
LABEL="${AFK_LABEL:-afk}"
MODEL="${AFK_MODEL:-}"
DRY_RUN="${AFK_DRY_RUN:-}"
LINK_LABEL="has-pr"
LOG_DIR="${TMPDIR:-/tmp}/afk-logs"

c_blue=$'\033[34m'; c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_red=$'\033[31m'; c_reset=$'\033[0m'
log()  { printf '%s[afk]%s %s\n' "$c_blue" "$c_reset" "$*"; }
ok()   { printf '%s[afk]%s %s\n' "$c_green" "$c_reset" "$*"; }
warn() { printf '%s[afk]%s %s\n' "$c_yellow" "$c_reset" "$*" >&2; }
die()  { printf '%s[afk]%s %s\n' "$c_red" "$c_reset" "$*" >&2; exit 1; }

# ---- preflight ---------------------------------------------------------------

command -v claude >/dev/null || die "claude CLI not found on PATH"
command -v gh >/dev/null     || die "gh CLI not found on PATH"
command -v jq >/dev/null     || die "jq not found on PATH"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated (run: gh auth login)"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"

if [[ -z "$DRY_RUN" && -n "$(git status --porcelain)" ]]; then
  die "working tree is dirty; commit or stash changes before running afk.sh"
fi

mkdir -p "$LOG_DIR"

# Ensure the link label exists (idempotent).
if [[ -z "$DRY_RUN" ]]; then
  gh label create "$LINK_LABEL" --color BFD4F2 --description "Has an open AFK pull request" >/dev/null 2>&1 || true
fi

# ---- select issues -----------------------------------------------------------

if [[ $# -gt 0 ]]; then
  ISSUES=("$@")
else
  log "no issue numbers given; selecting open issues labeled '$LABEL'"
  mapfile -t ISSUES < <(gh issue list --state open --label "$LABEL" --json number --jq '.[].number')
fi

if [[ ${#ISSUES[@]} -eq 0 ]]; then
  die "no issues to process (pass numbers, or label issues with '$LABEL')"
fi

log "base branch: $BASE | issues: ${ISSUES[*]}${MODEL:+ | model: $MODEL}${DRY_RUN:+ | DRY RUN}"

# Refresh base once up front.
if [[ -z "$DRY_RUN" ]]; then
  git checkout -q "$BASE"
  git pull -q --ff-only origin "$BASE" || warn "could not fast-forward $BASE from origin (continuing with local)"
fi

slugify() { echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' | cut -c1-40; }

# ---- per-issue worker --------------------------------------------------------

process_issue() {
  local n="$1"
  local meta title body state labels branch log
  meta="$(gh issue view "$n" --json number,title,body,state,labels 2>/dev/null)" \
    || { warn "#$n: could not fetch issue; skipping"; return 1; }

  state="$(jq -r '.state' <<<"$meta")"
  title="$(jq -r '.title' <<<"$meta")"
  body="$(jq -r '.body // ""' <<<"$meta")"
  labels="$(jq -r '[.labels[].name] | join(",")' <<<"$meta")"

  if [[ "$state" != "OPEN" ]]; then warn "#$n is $state; skipping"; return 0; fi
  if [[ ",$labels," == *",$LINK_LABEL,"* ]]; then
    warn "#$n already has '$LINK_LABEL' (PR exists); skipping"
    return 0
  fi

  branch="afk/${n}-$(slugify "$title")"
  log="$LOG_DIR/issue-${n}.log"
  log "#$n: $title"
  log "#$n: branch $branch | log $log"

  if [[ -n "$DRY_RUN" ]]; then
    ok "#$n: [dry-run] would branch, run Claude, build, push, and open a PR"
    return 0
  fi

  # Fresh branch off base.
  git checkout -q "$BASE"
  git branch -D "$branch" >/dev/null 2>&1 || true
  git checkout -q -b "$branch"

  # Headless Claude run. The script owns all git/gh operations, so Claude is
  # told to only modify the working tree.
  local prompt
  prompt=$(cat <<EOF
You are implementing a single GitHub issue in this repository, end-to-end and autonomously.

Issue #${n}: ${title}

${body}

Instructions:
- Implement the change fully and correctly. Match the existing architecture: reusable logic in the MaclovinCore target, CLI wiring in MaclovinCLI.
- Add or update tests under Tests/ where it makes sense.
- Run \`swift build\` and resolve any compile errors before you finish.
- If this is a documentation/decision issue, update the relevant files (PRD.md, docs/decisions.md, README.md).
- Keep the change scoped strictly to this issue. Do not touch unrelated files.
- Do NOT run git commit, git push, or create a pull request. Leave your changes in the working tree only — the surrounding script handles all git and GitHub operations.
EOF
)

  log "#$n: running Claude..."
  if ! claude -p "$prompt" \
        --dangerously-skip-permissions \
        --add-dir "$REPO_DIR" \
        ${MODEL:+--model "$MODEL"} \
        >"$log" 2>&1; then
    warn "#$n: Claude exited non-zero (see $log)"
  fi

  if [[ -z "$(git status --porcelain)" ]]; then
    warn "#$n: no changes were produced; abandoning branch"
    git checkout -q "$BASE"
    git branch -D "$branch" >/dev/null 2>&1 || true
    gh issue comment "$n" --body "AFK runner produced no changes for this issue. Needs a human look." >/dev/null || true
    return 0
  fi

  # Build gate: a green build opens a normal PR; a red build opens a draft.
  local draft="" build_note="Build: \`swift build\` passed."
  if ! swift build >>"$log" 2>&1; then
    draft="--draft"
    build_note="⚠️ Build: \`swift build\` FAILED — opening as draft. See run log."
    warn "#$n: build failed; PR will be a draft"
  fi

  git add -A
  git commit -q -m "AFK: implement #${n} ${title}

Implemented headlessly by the AFK runner for issue #${n}.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  git push -q -u origin "$branch"

  local pr_url
  pr_url="$(gh pr create \
    --base "$BASE" \
    --head "$branch" \
    --title "AFK: ${title} (#${n})" \
    ${draft} \
    --body "$(cat <<EOF
Implemented headlessly by \`afk.sh\` for issue #${n}.

${build_note}

Review and approve; merging this PR closes the issue.

Closes #${n}

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)")"

  gh issue edit "$n" --add-label "$LINK_LABEL" >/dev/null 2>&1 || true
  gh issue comment "$n" --body "AFK runner opened a PR: ${pr_url}

Approve and merge it to close this issue." >/dev/null || true

  git checkout -q "$BASE"
  ok "#$n: PR ready → $pr_url"
}

# ---- run ---------------------------------------------------------------------

failed=()
for n in "${ISSUES[@]}"; do
  if ! process_issue "$n"; then
    failed+=("$n")
  fi
  echo
done

if [[ ${#failed[@]} -gt 0 ]]; then
  warn "issues that errored: ${failed[*]}"
fi
ok "done. Review the open PRs; merging each closes its issue."
