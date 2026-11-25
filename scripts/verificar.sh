#!/usr/bin/env bash
# Muestra el estado completo del laboratorio: stack, recursos, instancia, app y contenedor.
# Uso: ./scripts/verificar.sh [nombre-del-stack] [ruta-de-la-clave.pem]
set -euo pipefail

STACK="${1:-lab-cloudformation-docker}"
KEY="${2:-$HOME/.ssh/lab-cloudformation-key.pem}"

salida() {
  aws cloudformation describe-stacks --stack-name "$STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

echo "== Stack =="
aws cloudformation describe-stacks --stack-name "$STACK" \
  --query 'Stacks[0].[StackName,StackStatus]' --output text

echo; echo "== Recursos =="
aws cloudformation list-stack-resources --stack-name "$STACK" \
  --query 'StackResourceSummaries[].[LogicalResourceId,ResourceType,ResourceStatus]' --output table

echo; echo "== Salidas =="
aws cloudformation describe-stacks --stack-name "$STACK" \
  --query 'Stacks[0].Outputs[].[OutputKey,OutputValue]' --output table

IP="$(salida PublicIP)"
ID="$(salida InstanceId)"

echo; echo "== Instancia =="
aws ec2 describe-instances --instance-ids "$ID" \
  --query 'Reservations[0].Instances[0].[InstanceId,InstanceType,State.Name,PublicIpAddress,Tags[?Key==`Name`].Value|[0]]' \
  --output text

echo; echo "== Aplicación (HTTP) =="
curl -sI --max-time 8 "http://$IP" | head -3
curl -s --max-time 8 "http://$IP" | grep -io '<title>.*</title>' || true

if [[ -f "$KEY" ]]; then
  echo; echo "== Contenedor Docker (por SSH) =="
  ssh -i "$KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "ec2-user@$IP" \
    'sudo docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"; systemctl is-active docker cfn-hup'
fi
