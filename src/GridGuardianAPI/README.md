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

## Read API (no authentication)

All data endpoints require a five-digit ZIP or ZIP+4, preserving leading zeros.
They use DynamoDB `Query` with the existing table keys and permissions; there
is no full-table scan or company/account isolation.

| GET route | Response |
| --- | --- |
| `/reports/{zipcode}` | `{items, total, next_offset}`; newest observation first |
| `/analytics/{zipcode}` | Image totals, classification counts, attention count, healthy percentage, GPS coverage, daily counts, latest observation |
| `/map/{zipcode}` | GeoJSON FeatureCollection, with report properties and `[longitude, latitude]` points |

Shared optional query parameters:

- `classification`: `HEALTHY`, `MAINTENANCE`, `DAMAGES`, or `UNASSESSED` (stored null classification).
- `severity`: `NONE`, `MEDIUM`, `HIGH`, or `UNKNOWN`.
- `start`, `end`: inclusive ISO 8601 timestamps **with timezone**; normalized to UTC.
- `flight_id`, `pole_id`: exact matches.

Reports also accept `limit` (1–500, default 100) and `offset` (default 0).
Follow `next_offset` until null. The former ZIP endpoint returned a bare array;
it now returns the pagination envelope. Example:

```text
GET /reports/00901?classification=DAMAGES&limit=25
GET /analytics/00901?start=2026-11-01T00:00:00Z
GET /map/00901?flight_id=flight-1
```

All DynamoDB pages are read before filtering and aggregating. Analytics and
maps cover the full filtered ZIP partition, rather than just the report page.
The classification filter also narrows the DynamoDB sort-key query. Other
filters apply in memory. This is suitable for the initial dataset; large ZIP
partitions will need indexes or precomputed aggregates to stay within Lambda
limits. Offset pagination is not a snapshot if records change between calls.

Only condition-prefixed observation records are returned; `REPORT-` processing
control records are excluded. The sort-key timestamp is used when capture
metadata has no timestamp. Malformed timestamps are excluded. Null, missing,
or invalid GPS values are counted as missing and omitted from the map; ZIP
centers are never substituted. No image download URL is invented: the current
worker records assessment metadata, not an S3 object reference.

Metrics count **image observations**, not unique poles or a complete inventory.
`attention_required` counts MAINTENANCE + DAMAGES; `healthy_percentage` uses
assessed images only and is null if none are assessable. Daily counts use UTC
observation dates and include only dates with observations.

The placeholder `POST /reports` has been removed; the image analyzer owns report
creation. DynamoDB errors return 503 without exposing AWS details. `/health`
is a process health check, not a database connectivity check. CORS allows GET
from all origins by default; optionally set comma-separated `CORS_ORIGINS`.
OpenAPI is available at `/openapi.json`, with interactive documentation at `/docs`.
No gateway or public Lambda URL is provisioned by this change.

## Local verification

```sh
uv sync
uv run python -m unittest discover -v
```

Tests use fake DynamoDB pages to check filtering, pagination, control-record
exclusion, map coordinates, aggregate denominators, validation and failures.
They do not establish live AWS connectivity or deployed HTTP behavior.
