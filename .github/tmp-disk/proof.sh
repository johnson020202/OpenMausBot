#!/usr/bin/env bash
# One platform: main's unfixed test and the fixed one, on a normal disk and one filled below the 15% reserve.
set +e
mkdir -p proof
TMP_DISK=$(node -p 'require("node:os").tmpdir()')
freek() { df -k "$TMP_DISK" | tail -1 | awk '{print $4}'; }
totalk() { df -k "$TMP_DISK" | tail -1 | awk '{print $2}'; }
disk() { df -k "$TMP_DISK" | tail -1 | awk -v w="$1" '{printf "%s: disk total %.0f GB free %.0f GB (%.0f%%), reserve-15%% %.1f GB\n",w,$2/1048576,$4/1048576,$4*100/$2,$2*0.15/1048576}' | tee -a proof/summary.txt; }
one() { name=$1; shift
  if timeout 240 pnpm exec vitest run "$@" > "proof/$name.log" 2>&1; then echo "$name pass ($(sed -E 's/\x1b\[[0-9;]*m//g' "proof/$name.log" | grep -m1 -E 'Tests +' | sed -E 's/ +/ /g'))" | tee -a proof/summary.txt
  else echo "$name FAIL: $(sed -E 's/\x1b\[[0-9;]*m//g' "proof/$name.log" | grep -m1 -E 'AssertionError|Error:' | cut -c1-110)" | tee -a proof/summary.txt; fi
}
FILL="$TMP_DISK/fill-the-disk"
fill() {
  want=$(( $(freek) - $(totalk) * 10 / 100 ))
  if [ "$want" -le 0 ]; then echo "already below 10% free, no fill" | tee -a proof/summary.txt; return; fi
  if command -v fallocate > /dev/null; then fallocate -l "${want}K" "$FILL"
  else fsutil file createnew "$(cygpath -w "$FILL")" $(( want * 1024 )) > /dev/null; fi
}
cp server/cloud-sync.e2e.test.ts proof-fixed.ts
cp server/testing/roomy-disk.mjs proof-roomy.mjs
disk "as the runner came"
cp .github/tmp-disk/cloud-sync.unfixed.txt server/cloud-sync.e2e.test.ts
one as-it-came-unfixed server/cloud-sync.e2e.test.ts
fill
disk "after filling"
one low-unfixed server/cloud-sync.e2e.test.ts
cp proof-fixed.ts server/cloud-sync.e2e.test.ts
one low-fixed-1 server/cloud-sync.e2e.test.ts
one low-fixed-2 server/cloud-sync.e2e.test.ts
one low-fixed-3 server/cloud-sync.e2e.test.ts
if [ "$RUNNER_OS" = "Linux" ]; then one low-lent-folders-fixed server/lent-folders.e2e.test.ts; fi
sed -i '/^syncBuiltinESMExports();$/d' server/testing/roomy-disk.mjs
one low-mutation-prelude-does-nothing server/cloud-sync.e2e.test.ts
cp proof-roomy.mjs server/testing/roomy-disk.mjs
rm -f "$FILL"
disk "after emptying"
one normal-fixed server/cloud-sync.e2e.test.ts
cat proof/summary.txt
