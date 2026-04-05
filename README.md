# OpenShift Profile Benchmarks

This repository contains two profiling utilities:

- `profile_ib.sh`: runs InfiniBand bandwidth and latency measurements.
- `profile_pcie.cu`: measures PCIe transfer latency and derived bandwidth for host-to-device and device-to-host copies.

## Files

- `profile_ib.sh`
- `profile_pcie.cu`

## InfiniBand Profiling

`profile_ib.sh` runs four perftest binaries and saves each run to `ib_logs/`:

- `ib_write_bw`
- `ib_read_bw`
- `ib_write_lat`
- `ib_read_lat`

### Prerequisites

- `ib_write_bw`, `ib_read_bw`, `ib_write_lat`, and `ib_read_lat` must be installed and available in `PATH`, or supplied through `--perftest-dir`.
- The selected Mellanox device must exist on both machines.
- Replace `<master_ip_addr>` with the server node's reachable IP address.

### Run

On the server:

```bash
chmod +x profile_ib.sh
./profile_ib.sh --rank 0 --master-ip <master_ip_addr> --mlx-device mlx5_6
```

On the client:

```bash
chmod +x profile_ib.sh
./profile_ib.sh --rank 1 --master-ip <master_ip_addr> --mlx-device mlx5_6
```

If the perftest binaries are not in `PATH`, point the script at their directory:

```bash
./profile_ib.sh --rank 0 --master-ip <master_ip_addr> --mlx-device mlx5_6 --perftest-dir /path/to/perftest/bin
```

### IB Logs

The script creates `ib_logs/` in this repository and writes one timestamped log per measurement.

Expected filenames:

- `ib_logs/ib_write_bw_server_<YYYYMMDD_HHMMSS>.log`
- `ib_logs/ib_read_bw_server_<YYYYMMDD_HHMMSS>.log`
- `ib_logs/ib_write_lat_server_<YYYYMMDD_HHMMSS>.log`
- `ib_logs/ib_read_lat_server_<YYYYMMDD_HHMMSS>.log`
- `ib_logs/ib_write_bw_client_rank1_<YYYYMMDD_HHMMSS>.log`
- `ib_logs/ib_read_bw_client_rank1_<YYYYMMDD_HHMMSS>.log`
- `ib_logs/ib_write_lat_client_rank1_<YYYYMMDD_HHMMSS>.log`
- `ib_logs/ib_read_lat_client_rank1_<YYYYMMDD_HHMMSS>.log`

These files contain the raw `perftest` output, including the exact command used, the selected mlx device, bandwidth summaries for the `*_bw` runs, and latency summaries for the `*_lat` runs.

## PCIe Profiling

Compile the CUDA benchmark with:

```bash
nvcc -O3 -o profile_pcie profile_pcie.cu
```

Run it with:

```bash
./profile_pcie
```

You can optionally choose a different CSV path:

```bash
./profile_pcie --output pcie_logs/custom_profile.csv
```

### PCIe Output

`profile_pcie` prints CSV to standard output and also writes the same data to:

- `pcie_logs/profile_pcie.csv`

The CSV header is:

```text
direction,size_bytes,avg_latency_us,min_latency_us,max_latency_us,bandwidth_GBps
```

Each row reports both latency and bandwidth for one transfer direction and size:

- `direction`: `H2D` for host-to-device or `D2H` for device-to-host
- `size_bytes`: transfer size in bytes
- `avg_latency_us`: average latency in microseconds
- `min_latency_us`: minimum observed latency in microseconds
- `max_latency_us`: maximum observed latency in microseconds
- `bandwidth_GBps`: effective bandwidth in GB/s computed from the average latency

## Output Summary

Running the tools in this repository produces:

- `ib_logs/*.log`: raw InfiniBand bandwidth and latency logs
- `pcie_logs/profile_pcie.csv`: PCIe latency and bandwidth sweep in CSV format
