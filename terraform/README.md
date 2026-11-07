# GridGuardian infrastructure

```text
S3 images/ upload -> Lambda container -> Bedrock Nova
                          |                 |
                          +-- JSON report <-+
                          +-- DynamoDB GridGuardian (report_id)
                          +-- CloudWatch logs
                          +-- SQS failure destination
```

This stack references the existing S3 bucket `grid-guardian-images` and DynamoDB table `GridGuardian` in `us-east-1`. The table's partition key is `report_id` (String), with no sort key. Terraform reads these resources as data sources: it does not recreate, import, delete, or change their storage settings, policies, encryption, backups, or tags. In particular, it does not enable PITR on the existing table.

It provisions an immutable-tag ECR repository, the Lambda execution role, logs, and a failed-invocation queue. Once a worker image is provided, it also provisions Lambda and its authorized S3 upload trigger. The role can read the image prefix in the existing bucket, read/write the existing reports table, invoke the selected US Nova inference profile, write logs, and send failure records. Bucket and table names can be overridden in tfvars. Use a separate existing bucket/table for each environment that needs isolated data.

The API, frontend, GitHub Actions workflow, and worker Dockerfile/handler are outside this infrastructure stack. The worker still needs to be implemented. Bedrock is a managed service called by the worker. The deployment identity must have permission to create these resources, pass the Lambda execution role, and read ECR images/manage the repository policy. Organization policies, model availability, and Bedrock quotas still apply.

## Initial deployment

Use your authenticated CLI profile; do not put credentials in tfvars or source files.

```powershell
$env:AWS_PROFILE = "379810014574_TerraformAccess"
$env:AWS_REGION = "us-east-1"
aws sts get-caller-identity
Set-Location C:\Users\Pablo\GridGuardian\terraform
Copy-Item terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check
terraform validate
terraform test
terraform plan -out=base.tfplan
terraform apply base.tfplan
```

Keep `image_tag = null` for the initial apply: it references existing storage and creates the repository and worker support resources without Lambda or the S3 trigger. Previously uploaded images are not processed retroactively after enabling the trigger. The existing bucket must be in the same Region as Lambda. The deployment identity needs permission to read bucket metadata and describe the table as well as configure the bucket notification.

Requires Terraform 1.7 or newer. Tests use a mocked AWS provider to check the bootstrap plan and simulate worker deployment without AWS calls or real resource creation.

State is local by default. State, real tfvars, plans, and provider caches are ignored by Git. Commit `.terraform.lock.hcl` after initialization. Before teammates or CI apply the stack, configure a shared remote backend with locking. Do not use separate local states for the same resources.

## Push an image and enable Lambda

Implement a Lambda-compatible Python handler and Dockerfile first, including dependencies and the root `prompt.txt`. Build Linux amd64 images to match Lambda's configured x86_64 architecture. For example, once `docker/analysis.Dockerfile` has been implemented, run these commands from `terraform/`:

```powershell
$repository = terraform output -raw ecr_repository_url
$registry = ($repository -split "/")[0]
$imageTag = git rev-parse HEAD
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $registry
docker buildx build --platform linux/amd64 --provenance=false --load -f ../docker/analysis.Dockerfile -t "${repository}:${imageTag}" ..
docker push "${repository}:${imageTag}"
```

The Dockerfile in this example does not exist yet. Use a unique tag for every image build (such as a committed Git SHA); tags cannot be overwritten. Change `image_tag` in `terraform.tfvars` to the pushed tag, then run:

```powershell
terraform plan -out=worker.tfplan
terraform apply worker.tfplan
```

Terraform resolves the tag to its digest for reproducible deployment. Subsequent updates use a new tag and another reviewed apply. Keep `image_tag` set after enabling the worker: setting it to null plans deletion of Lambda and its trigger. Let Terraform own the deployed image rather than independently updating Lambda from CI.

## Worker contract

- Implement an event handler, not an API web server, and set its command in a Lambda-compatible container (AWS provides Python base images). Bundle `prompt.txt`; Terraform does not build images or upload prompts.
- Read `IMAGES_BUCKET`, `IMAGE_PREFIX`, `REPORTS_TABLE`, `REPORT_ID_KEY` (set to `report_id`), and `BEDROCK_MODEL_ID`. AWS supplies temporary credentials through the role.
- Iterate over S3 event `Records`, URL-decode each key, and fetch the event's `versionId` when supplied. Upload only images under `images/`; other files and outputs must use another prefix. All ObjectCreated events under the prefix trigger analysis.
- Preserve report ID, capture time, and GPS in S3 object metadata at upload, or create the report record before uploading. Notifications do not contain that custom metadata; fetch it with the object or read the report. Store validated model JSON fields as DynamoDB attributes alongside metadata and the image reference.
- Use stable `report_id` values and conditional database claims for retry-safe processing. S3 events may be duplicated or delivered out of order. A stable ID alone does not prevent duplicate model calls. Recover abandoned claims and skip completed reports.
- Call Bedrock Converse, validate JSON/classification fields, and raise processing errors to trigger retries. Set SDK timeouts and output token limits to fit the Lambda timeout.
- Lambda retries function errors twice. Exhausted asynchronous invocations go to SQS as failure records. Monitor CloudWatch and the queue; manual replay must extract the original event from `requestPayload`. Automatic replay and alarm notifications are not configured.
- No input queue or concurrency cap is configured. For sustained uploads, add an SQS input queue and configure concurrency against Bedrock quotas.

The report table supports lookup by `report_id`. Add secondary indexes after defining flight, pole, classification, and time query patterns for the dashboard.

## Existing resources and cleanup

No import is needed for the existing bucket or table, because they are data sources. If you previously applied the earlier configuration that created storage, do not apply this revision until reviewing the state migration: removing managed resources from configuration can plan their deletion. Detach that old storage from state (after verifying the exact addresses and ownership) if you intend to retain it. Do not import the existing bucket/table into these data source addresses.

Terraform owns the bucket's complete notification configuration once the worker is enabled. Before applying, inspect existing bucket notifications and include any that must be retained in the same `aws_s3_bucket_notification` resource; applying this resource otherwise replaces those notifications. No AWS changes have been made by writing this configuration.

Destroying this stack removes its managed worker resources and bucket notification, but leaves the existing bucket and DynamoDB table intact. The ECR repository cannot be destroyed while populated.
