# LibreOffice DOCX to PDF ![](https://img.shields.io/badge/code_style-prettier-ff69b4.svg)

AWS Lambda DOCX to PDF converter using LibreOffice

<p align="left">
  This project was created based on <a href="https://github.com/shelfio/aws-lambda-libreoffice">
    https://github.com/shelfio/aws-lambda-libreoffice
  </a> which should be referenced for documentation, code samples, support, or other issues.
</p>

## Installation

Requires Node.js 24 or newer.

```bash
npm install
```

## Development

Make changes to `handler.js` as needed. It is an ES module and uses AWS SDK v3, since the Node.js 24 Lambda runtime doesn't bundle SDK v2.

The image is built on `public.ecr.aws/shelf/lambda-libreoffice-base:26.2-node24-x86_64` (LibreOffice 26.2, Amazon Linux 2023). The base image is x86_64 only, so the Lambda function's architecture MUST be `x86_64`.

To run the image locally with the Lambda Runtime Interface Emulator:

```
docker build --platform linux/amd64 -t docx-to-pdf-converter .
docker run --platform linux/amd64 -p 9000:8080 -e AWS_REGION=ca-central-1 -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN docx-to-pdf-converter
curl -XPOST localhost:9000/2015-03-31/functions/function/invocations -d '{"bucket":"bucket_name","key":"s3_key.docx"}'
```

### Deployment

`template.yaml` is plain CloudFormation, one stack per stage:

- `docx-to-pdf-converter-main` is production. Its function keeps the name `docx-to-pdf-converter`, which callers invoke. `deploy.yml` deploys it on every push to `main`, so merging a PR ships it. It then converts `test/fixtures/convert.docx` through the function.
- `docx-to-pdf-converter-pr-<n>` is a throwaway stack per pull request. `pr-stack.yml` deploys and checks it on every push to the PR and deletes it when the PR closes.

Both workflows run `scripts/deploy-stack.sh` and `scripts/verify-stack.sh`, under the OIDC roles `gha-serverless-libreoffice-production` and `gha-serverless-libreoffice-pr` from admin-dev-ops. The repo needs a `AWS_ACCOUNT_ID` variable and two GitHub Environments: `production`, limited to `main`, and `pr`.

Each run uploads the check's fixture, payload, raw response, log tail and PDF as a `verify-<stage>-<sha>` artifact, kept for 14 days, failed runs included.

The main stack also owns what the PR stacks share: the `/aws/lambda/docx-to-pdf-converter-pr` log group, the `docx-to-pdf-converter-pr` ECR repo (images expire after 14 days) and the `docx-to-pdf-converter-pr-fixtures-<account>` bucket (objects expire after a day). The deploy roles can't delete log groups or S3 objects, so a PR stack MUST NOT create either.

#### Importing the console-made function (one time)

The production function, its role and its log group were created in the console. Run this as an admin, from this branch, before the first PR stack deploys. `migration/import.yaml` matches the live resources, so the import changes nothing:

```bash
aws cloudformation create-change-set --stack-name docx-to-pdf-converter-main \
  --change-set-name import --change-set-type IMPORT \
  --template-body file://migration/import.yaml --capabilities CAPABILITY_NAMED_IAM \
  --resources-to-import '[
    {"ResourceType":"AWS::Logs::LogGroup","LogicalResourceId":"ConverterLogGroup","ResourceIdentifier":{"LogGroupName":"/aws/lambda/docx-to-pdf-converter"}},
    {"ResourceType":"AWS::IAM::Role","LogicalResourceId":"ConverterRole","ResourceIdentifier":{"RoleName":"docx-to-pdf-converter-role-s30byqzk"}},
    {"ResourceType":"AWS::Lambda::Function","LogicalResourceId":"ConverterFunction","ResourceIdentifier":{"FunctionName":"docx-to-pdf-converter"}}]'
aws cloudformation wait change-set-create-complete --stack-name docx-to-pdf-converter-main --change-set-name import
aws cloudformation execute-change-set --stack-name docx-to-pdf-converter-main --change-set-name import
aws cloudformation wait stack-import-complete --stack-name docx-to-pdf-converter-main
aws cloudformation update-termination-protection --enable-termination-protection --stack-name docx-to-pdf-converter-main
```

Then move the stack onto `template.yaml`, still on the image that's live today. This adds the boundary to the role and creates the shared PR resources:

```bash
aws cloudformation deploy --stack-name docx-to-pdf-converter-main --template-file template.yaml \
  --capabilities CAPABILITY_NAMED_IAM --no-execute-changeset \
  --parameter-overrides Stage=main \
    ImageUri=699253540666.dkr.ecr.ca-central-1.amazonaws.com/docx-to-pdf-converter@sha256:113d1d4ec9ba824ce1e6227cc8142cd76e00a10b45ccd2933e9ea7cc8681b139 \
    PermissionsBoundaryArn=arn:aws:iam::699253540666:policy/gha-serverless-libreoffice-production-boundary \
  --tags STAGE=main Environment=Production
```

Review the change set and execute it. `migration/` can be deleted once this has run.

## Usage

The `handler` function accepts a `bucket` and a `key` argument, which are the name of an S3 bucket, and the S3 key of an object in that bucket. `key` should point to a valid `.docx` document.

```ts
import AWS from "aws-sdk";

async function convertToPdf(): Promise<string> {
  const lambda = new AWS.Lambda();
  const payload = {
      bucket: 'bucket_name',
      key: 's3_key.docx',
  };
  const params: AWS.Lambda.InvocationRequest = {
    FunctionName: 'docx-to-pdf-converter',
    Payload: JSON.stringify(payload),
    InvocationType: 'RequestResponse',
  };
  const response = await lambda
    .invoke(params, (err) => {
      if (err) {
        throw err;
      }
    })
    .promise();

  const result = JSON.parse(response.Payload as string);
  if (!('Key' in result)) {
    throw new Error('File could not be converted to PDF');
  }
  return result.Key;
}
```

### Troubleshooting

- If you receive an `AccessDenied` error when reading/writing to S3, check that the Lambda function has permission to read/write to the bucket and object that you supplied as input.
