FROM public.ecr.aws/shelf/lambda-libreoffice-base:26.2-node24-x86_64

COPY package.json package-lock.json ${LAMBDA_TASK_ROOT}/

RUN npm ci --omit=dev

COPY handler.js ${LAMBDA_TASK_ROOT}/

CMD [ "handler.handler" ]
