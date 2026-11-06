#!/usr/bin/env bash
# Converts test/fixtures/convert.docx through a deployed function and checks the PDF it writes.
# Usage: scripts/verify-stack.sh <function-name> <stage>. Needs aws, jq and poppler-utils.
# Uses the main stack's PR fixtures bucket, which expires objects after a day.
set -euo pipefail

fn=$1
stage=$2
account=$(aws sts get-caller-identity --query Account --output text)
bucket="docx-to-pdf-converter-pr-fixtures-$account"
# The handler writes /tmp/<key> and puts the PDF at the bucket root, so the key MUST NOT contain a slash.
name="$stage-${GITHUB_SHA:-$(git rev-parse HEAD)}"
# Kept for the workflow to upload, so a run's input and output can be opened afterwards.
out=${VERIFY_OUT:-verify-output}
rm -rf "$out" && mkdir -p "$out"

cp test/fixtures/convert.docx "$out/convert.docx"
aws s3api put-object --bucket "$bucket" --key "$name.docx" --body "$out/convert.docx" >/dev/null
jq -n --arg bucket "$bucket" --arg key "$name.docx" '{bucket: $bucket, key: $key}' >"$out/payload.json"
aws lambda invoke \
  --function-name "$fn" \
  --cli-binary-format raw-in-base64-out \
  --payload "fileb://$out/payload.json" \
  --log-type Tail \
  "$out/response.json" >"$out/invoke.json"
jq -r '.LogResult' "$out/invoke.json" | base64 -d >"$out/tail.log"
grep '^REPORT' "$out/tail.log" || true

if jq -e '.FunctionError' "$out/invoke.json" >/dev/null; then
  echo "Function error:" && cat "$out/response.json" "$out/tail.log"
  exit 1
fi
jq -e --arg key "$name.pdf" '.Key == $key' "$out/response.json" >/dev/null || {
  echo "Unexpected response:" && cat "$out/response.json" "$out/tail.log"
  exit 1
}

aws s3api get-object --bucket "$bucket" --key "$name.pdf" "$out/convert.pdf" >/dev/null
[ "$(head -c 4 "$out/convert.pdf")" = "%PDF" ] || { echo "Output is not a PDF"; exit 1; }
pdffonts "$out/convert.pdf"
pages=$(pdfinfo "$out/convert.pdf" | awk '/^Pages:/ {print $2}')
[ "$pages" = 2 ] || { echo "Expected 2 pages, got $pages"; exit 1; }
pdftotext "$out/convert.pdf" - | grep -q "Second page" || { echo "Second page text is missing"; exit 1; }
