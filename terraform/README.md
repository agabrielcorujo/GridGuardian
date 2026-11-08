# GridGuardian infrastructure

Run Terraform from this directory using the existing local `terraform.tfstate`.
`existing.tf` restores the definitions for the nine managed resources already
in that state, at the same addresses. `main.tf` was empty before this change;
applying an empty configuration would have removed those resources.
Keep the local state and its backup. Never commit state, `.terraform/`, or plan
files. Commit `.terraform.lock.hcl` and the `.tf` source files.

## First deployment

1. Commit and push the API source, requirements, Dockerfile, and GitHub workflow
   on `api` or `main`. The workflow publishes an `api-*` image to the shared ECR
   repository. If the function does not exist, the workflow records that setup is
   pending and leaves the published image ready. If deployment permissions are
   missing, the workflow fails after publishing; apply Terraform and rerun it.
2. Copy `terraform.tfvars.example` to `terraform.tfvars`. Replace its placeholder
   with the API image digest from the Actions summary (`sha256:...`, without the
   repository prefix). Use the API image, not an analyzer image.
3. Run:

```sh
export AWS_PROFILE=379810014574_TerraformAccess
terraform init
terraform plan -out=api.tfplan
terraform apply api.tfplan
```

Review the plan: it should create `GridGuardianAPI`, its execution role/policy,
a 14-day CloudWatch log group, and the GitHub Lambda deployment policy. It also
extends the existing ECR retrieval policy to allow the API, preserving analyzer
access, and records the `api` branch in GitHub OIDC trust. No existing resources
should be destroyed or replaced. Do not run without the existing local state;
these shared resources are already managed and are not new resources to create.

The API uses Python's `main.handler` baked into the container, architecture
`x86_64`, 256 MB RAM, a 15-second timeout, and `TABLE_NAME=GridGuardian`.
Its role allows only DynamoDB Query/PutItem and writes to its own log group.
No HTTP gateway or public function URL is provisioned in this change.

## Subsequent releases

Push API changes to `api` or `main`. The workflow publishes a unique immutable
image tag and updates the existing Lambda by digest, waits for completion, and
checks the deployed digest. Both branches deploy to the same development API;
release runs share a concurrency group. Terraform ignores `image_uri` changes
after creation so a later infrastructure apply will not roll back a CI release.
Keep the initial `api_image_digest` input available for Terraform plans.
GitHub does not create infrastructure or run Terraform.

The existing analyzer Lambda was not recorded as an instance in the supplied
state and is outside this change. Its existing role, policy, queue, repository,
and image retrieval permission are retained.
