import copy
import io
import os
import unittest
from unittest.mock import Mock, patch

import boto3
from botocore.exceptions import ClientError
from botocore.stub import ANY, Stubber

import handler


class ReportDestinationTests(unittest.TestCase):
    def setUp(self):
        self.environment = patch.dict(os.environ, {
            "REPORTS_TABLE": "GridGuardian",
            "REPORT_PARTITION_KEY": "zipcode",
            "REPORT_SORT_KEY": "condition-timestamp",
        })
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.metadata = {
            **handler.observation_metadata({"zipcode": "00901"}),
            "upload_event_time": "2026-11-07T20:00:00Z",
        }
        self.analysis = dict(
            infrastructure_detected=True, classification="MAINTENANCE", severity="MEDIUM",
            issues_detected=["Vegetation touching lines"], description="Vegetation interference.",
            recommended_action="Clear vegetation.",
        )

    def test_fetch_recognizes_all_three_image_formats(self):
        with patch.dict(os.environ, {"IMAGES_BUCKET": "grid-guardian-images", "IMAGE_PREFIX": "images/"}):
            for extension, payload, expected in (
                ("jpeg", b"\xff\xd8\xffimage", "jpeg"),
                ("png", b"\x89PNG\r\n\x1a\nimage", "png"),
                ("webp", b"RIFF\x04\x00\x00\x00WEBPimage", "webp"),
            ):
                with self.subTest(format=expected):
                    s3 = Mock()
                    s3.get_object.return_value = {
                        "Body": io.BytesIO(payload), "ContentLength": len(payload),
                        "Metadata": {"zipcode": "00901"},
                    }
                    record = {
                        "eventTime": "2026-11-07T20:00:00Z",
                        "s3": {"bucket": {"name": "grid-guardian-images"}, "object": {"key": f"images/pole.{extension}"}},
                    }
                    result = handler.fetch_image(s3, record)
                    self.assertEqual(result[0], payload)
                    self.assertEqual(result[1], expected)

    def test_zipcode_preserves_leading_zeros_and_rejects_missing_values(self):
        self.assertEqual(self.metadata["zipcode"], "00901")
        for zipcode in ("", "901", "abcde", "00901-extra"):
            with self.subTest(zipcode=zipcode), self.assertRaises(ValueError):
                handler.observation_metadata({"zipcode": zipcode})

    def test_keys_use_schema_and_normalized_capture_timestamp(self):
        metadata = {**self.metadata, "timestamp": "2026-11-07T16:00:00-04:00"}
        claim, report = handler.report_keys(metadata, "source", "HEALTHY")
        self.assertEqual(claim, {"zipcode": "00901", "condition-timestamp": "REPORT-source"})
        self.assertEqual(report, {
            "zipcode": "00901", "condition-timestamp": "HEALTHY-2026-11-07T20:00:00.000000Z",
        })
        for category in ("MAINTENANCE", "DAMAGES", None):
            next_claim, _ = handler.report_keys(metadata, "source", category)
            self.assertEqual(claim, next_claim)

    def test_unassessable_report_uses_event_timestamp(self):
        _, key = handler.report_keys(self.metadata, "source")
        self.assertEqual(key["condition-timestamp"], "UNASSESSED-2026-11-07T20:00:00.000000Z")

    def test_report_and_retry_record_are_written_in_one_valid_transaction(self):
        table = boto3.resource(
            "dynamodb", region_name="us-east-1", aws_access_key_id="testing",
            aws_secret_access_key="testing",
        ).Table("GridGuardian")
        key, _ = handler.report_keys(self.metadata, "source")
        captured = []
        table.meta.client.meta.events.register(
            "before-parameter-build.dynamodb.TransactWriteItems",
            lambda params, **kwargs: captured.append(copy.deepcopy(params)),
        )
        with Stubber(table.meta.client) as stub:
            stub.add_response("transact_write_items", {}, {"TransactItems": ANY})
            handler.save_report(table, key, "owner", "report", "source", self.metadata, self.analysis)
            stub.assert_no_pending_responses()
        transaction = captured[0]["TransactItems"]
        item = transaction[0]["Put"]["Item"]
        self.assertEqual(item["zipcode"], "00901")
        self.assertEqual(item["condition-timestamp"], "MAINTENANCE-2026-11-07T20:00:00.000000Z")
        self.assertEqual(item["report_id"], "report")
        self.assertEqual(transaction[1]["Update"]["Key"]["condition-timestamp"], "REPORT-source")

    def test_upload_claims_stable_key_and_saves_classified_report(self):
        table = Mock()
        event = {"Records": [{"eventSource": "aws:s3", "eventName": "ObjectCreated:Put"}]}
        with patch.object(handler, "services", return_value=(Mock(), Mock(), table)), \
             patch.object(handler, "fetch_image", return_value=(b"image", "jpeg", "report", "source", self.metadata)), \
             patch.object(handler, "analyze_image", return_value=self.analysis):
            result = handler.lambda_handler(event, None)
        self.assertEqual(result["reports"][0]["status"], "COMPLETED")
        self.assertEqual(table.update_item.call_args.kwargs["Key"], {
            "zipcode": "00901", "condition-timestamp": "REPORT-source",
        })
        transaction = table.meta.client.transact_write_items.call_args.kwargs["TransactItems"]
        self.assertEqual(transaction[0]["Put"]["Item"]["classification"], "MAINTENANCE")

    def test_completed_retry_skips_model_and_report_write(self):
        table = Mock()
        table.update_item.side_effect = ClientError(
            {"Error": {"Code": "ConditionalCheckFailedException"}}, "UpdateItem",
        )
        table.get_item.return_value = {"Item": {"source_id": "source", "status": "COMPLETED"}}
        event = {"Records": [{"eventSource": "aws:s3", "eventName": "ObjectCreated:Put"}]}
        with patch.object(handler, "services", return_value=(Mock(), Mock(), table)), \
             patch.object(handler, "fetch_image", return_value=(b"image", "jpeg", "report", "source", self.metadata)), \
             patch.object(handler, "analyze_image") as analyze:
            result = handler.lambda_handler(event, None)
        self.assertEqual(result["reports"][0]["status"], "ALREADY_COMPLETED")
        analyze.assert_not_called()
        table.meta.client.transact_write_items.assert_not_called()


if __name__ == "__main__":
    unittest.main()
