# 16 GB ZRAM Fast In-Memory Swap Configuration

Configures high-speed in-memory swap using the kernel's `zram` module and `zstd` compression algorithm.

## Features:
1. **Zero Flash Wear:** No writing or swapping to internal UFS storage.
2. **16 GB Virtual Capacity:** Allows running heavy workloads without OOM kills.
3. **Latency Optimization:** `vm.page-cluster = 0` eliminates multi-page readahead latency overhead.
