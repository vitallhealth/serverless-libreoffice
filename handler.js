/**
 * Lambda handler that converts a DOCX in S3 to PDF with LibreOffice and writes the PDF back
 * to the same bucket. Runs in the lambda-libreoffice-base container image (see Dockerfile).
 */
import {
  GetObjectCommand,
  PutObjectCommand,
  S3Client,
} from "@aws-sdk/client-s3";
import { canBeConvertedToPDF, convertTo } from "@shelf/aws-lambda-libreoffice";
import { readFileSync, writeFileSync } from "fs";
import path from "path";

const s3 = new S3Client({});

/**
 * Converts `s3://bucket/key` to PDF and uploads it to the bucket root as `<basename>.pdf`.
 * @param event Invocation payload.
 * @param event.bucket S3 bucket holding the source document.
 * @param event.key S3 key of the `.docx` document.
 * @returns The uploaded PDF's key, or `false` when the file type can't be converted.
 * @throws When the S3 read/write fails or LibreOffice can't convert the file.
 */
// Lambda resolves the handler by export name, so it can't be a default export.
// eslint-disable-next-line import/prefer-default-export
export const handler = async ({ bucket, key }) => {
  const { Body } = await s3.send(
    new GetObjectCommand({ Bucket: bucket, Key: key })
  );
  const inputFileBuffer = await Body.transformToByteArray();

  // convertTo reads /tmp/<key>, deletes it afterwards and writes /tmp/<name>.pdf
  writeFileSync(`/tmp/${key}`, inputFileBuffer);

  if (!canBeConvertedToPDF(key)) {
    return false;
  }

  const outputFilename = await convertTo(key, "pdf");
  const outputFileBuffer = readFileSync(outputFilename);

  const pdfKey = `${path.basename(key, ".docx")}.pdf`;

  await s3.send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: pdfKey,
      Body: outputFileBuffer,
      ContentType: "application/pdf",
    })
  );

  return { Key: pdfKey };
};
