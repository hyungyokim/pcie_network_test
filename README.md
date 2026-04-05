# OpenShift Profile Bandwidth Tests

This directory contains two small benchmarking utilities:

- `measure_ib_bw.sh`: runs InfiniBand write/read bandwidth tests and saves per-run logs.
- `measure_pcie_bw.cu`: measures GPU PCIe host-to-device and device-to-host transfer latency/bandwidth and emits CSV-formatted results.

## Files

- `measure_ib_bw.sh`
- `measure_pcie_bw.cu`

## InfiniBand Bandwidth Test

The InfiniBand script wraps both `ib_write_bw` and `ib_read_bw`, runs them with CUDA DMA-BUF enabled, and stores the output under `ib_logs/`.

### Prerequisites

- `ib_write_bw` and `ib_read_bw` must be installed and available in `PATH`.
- The selected Mellanox device must exist on both machines.
- Update `<master_ip_addr>` with the server node's reachable IP address.

### Run

On the server:

```bash
./measure_ib_bw.sh --rank 0 --master-ip <master_ip_addr> --mlx-device mlx5_6
```

On the client:

```bash
./measure_ib_bw.sh --rank 1 --master-ip <master_ip_addr> --mlx-device mlx5_6
```

### IB Logs

The script creates an `ib_logs/` directory in this repository and writes timestamped logs there.

Expected log names:

- Server:
  - `ib_logs/ib_write_bw_server_<YYYYMMDD_HHMMSS>.log`
  - `ib_logs/ib_read_bw_server_<YYYYMMDD_HHMMSS>.log`
- Client:
  - `ib_logs/ib_write_bw_client_rank1_<YYYYMMDD_HHMMSS>.log`
  - `ib_logs/ib_read_bw_client_rank1_<YYYYMMDD_HHMMSS>.log`

These logs are the raw `perftest` outputs from `ib_write_bw` and `ib_read_bw`. They are useful for:

- confirming which device and options were used,
- reviewing the reported bandwidth values in Gbit/s,
- comparing server/client runs collected at the same timestamp,
- keeping an archival record of each measurement sweep.

## PCIe Bandwidth Test

Compile the CUDA benchmark with:

```bash
nvcc -O3 -o measure_pcie_bw measure_pcie_bw.cu
```

Then run it and save the CSV output:

```bash
./measure_pcie_bw | tee pcie_sweep.csv
```

Note: the compile command above creates a binary named `measure_pcie_bw`. If you want to run `./pcie_latency_test | tee pcie_sweep.csv` instead, compile with `-o pcie_latency_test`.

### PCIe Output

The PCIe benchmark prints CSV directly to standard output with the following header:

```text
direction,size_bytes,avg_us,min_us,max_us,GBps
```

Saving with `tee` writes the same output to:

- `pcie_sweep.csv`

Each row records one transfer direction and payload size:

- `direction`: `H2D` for host-to-device, `D2H` for device-to-host
- `size_bytes`: transfer size in bytes
- `avg_us`: average transfer latency in microseconds
- `min_us`: minimum observed latency in microseconds
- `max_us`: maximum observed latency in microseconds
- `GBps`: effective transfer bandwidth in GB/s computed from the average latency

This file is the main artifact for plotting PCIe transfer performance across message sizes.

## Output Summary

Running the workflows in this directory produces the following saved outputs:

- `ib_logs/*.log`: raw timestamped InfiniBand bandwidth logs for `ib_write_bw` and `ib_read_bw`
- `pcie_sweep.csv`: CSV table of PCIe transfer latency and bandwidth results
