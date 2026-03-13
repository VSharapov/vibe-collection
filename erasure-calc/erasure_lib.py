"""
Erasure coding parity and hot spare calculator - library.

Rule of thumb formulas based on:
- Rebuild time scales with disk size (larger = longer vulnerability window)
- Failure probability scales with disk count
- Industry practice: 10+4 for 20TB+ drives, RAID6 for 4-8TB, RAID5 for <2TB
"""

import math
from dataclasses import dataclass


@dataclass
class ErasureConfig:
    num_disks: int
    size_gb: int
    parity: int
    hot_spares: int
    
    @property
    def data_disks(self) -> int:
        return self.num_disks - self.parity - self.hot_spares
    
    @property
    def usable_capacity_gb(self) -> float:
        return self.data_disks * self.size_gb
    
    @property
    def raw_capacity_gb(self) -> float:
        return self.num_disks * self.size_gb
    
    @property
    def storage_efficiency(self) -> float:
        if self.num_disks == 0:
            return 0.0
        return self.data_disks / self.num_disks
    
    @property
    def parity_ratio(self) -> float:
        if self.num_disks == 0:
            return 0.0
        return self.parity / self.num_disks
    
    @property
    def hot_spare_ratio(self) -> float:
        if self.num_disks == 0:
            return 0.0
        return self.hot_spares / self.num_disks


def parity_portion(num_disks: int, size_gb: int) -> int:
    """
    Calculate recommended parity disk count.
    
    Formula: pp = log2(size_gb)/4 + log2(num_disks)/2 - 2
    """
    if num_disks < 2 or size_gb < 1:
        return 0
    
    raw = math.log2(size_gb) / 4 + math.log2(num_disks) / 2 - 2
    parity = max(1, round(raw))
    max_parity = (num_disks - 1) // 2
    return min(parity, max(1, max_parity))


def hot_spares(num_disks: int, size_gb: int) -> int:
    """
    Calculate recommended hot spare count.
    
    Formula: hs = (log2(size_gb/4000) + log2(num_disks/8)) / 2
    """
    if num_disks < 4 or size_gb < 1:
        return 0
    
    size_factor = math.log2(size_gb / 4000) if size_gb > 4000 else 0
    disk_factor = math.log2(num_disks / 8) if num_disks > 8 else 0
    
    raw = (size_factor + disk_factor) / 2
    spares = max(0, round(raw))
    max_spares = num_disks // 5
    return min(spares, max(0, max_spares))


def calculate(num_disks: int, size_gb: int) -> ErasureConfig:
    """Calculate full erasure coding configuration."""
    p = parity_portion(num_disks, size_gb)
    h = hot_spares(num_disks, size_gb)
    
    while p + h >= num_disks and p > 1:
        p -= 1
    while p + h >= num_disks and h > 0:
        h -= 1
    
    return ErasureConfig(
        num_disks=num_disks,
        size_gb=size_gb,
        parity=p,
        hot_spares=h
    )


def estimate_rebuild_hours(size_gb: int, speed_mbps: int = 150) -> float:
    """Estimate rebuild time in hours. Default 150 MB/s sustained."""
    return size_gb / (speed_mbps * 3.6)
