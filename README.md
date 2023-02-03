# Serverless LibreOffice ![](https://img.shields.io/badge/code_style-prettier-ff69b4.svg)

AWS Lambda DOCX to PDF converter using LibreOffice

<p align="left">
  This project was created based on <a href="https://github.com/shelfio/aws-lambda-libreoffice">
    https://github.com/shelfio/aws-lambda-libreoffice
  </a> which should be referenced for documentation, code samples, support, or other issues.
</p>

## Installation

```bash
npm install
```

## Development

Make changes to `handler.js` as needed

### Deployment

For a first time deployment, you will need to set up an AWS ECR repository for the Docker image:

```
aws ecr get-login-password --region <AWS REGION> | docker login --username AWS --password-stdin <AWS ACCOUNT ID>.dkr.ecr.ca-central-1.amazonaws.com

aws ecr create-repository --repository-name docx-to-pdf-converter --image-scanning-configuration scanOnPush=true --image-tag-mutability MUTABLE
```

Once the ECR repository has been created, run the following to build, tag, and push the image to ECR

```
docker build -t docx-to-pdf-converter .

docker tag  docx-to-pdf-converter:latest <AWS ACCOUNT ID>.dkr.ecr.ca-central-1.amazonaws.com/docx-to-pdf-converter:latest

docker push <AWS ACCOUNT ID>.dkr.ecr.ca-central-1.amazonaws.com/docx-to-pdf-converter:latest
```

**[First time deployment only]** Once the image has been pushed, you'll need to create a Lambda function from the image. To do this go to `Lambda > Create Function > Container Image > Browse images` and select your newly created image.

**[Subsequent deployments]** Repeat the build, tag, and push process, and then go to your Lambda's Image settings. Select `Deploy new image` and browse for the image tagged `latest`

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
