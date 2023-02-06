FROM public.ecr.aws/shelf/lambda-libreoffice-base:7.4-node16-x86_64

COPY ./ ${LAMBDA_TASK_ROOT}/

# Dependency not supplied by lambda-libreoffice-base image
RUN yum install java-1.8.0-openjdk-devel -y

RUN npm install

CMD [ "handler.handler" ]