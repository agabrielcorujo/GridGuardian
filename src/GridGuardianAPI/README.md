# GridGuardian API

FastAPI runs in AWS Lambda through `main.handler` (Mangum). Python 3.11
matches `.python-version`. Lambda supplies AWS credentials and the region;
`TABLE_NAME` defaults to `GridGuardian`.

## Build locally

From the repository root:

```sh
docker buildx build --platform linux/amd64 --provenance=false --load \
  -f docker/GridGuardian.Dockerfile \
  -t gridguardian-api:local src/GridGuardianAPI
```

## Stage 1: publish to ECR

Commit the Dockerfile, workflow, API source, and `requirements.txt`, then push
branch `api` or `main`. Changes under `src/GridGuardianAPI/`, the Dockerfile,
or the workflow trigger **Publish and deploy GridGuardian API**. Once the workflow
is on the default branch, it can also be started from the Actions tab.

The workflow assumes the existing AWS role through GitHub OIDC, so no AWS
access-key secrets or repository variables are required:

- Account: `379810014574`, region: `us-east-1`
- Role: `gridguardian-dev-github-ecr-push`
- Repository: `gridguardian-dev-image-analyzer`

The shared repository uses immutable tags. Each API image gets
`api-<commit>-<run-id>-<attempt>` so reruns and analyzer images do not collide.
The workflow summary includes the image URI and immutable digest URI.
Single-architecture images have provenance and SBOM attestations disabled for
Lambda compatibility.

## Stage 2: Terraform and releases

See [the infrastructure instructions](../../terraform/README.md) for initial
creation of `GridGuardianAPI` using the first published API image digest.
After you apply Terraform, the GitHub workflow also deploys subsequent images
and waits for Lambda to finish updating. Terraform owns all AWS infrastructure;
GitHub Actions owns image publishing and Lambda code releases.
