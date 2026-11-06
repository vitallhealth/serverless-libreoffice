#!/usr/bin/env bash
# Builds the image, pushes it to ECR and deploys template.yaml as docx-to-pdf-converter-<stage>.
# Usage: scripts/deploy-stack.sh <stage> <github-environment>, e.g. `main production` or `pr-12 pr`.
# Called by deploy.yml and pr-stack.yml. Needs AWS credentials for gha-serverless-libreoffice-<env>.
set -euo pipefail

stage=$1
env=$2
region=${AWS_REGION:-ca-central-1}
account=$(aws sts get-caller-identity --query Account --output text)
registry="$account.dkr.ecr.$region.amazonaws.com"

if [ "$stage" = main ]; then
  repo=docx-to-pdf-converter
  environment_tag=Production
else
  repo=docx-to-pdf-converter-pr
  environment_tag=Test
fi
tag="$stage-${GITHUB_SHA:-$(git rev-parse HEAD)}"

aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$registry"
# --provenance=false keeps a single-image manifest. Lambda rejects manifest lists.
docker build --platform linux/amd64 --provenance=false -t "$registry/$repo:$tag" .
docker push "$registry/$repo:$tag"
digest=$(aws ecr describe-images --repository-name "$repo" --image-ids imageTag="$tag" \
  --query 'imageDetails[0].imageDigest' --output text)

aws cloudformation deploy \
  --stack-name "docx-to-pdf-converter-$stage" \
  --template-file template.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset \
  --parameter-overrides \
    Stage="$stage" \
    ImageUri="$registry/$repo@$digest" \
    PermissionsBoundaryArn="arn:aws:iam::$account:policy/gha-serverless-libreoffice-$env-boundary" \
  --tags STAGE="$stage" Environment="$environment_tag"

# Production keeps the console name that callers invoke.
if [ "$stage" = main ]; then fn=docx-to-pdf-converter; else fn="docx-to-pdf-converter-$stage"; fi
aws lambda wait function-updated-v2 --function-name "$fn"
