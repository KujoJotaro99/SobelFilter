#!/usr/bin/env bash
set -euo pipefail

seeds="${*:-"1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20"}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

best_seed=""
best_mhz=0

for s in $seeds; do
  if ! make -C "${script_dir}" --no-print-directory clean >/dev/null; then
    echo "seed ${s}: clean failed"
    continue
  fi
  if ! make -C "${script_dir}" --no-print-directory place SEED="$s" > "${script_dir}/out_seed${s}.txt" 2>&1; then
    echo "seed ${s}: failed"
    continue
  fi

  mhz="$(awk '/Max frequency for clock '\''core_clk_\$glb_clk'\''/{v=$7} END{print v}' "${script_dir}/out_seed${s}.txt")"
  if [[ -z "${mhz}" ]]; then
    echo "seed ${s}: no Fmax found (check out_seed${s}.txt)"
    tail -n 4 "${script_dir}/out_seed${s}.txt" | sed 's/^/  /'
    continue
  fi

  echo "seed ${s}: ${mhz} MHz"

  if awk "BEGIN{exit !(${mhz} > ${best_mhz})}"; then
    best_mhz="${mhz}"
    best_seed="${s}"
  fi
done

if [[ -n "${best_seed}" ]]; then
  echo ""
  echo "Best seed: ${best_seed} (${best_mhz} MHz)"
fi
