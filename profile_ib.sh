#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage:
  $0 --rank <rank> --master-ip <ip> --mlx-device <mlx_id> [--perftest-dir <path>]

Required:
  --rank <rank>            Rank (0 = server)
  --master-ip <ip>         Master IP
  --mlx-device <id>        mlx device (e.g., mlx5_0)

Optional:
  --perftest-dir <path>    Directory containing ib_write_bw, ib_read_bw,
                           ib_write_lat, and ib_read_lat
EOF
}

RANK=""
MASTER_IP=""
MLX_DEVICE=""
PERFTEST_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rank) RANK="$2"; shift 2 ;;
    --master-ip) MASTER_IP="$2"; shift 2 ;;
    --mlx-device) MLX_DEVICE="$2"; shift 2 ;;
    --perftest-dir) PERFTEST_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$RANK" || -z "$MASTER_IP" || -z "$MLX_DEVICE" ]]; then
  echo "Missing required args"
  usage
  exit 1
fi

resolve_binary() {
  local name="$1"
  if [[ -n "$PERFTEST_DIR" ]]; then
    echo "${PERFTEST_DIR%/}/$name"
  else
    echo "$name"
  fi
}

IB_WRITE_BW="$(resolve_binary ib_write_bw)"
IB_READ_BW="$(resolve_binary ib_read_bw)"
IB_WRITE_LAT="$(resolve_binary ib_write_lat)"
IB_READ_LAT="$(resolve_binary ib_read_lat)"

for bin in "$IB_WRITE_BW" "$IB_READ_BW" "$IB_WRITE_LAT" "$IB_READ_LAT"; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "Required binary not found: $bin"
    exit 1
  }
done

LOG_DIR="ib_logs"
mkdir -p "$LOG_DIR"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

role_label() {
  if [[ "$RANK" == "0" ]]; then
    echo "server"
  else
    echo "client_rank${RANK}"
  fi
}

run_profile() {
  local bin="$1"
  local name="$2"
  shift 2

  local role
  local log_file
  role="$(role_label)"
  log_file="${LOG_DIR}/${name}_${role}_${TIMESTAMP}.log"

  local cmd=("$bin" -d "$MLX_DEVICE" "$@")
  if [[ "$RANK" != "0" ]]; then
    cmd+=("$MASTER_IP")
  fi

  echo "[INFO] Running ${name} (${role}) -> ${log_file}"
  printf '[CMD]'; printf ' %q' "${cmd[@]}"; printf '\n'

  "${cmd[@]}" 2>&1 | tee "$log_file"
}

echo "[INFO] rank=$RANK master_ip=$MASTER_IP mlx=$MLX_DEVICE"
echo "[INFO] Logs -> $LOG_DIR"

CUDA_ARGS=(--use_cuda=0 --use_cuda_dmabuf)

run_profile "$IB_WRITE_BW" "ib_write_bw" -a -f 1 --report_gbits "${CUDA_ARGS[@]}"
run_profile "$IB_READ_BW" "ib_read_bw" -a -f 1 --report_gbits "${CUDA_ARGS[@]}"

echo "[INFO] Skipping ib_write_lat: perftest does not support CUDA write latency tests"

run_profile "$IB_READ_LAT" "ib_read_lat" -a "${CUDA_ARGS[@]}"

echo "[INFO] Done."
