#!/usr/bin/env bash
set -euo pipefail

best_seed=""
best_mhz=0

for s in {1..20}; do
  echo "seed ${s}: running..."
  make clean >/dev/null
  if make place SEED=$s > out_seed${s}.txt 2>&1; then
    mhz=$(awk '/Max frequency for clock '"'"'core_clk_\$glb_clk'"'"'/{v=$7} END{print v}' out_seed${s}.txt)
    echo "seed ${s}: ${mhz} MHz"
    if awk -v m="$mhz" -v b="$best_mhz" 'BEGIN{exit !(m>b)}'; then
      best_mhz=$mhz
      best_seed=$s
    fi
  else
    echo "seed ${s}: place failed (see out_seed${s}.txt)"
  fi
done

echo "Best seed: ${best_seed} (${best_mhz} MHz)"
