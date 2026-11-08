# GridGuardian infrastructure

<<<<<<< HEAD
`aws-infra` is the shared branch for all Terraform changes, including the
analyzer and API. Both Adrian and Pablo must pull this branch before planning
or applying. Do not apply the older Terraform configuration from `api`.

## Synchronize an existing checkout
=======
Run Terraform from this directory using the existing local `terraform.tfstate`.
Keep the local state and its backup. Never commit state, `.terraform/`, or plan
files. Commit `.terraform.lock.hcl` and the `.tf` source files.

## File layout

All `.tf` files here belong to one root module and share the same state.

| File | Contents |
| --- | --- |
| `versions.tf` | Terraform and AWS provider version requirements |
| `providers.tf` | AWS region, allowed account, and default tags |
| `variables.tf` | Input variables, including the initial API image digest |
| `api.tf` | API Lambda, execution role and policy, and log group |
| `analyzer.tf` | Analyzer execution role and policy |
| `github.tf` | GitHub OIDC provider, publishing role, and deployment permissions |
| `ecr.tf` | Shared image repository and Lambda retrieval policy |
| `dynamodb.tf` | Reports table |
| `sqs.tf` | Analysis failure queue |
| `outputs.tf` | Infrastructure outputs |

Resource blocks were regrouped from `main.tf`, `existing.tf`, and `api.tf`
without changing their addresses or configuration. Keep existing resource labels
and instance keys, including `aws_iam_openid_connect_provider.github[0]`.
This file reorganization requires no imports, state moves, or infrastructure apply.

## Verify organization changes and refresh state

Use the existing state and real `api_image_digest` input. Do not initialize a
new empty state to replace the existing state. Run:

```sh
export AWS_PROFILE=379810014574_TerraformAccess
terraform init -lockfile=readonly
terraform fmt -check
terraform validate
terraform plan
```

Review the regular plan for zero infrastructure changes. Refresh-only mode does
not check whether configuration changes would modify infrastructure. If the
regular plan proposes changes, investigate them before proceeding; do not apply
them as part of a file reorganization.

To separately refresh state from AWS without changing cloud resources:

```sh
terraform plan -refresh-only -out=refresh.tfplan
terraform show refresh.tfplan
terraform apply refresh.tfplan
```

Review the refresh plan before applying it. Applying the saved refresh-only plan
updates Terraform state and outputs to reflect AWS; it does not deploy changes.

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
>>>>>>> 230aa06 (updated terraform directory so its more intuitive)

```sh
git switch aws-infra
git pull --ff-only origin aws-infra
cd terraform
export AWS_PROFILE=379810014574_TerraformAccess
terraform init
```

Keep your existing state and local `terraform.tfvars`; never commit them. Update
any existing `github_publish_branches` override to include `main`, `aws-infra`,
and `api`. Updating the variable default does not override a local tfvars value.
Keep the existing analyzer `image_tag` set: clearing it disables the worker and
plans to remove its function and S3 integration.

Set `api_image_digest` to the API digest from the Actions summary, or read the
currently deployed API image with:

```sh
aws lambda get-function --function-name GridGuardianAPI --region us-east-1 \
  --query 'Code.ResolvedImageUri' --output text
```

Use only the `sha256:...` suffix as `api_image_digest`. The existing API resources
are adopted by `api-imports.tf` when missing from the selected state. The import
blocks preserve their resource addresses and do not recreate the API. Terraform
ignores subsequent API image changes; GitHub Actions owns API image releases.

```sh
terraform plan -out=infra.tfplan
terraform show infra.tfplan
terraform apply infra.tfplan
```

Review the saved plan before applying: both functions must retain ECR retrieval
access, and GitHub trust must retain all three branches. Expect API imports where
needed, not API replacement. Investigate any resource destruction or replacement.

Git synchronizes configuration, not Terraform state. This checkout currently has
no shared remote backend. Agree on one authoritative state and serialize applies;
independent local state files can still disagree even on the same Git branch.
After adopting the API into the authoritative state, retire the old API checkout
from infrastructure applies. Do not apply from both states.

## API configuration

`GridGuardianAPI` uses the existing ECR repository, Python `main.handler`,
`x86_64`, 256 MB, a 15-second timeout, and `TABLE_NAME=GridGuardian`. Its role
allows DynamoDB Query/PutItem and writing its own logs. The log group retains
14 days. No public function URL or HTTP gateway is provisioned.

The GitHub role can publish images and update only this API function. Its OIDC
trust includes `main`, `aws-infra`, and `api`, with the repository ID subjects
and the existing legacy `api` subject. The ECR repository policy permits both
the analyzer and API Lambda functions to retrieve images. Keep both permissions
in Terraform: older configurations reverted them and broke Actions deployments.

API pushes on `api` or `main` publish a unique immutable image tag and deploy
by digest. Infrastructure work on `aws-infra` does not deploy API source.

## Reports table

Terraform manages the table named by `reports_table_name` with on-demand billing and this key schema:

| Key | Attribute | Type | Example |
| --- | --- | --- | --- |
| Partition key | `zipcode` | String | `02108` |
| Sort key | `condition-timestamp` | String | `HEALTHY-2026-11-07T20:00:00.000000Z` |

Writers must build `condition-timestamp` as `<condition>-<timestamp>`. Use a consistent UTC timestamp format and preserve ZIP codes as strings, including leading zeros. Each ZIP code and sort key pair must uniquely identify an item.

Query a ZIP code and condition using `#zip = :zip AND begins_with(#sk, :condition)`, with attribute names `{"#zip": "zipcode", "#sk": "condition-timestamp"}` and values such as `:zip = "02108"`, `:condition = "HEALTHY-"`. The trailing separator avoids matching other condition names with the same prefix.

The import block adopts the existing table without recreating it. The verified table is in account `379810014574`, region `us-east-1`. Preview the import and table changes with:

```sh
AWS_PROFILE=379810014574_TerraformAccess terraform plan -out=reports.tfplan -target=aws_dynamodb_table.reports
```

The configured keys and billing mode match the existing table. The plan should import it and may update project tags in place; it should not replace it. After reviewing, apply the saved plan using the same AWS profile:

```sh
AWS_PROFILE=379810014574_TerraformAccess terraform apply reports.tfplan
```

The Lambda uses `REPORTS_TABLE`, `REPORT_PARTITION_KEY`, and `REPORT_SORT_KEY` from `main.tf`. Include `zipcode` in each uploaded image's S3 user metadata as a five-digit ZIP or ZIP+4 string (for example, `00901`). Missing or invalid ZIP codes fail processing rather than writing to an invented location.

Reports use `<classification>-<timestamp>` for the sort key, with `HEALTHY`, `MAINTENANCE`, or `DAMAGES` and a UTC timestamp with six fractional digits. Unassessable images retain a null classification and use the `UNASSESSED-` key prefix. The timestamp comes from capture metadata when supplied, otherwise the S3 event time (or object last-modified time). Two different images with the same ZIP, classification, and timestamp produce a collision error rather than overwrite a report; supply distinct capture timestamps for distinct observations.

The worker also stores a `REPORT-<source_id>` control item in the same ZIP partition to prevent duplicate analysis on retries. It atomically writes the classified report and completes this control item. Condition-prefixed queries return reports; ZIP-only queries also include control items. The report retains `report_id` as a non-key attribute. Reclassifying existing reports requires moving them to the new condition key; this upload worker does not reclassify completed reports.
