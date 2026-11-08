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

The Lambda receives `REPORT_PARTITION_KEY` and `REPORT_SORT_KEY`. The current worker in `../lambda/handler.py` still writes a single `report_id` key and must be updated before deploying it against this schema. It must supply ZIP codes, construct the combined sort key, and move items when their condition changes (primary key attributes cannot be updated in place).
