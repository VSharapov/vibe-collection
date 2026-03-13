# erasure-calc

Rule of thumb calculator for erasure coding parity disks and hot spares.

## Why?

Large disks take forever to rebuild. During rebuild, the array is vulnerable. Industry practice is to use more parity for larger disks (e.g., 10+4 for 20TB+ drives vs RAID6 for 4-8TB).

## Formulas

```
parity(n,s)     = max(1, round(log₂(s)/4 + log₂(n)/2 - 2))
hot_spares(n,s) = max(0, round((log₂(s/4000) + log₂(n/8)) / 2))
```

## CLI

```bash
./erasure.py -n 16 -s 24000
# data=10 parity=4 hot_spares=2

./erasure.py -n 16 -s 24000 -v
# Configuration for 16x 24000GB drives:
#   Data disks:      10
#   Parity disks:    4
#   Hot spares:      2
#   Scheme:          10+4+2hs
#   Storage eff:     62.5%
#   ...
```

## Web UI

```bash
python3 -m http.server 8000
# open http://localhost:8000
```

Heatmap shows RGB where R=data%, G=parity%, B=hot spares%.
