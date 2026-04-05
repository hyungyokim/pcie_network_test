#!/usr/bin/env bash
set -euo pipefail

# measure_ib_bw.sh (with logging)

usage() {
  cat <<EOF
Usage:
  $0 --rank <rank> --master-ip <ip> --mlx-device <mlx_id> [--ibwrite-bw <path>]

Required:
  --rank <rank>          Rank (0 = server)
  --master-ip <ip>       Master IP
  --mlx-device <id>      mlx device (e.g., mlx5_0)

Optional:
  --ibwrite-bw <path>    Custom ib_write_bw path
EOF
}

RANK=""
MASTER_IP=""
MLX_DEVICE=""
IBWRITE_BW=""
IBREAD_BW=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rank) RANK="$2"; shift 2 ;;
    --master-ip) MASTER_IP="$2"; shift 2 ;;
    --mlx-device) MLX_DEVICE="$2"; shift 2 ;;
    --ibwrite-bw) IBWRITE_BW="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$RANK" || -z "$MASTER_IP" || -z "$MLX_DEVICE" ]]; then
  echo "Missing required args"; usage; exit 1
fi

# Resolve binaries
if [[ -n "$IBWRITE_BW" ]]; then
  IB_DIR="$(dirname "$IBWRITE_BW")"
  IBREAD_BW="$IB_DIR/ib_read_bw"
else
  IBWRITE_BW="ib_write_bw"
  IBREAD_BW="ib_read_bw"
fi

command -v "$IBWRITE_BW" >/dev/null || { echo "ib_write_bw not found"; exit 1; }
command -v "$IBREAD_BW"  >/dev/null || { echo "ib_read_bw not found"; exit 1; }

LOG_DIR="ib_logs"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

run_ib() {
  local bin="$1"
  local name="$2"

  if [[ "$RANK" == "0" ]]; then
    LOG_FILE="${LOG_DIR}/${name}_server_${TIMESTAMP}.log"

    echo "[INFO] Running ${name} SERVER → ${LOG_FILE}"
    echo "[CMD] $bin -d $MLX_DEVICE -a -f 1 --report_gbits --use_cuda=0 --use_cuda_dmabuf"

    "$bin" \
      -d "$MLX_DEVICE" \
      -a \
      -f 1 \
      --report_gbits \
      --use_cuda=0 \
      --use_cuda_dmabuf \
      | tee "$LOG_FILE"

  else
    LOG_FILE="${LOG_DIR}/${name}_client_rank${RANK}_${TIMESTAMP}.log"

    echo "[INFO] Running ${name} CLIENT → ${LOG_FILE}"
    echo "[CMD] $bin -d $MLX_DEVICE -a -f 1 --report_gbits --use_cuda=0 --use_cuda_dmabuf $MASTER_IP"

    "$bin" \
      -d "$MLX_DEVICE" \
      -a \
      -f 1 \
      --report_gbits \
      --use_cuda=0 \
      --use_cuda_dmabuf \
      "$MASTER_IP" \
      | tee "$LOG_FILE"
  fi
}

echo "[INFO] rank=$RANK master_ip=$MASTER_IP mlx=$MLX_DEVICE"
echo "[INFO] Logs → $LOG_DIR"

run_ib "$IBWRITE_BW" "ib_write_bw"
run_ib "$IBREAD_BW"  "ib_read_bw"

echo "[INFO] Done."
