#!/usr/bin/env bash
# CPS 5981 · Unit 07 · synthetic user probe
# Hits four endpoints once per second and writes one CSV row per request.
# Usage:  ./probe.sh <seconds> > results/probe-E1.csv
set -u
BASE="${BASE:-http://127.0.0.1:8080}"
DUR="${1:-120}"
EPS="/edge-health / /api/Products /rest/admin/application-configuration"

probe_one() {
  local ts="$1" ep="$2" raw code secs served
  raw=$(curl -s -o /dev/null -D - --max-time 20 \
        -w 'META %{http_code} %{time_total}\n' "$BASE$ep" 2>/dev/null)
  read -r _ code secs <<<"$(grep '^META' <<<"$raw")"
  # after a retry nginx lists every address tried; the last one served the request
  served=$(grep -i '^x-served-by:' <<<"$raw" | awk '{print $NF}' | tr -d '\r,')
  echo "$ts,$ep,${code:-000},${secs:-20},${served:--}"
}

echo "ts,endpoint,status,seconds,served_by"
end=$((SECONDS + DUR))
while [ "$SECONDS" -lt "$end" ]; do
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  for ep in $EPS; do probe_one "$ts" "$ep" & done
  sleep 1
done
wait
