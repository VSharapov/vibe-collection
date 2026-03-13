#!/usr/bin/env python3
"""
Erasure coding parity and hot spare calculator - CLI.
"""

import argparse
from erasure_lib import calculate, estimate_rebuild_hours, parity_portion, hot_spares


def main():
    parser = argparse.ArgumentParser(
        description="Erasure coding parity & hot spare calculator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --disks 16 --size-gb 24000    # 16x 24TB drives
  %(prog)s -n 8 -s 4000                  # 8x 4TB drives
  %(prog)s -n 3 -s 16                    # Toy example
        """
    )
    parser.add_argument("-n", "--disks", type=int, required=True,
                        help="Number of disks")
    parser.add_argument("-s", "--size-gb", type=int, required=True,
                        help="Size per disk in GB")
    parser.add_argument("-v", "--verbose", action="store_true",
                        help="Show detailed output")
    
    args = parser.parse_args()
    
    config = calculate(args.disks, args.size_gb)
    
    if args.verbose:
        rebuild_hrs = estimate_rebuild_hours(args.size_gb)
        print(f"Configuration for {args.disks}x {args.size_gb}GB drives:")
        print(f"  Data disks:      {config.data_disks}")
        print(f"  Parity disks:    {config.parity}")
        print(f"  Hot spares:      {config.hot_spares}")
        print(f"  Scheme:          {config.data_disks}+{config.parity}" + 
              (f"+{config.hot_spares}hs" if config.hot_spares else ""))
        print(f"  Storage eff:     {config.storage_efficiency:.1%}")
        print(f"  Raw capacity:    {config.raw_capacity_gb/1000:.1f} TB")
        print(f"  Usable capacity: {config.usable_capacity_gb/1000:.1f} TB")
        print(f"  Est. rebuild:    {rebuild_hrs:.1f} hours")
    else:
        print(f"data={config.data_disks} parity={config.parity} hot_spares={config.hot_spares}")


if __name__ == "__main__":
    main()
