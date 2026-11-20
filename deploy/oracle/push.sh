#!/usr/bin/env bash
# Copy ApplyPilot from this PC to the Oracle VM (run from the repo root in Git Bash).
#   bash deploy/oracle/push.sh ubuntu@<vm-ip>            code only (safe to repeat for updates)
#   bash deploy/oracle/push.sh ubuntu@<vm-ip> --with-data  also your database, settings, facts, resume and photo (once)
set -euo pipefail
HOST="${1:?usage: push.sh user@host [--with-data]}"
KEY="${SSH_KEY:-$HOME/.ssh/applypilot_oracle}"
SSH="ssh -i $KEY -o StrictHostKeyChecking=accept-new"
$SSH "$HOST" "sudo mkdir -p /opt/applypilot && sudo chown \$USER:\$USER /opt/applypilot"
tar czf - --exclude=.git --exclude=app --exclude=node_modules --exclude='*/__pycache__' --exclude='*.pyc' \
    --exclude=output --exclude=.cockpit-dev --exclude=.claude --exclude=.agents --exclude='*.db' --exclude='*.db-*' \
    --exclude=backend/.env --exclude='backend/data/candidate_facts.json' --exclude='backend/data/*.local.json' \
    --exclude=stitch_applypilot_ios_design_system --exclude=backups . | $SSH "$HOST" "tar xzf - -C /opt/applypilot"
if [ "${2:-}" = "--with-data" ]; then
  FILES=""
  for f in applypilot.db backend/.env backend/data/candidate_facts.json output/resumes output/profile; do [ -e "$f" ] && FILES="$FILES $f"; done
  tar czf - $FILES | $SSH "$HOST" "tar xzf - -C /opt/applypilot && chmod 600 /opt/applypilot/backend/.env /opt/applypilot/applypilot.db 2>/dev/null || true"
  echo "Data copied:$FILES"
fi
echo "Pushed to $HOST:/opt/applypilot"
