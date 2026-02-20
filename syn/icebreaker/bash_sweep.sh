#!/usr/bin/env bash
set -euo pipefail

best_seed=""
best_mhz=0

for s in $(seq 1 20); do
  echo "seed ${s}: running..."
  rm -rf build
  if make clean >/dev/null 2>&1; then :; fi
  if make place SEED="$s" > "out_seed${s}.txt" 2>&1; then
    mhz=$(awk '/Max frequency for clock '\''core_clk_\$glb_clk'\''/{v=$7} END{print v}' "out_seed${s}.txt")
    echo "seed ${s}: ${mhz} MHz"
    if [[ -n "$mhz" ]]; then
      mhz_i=${mhz%.*}
      if (( mhz_i > best_mhz )); then
        best_mhz=$mhz_i
        best_seed=$s
      fi
    fi
  else
    echo "seed ${s}: place failed (see out_seed${s}.txt)"
  fi
done

if [[ -n "$best_seed" ]]; then
  echo "Best seed: $best_seed (${best_mhz} MHz)"
fi
