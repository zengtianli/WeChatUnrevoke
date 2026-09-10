#!/bin/bash
# Update the existing static product site after its first provisioning.
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR"
source "${DEPLOY_LIB:-$HOME/Dev/tools/dev/lib/deploy}/core.sh"
vps_load
python3 scripts/build-site.py
# Stage complete content, then switch the current directory; retain one rollback.
rsync -az --delete "$DIR/dist/site/" "$VPS:/var/www/unrevoke-next/"
ssh "$VPS" 'test -s /var/www/unrevoke-next/index.html && test -s /var/www/unrevoke-next/media/tutorial.mp4 && if [ -d /var/www/unrevoke ]; then rm -rf /var/www/unrevoke-previous; mv /var/www/unrevoke /var/www/unrevoke-previous; fi; mv /var/www/unrevoke-next /var/www/unrevoke'
http_verify_edge "unrevoke.tianli.cyou" / --expect 200
python3 scripts/verify-site.py
