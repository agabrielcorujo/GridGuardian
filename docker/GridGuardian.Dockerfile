FROM public.ecr.aws/lambda/python:3.11

# Build from src/GridGuardianAPI; the runtime invokes the Mangum handler.
COPY requirements.txt ${LAMBDA_TASK_ROOT}/requirements.txt
RUN python -m pip install --no-cache-dir --require-hashes \
    --requirement ${LAMBDA_TASK_ROOT}/requirements.txt \
    --target ${LAMBDA_TASK_ROOT}

COPY main.py ${LAMBDA_TASK_ROOT}/main.py
CMD ["main.handler"]
