# Pole image uploads

Place your `.jpeg` or `.webp` pole photos here (each at most 3.75 MiB;
at most 8000 pixels per dimension for Bedrock). The whole directory is
excluded from the API Docker build.
Files with `.jpg`, `.png`, or other extensions are excluded from uploads.
File contents must match their extension; a JPEG saved with a `.webp` name
must be renamed to `.jpeg` before running the uploader.

From `src/GridGuardianAPI`, using an environment with the API's `boto3` dependency:

```sh
python images/upload_images.py --dry-run
python images/upload_images.py --profile YOUR_AWS_PROFILE
```

The default makes **100 total uploads**, numbered 0–99, cycling through the
photos in filename order. Use `--count 101` for 0–100 inclusive, or another
count as needed. Each invocation uses a unique batch folder:
`s3://grid-guardian-images/images/<batch-uuid>/<number>.<extension>`.
Credentials come from the selected profile or the normal AWS credential chain.
The uploader needs `s3:PutObject` on that prefix. Dry runs need no AWS credentials.

Metadata includes `record-id`, the analyzer's actual identity field `report-id`,
`zipcode`, `latitude`, `longitude`, a timezone-aware unique `timestamp`,
`pole-id`, and `flight-id`. Locations cycle through sample Puerto Rico locations
in San Juan, Ponce, Mayaguez, Arecibo, and Caguas. Each upload receives a random
coordinate pair within its ZIP's configured rectangle, with no duplicate pairs
within a batch. Edit `LOCATIONS` in the script to change the ranges. These are
approximate test areas, not official ZIP boundaries. These coordinates and timestamps
are **synthetic test observations**, not actual photo capture data.

The contract was checked against `lambda/handler.py` on `origin/aws-infra`;
the bucket and prefix also match this branch's Terraform outputs and analyzer
IAM policy. Uploads trigger the existing S3 analysis pipeline. The script uploads
only; successful upload does not confirm that asynchronous analysis completed.
