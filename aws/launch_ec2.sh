#!/usr/bin/env bash
# Jalankan dari PC/Termux yang sudah `aws configure` (dan `gh auth login` atau set RUNNER_TOKEN).
# Contoh: GH_REPO=USER/ci-build ./aws/launch_ec2.sh
set -euo pipefail
cd "$(dirname "$0")"

GH_REPO="${GH_REPO:?isi GH_REPO=owner/repo}"
REGION="${REGION:-us-east-1}"
TYPE="${TYPE:-c6a.8xlarge}"          # 32 vCPU / 64GB
DISK="${DISK:-400}"                  # GB
SPOT="${SPOT:-true}"                 # true = jauh lebih murah, bisa diputus AWS
BEHAVIOR="${BEHAVIOR:-terminate}"    # terminate | stop (stop tidak boleh untuk spot one-time)
IDLE_MINUTES="${IDLE_MINUTES:-30}"
MAX_HOURS="${MAX_HOURS:-10}"
RUNNER_LABELS="${RUNNER_LABELS:-aosp}"
KEY_NAME="${KEY_NAME:-}"             # opsional, untuk SSH
[ "$SPOT" = "true" ] && BEHAVIOR=terminate

if [ -z "${RUNNER_TOKEN:-}" ]; then
  RUNNER_TOKEN=$(gh api -X POST "repos/${GH_REPO}/actions/runners/registration-token" --jq .token)
fi

AMI=$(aws ssm get-parameter --region "$REGION" \
  --name /aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
  --query Parameter.Value --output text)

UD=$(mktemp)
{
  echo '#!/bin/bash'
  echo "export GH_REPO='$GH_REPO' RUNNER_TOKEN='$RUNNER_TOKEN' IDLE_MINUTES='$IDLE_MINUTES' MAX_HOURS='$MAX_HOURS' RUNNER_LABELS='$RUNNER_LABELS' TG_BOT_TOKEN='${TG_BOT_TOKEN:-}' TG_CHAT_ID='${TG_CHAT_ID:-}'"
  tail -n +2 setup_runner.sh
} > "$UD"

ARGS=(--region "$REGION" --image-id "$AMI" --instance-type "$TYPE"
  --instance-initiated-shutdown-behavior "$BEHAVIOR"
  --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=${DISK},VolumeType=gp3,DeleteOnTermination=true}"
  --metadata-options "HttpTokens=required"
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=aosp-ci-runner}]"
  --user-data "file://$UD")
[ -n "$KEY_NAME" ] && ARGS+=(--key-name "$KEY_NAME")
[ "$SPOT" = "true" ] && ARGS+=(--instance-market-options "MarketType=spot,SpotOptions={SpotInstanceType=one-time}")

ID=$(aws ec2 run-instances "${ARGS[@]}" --query 'Instances[0].InstanceId' --output text)
rm -f "$UD"
echo "Instance: $ID ($TYPE, spot=$SPOT, region=$REGION)"
echo "Tunggu ±3-5 menit sampai runner 'aosp' muncul di GitHub: Settings > Actions > Runners"
echo "Matikan manual: aws ec2 terminate-instances --region $REGION --instance-ids $ID"