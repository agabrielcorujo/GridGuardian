# Reports table

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
