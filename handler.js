const { writeFileSync, readFileSync } = require("fs");
const {
  convertTo,
  canBeConvertedToPDF,
} = require("@shelf/aws-lambda-libreoffice");
const { S3 } = require("aws-sdk");
const path = require("path");

module.exports.handler = async ({ bucket, key }) => {
  const s3 = new S3({ params: { Bucket: bucket } });

  const { Body: inputFileBuffer } = await s3.getObject({ Key: key }).promise();
  const inputFilename = `/tmp/${key}`;

  writeFileSync(inputFilename, inputFileBuffer);
  // assuming there is a document.docx file inside /tmp dir
  // original file will be deleted afterwards

  // it is optional to invoke this function, you can skip it if you're sure about file format
  if (!canBeConvertedToPDF(key)) {
    return false;
  }

  const outputFilename = convertTo(key, "pdf"); // returns /tmp/document.pdf

  const outputFileBuffer = readFileSync(outputFilename);

  const pdfKey = `${path.basename(key, ".docx")}.pdf`;

  await s3
    .upload({
      Key: pdfKey,
      Body: outputFileBuffer,
      ContentType: "application/pdf",
    })
    .promise();

  return { Key: pdfKey };
};
