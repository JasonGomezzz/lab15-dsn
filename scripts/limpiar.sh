#!/usr/bin/env bash
# Limpieza de recursos para evitar costos: elimina el stack y, si se pide, el Key Pair.
# Uso: ./scripts/limpiar.sh [nombre-del-stack] [--con-key-pair]
set -euo pipefail

STACK="${1:-lab-cloudformation-docker}"
KEY_NAME="lab-cloudformation-key"

read -r -p "Se eliminará el stack '$STACK' (EC2, Security Group, EIP, rol IAM). ¿Continuar? [s/N] " r
[[ "$r" =~ ^[sS]$ ]] || { echo "Cancelado."; exit 0; }

aws cloudformation delete-stack --stack-name "$STACK"
echo "Esperando DELETE_COMPLETE..."
aws cloudformation wait stack-delete-complete --stack-name "$STACK"
echo "Stack eliminado."

if [[ "${2:-}" == "--con-key-pair" ]]; then
  aws ec2 delete-key-pair --key-name "$KEY_NAME"
  rm -f "$HOME/.ssh/$KEY_NAME.pem"
  echo "Key Pair $KEY_NAME eliminado (nube y archivo local)."
fi
