#!/usr/bin/env bash
# One Linux shard of every test file at low disk, on main's unfixed cloud-sync.e2e so the sweep has a known catch. Each
# failure then runs alone, still at low disk and on a normal one: only "fails low, passes normal" is the disk.
set +e
mkdir -p proof
disk() { df -k /tmp | tail -1 | awk -v w="$1" '{printf "%s: disk total %.0f GB free %.0f GB (%.0f%%), reserve-15%% %.1f GB\n",w,$2/1048576,$4/1048576,$4*100/$2,$2*0.15/1048576}' | tee -a proof/summary.txt; }
alone() { if timeout 300 pnpm exec vitest run "$2" > "proof/$1.log" 2>&1; then echo pass; else echo FAIL; fi; }
cp .github/tmp-disk/cloud-sync.unfixed.txt server/cloud-sync.e2e.test.ts
total=$(df -k /tmp | tail -1 | awk '{print $2}'); free=$(df -k /tmp | tail -1 | awk '{print $4}')
fallocate -l "$(( free - total * 10 / 100 ))K" /tmp/fill-the-disk
disk "filled"
timeout 1800 pnpm exec vitest run --shard="$SHARD/8" --reporter=default --reporter=json --outputFile.json=proof/low.json > proof/low.log 2>&1
echo "shard exit $?" | tee -a proof/summary.txt
sed -E 's/\x1b\[[0-9;]*m//g' proof/low.log | grep -E '^ +(Test Files|Tests) ' | tee -a proof/summary.txt
if [ "$SHARD" = "1" ]; then
  timeout 300 pnpm test:electron > proof/node-low.log 2>&1
  echo "node tests at low disk exit $? $(grep -E '^(# |ℹ )(pass|fail) ' proof/node-low.log | tr '\n' ' ')" | tee -a proof/summary.txt
fi
disk "end of shard"
python3 - > proof/failed.txt <<'PY'
import json, os
d = json.load(open("proof/low.json"))
for r in d["testResults"]:
    if r["status"] == "failed": print(os.path.relpath(r["name"]))
PY
n=0; : > proof/low-alone.txt
while IFS= read -r f; do n=$((n+1)); echo "$f $(alone "alone-low-$n" "$f")" >> proof/low-alone.txt; done < proof/failed.txt
node_low=0
if [ "$SHARD" = "1" ] && ! grep -qE '^(# |ℹ )fail 0' proof/node-low.log; then node_low=1; fi
rm -f /tmp/fill-the-disk
disk "emptied"
n=0
while IFS= read -r line; do n=$((n+1)); f=${line% *}; echo "$line | normal $(alone "alone-normal-$n" "$f")" | tee -a proof/summary.txt; done < proof/low-alone.txt
if [ "$node_low" = "1" ]; then timeout 300 pnpm test:electron > proof/node-normal.log 2>&1; echo "node tests on a normal disk exit $? $(grep -E '^(# |ℹ )(pass|fail) ' proof/node-normal.log | tr '\n' ' ')" | tee -a proof/summary.txt; fi
exit 0
