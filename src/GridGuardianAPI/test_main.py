import unittest
from decimal import Decimal
from unittest.mock import Mock, patch

from fastapi import HTTPException
from botocore.exceptions import ClientError
import main


def report(category, day, **extra):
    return {"zipcode": "00901", "condition-timestamp": f"{category}-2026-11-{day:02d}T12:00:00.000000Z",
            "classification": None if category == "UNASSESSED" else category,
            "severity": {"HEALTHY": "NONE", "DAMAGES": "HIGH", "MAINTENANCE": "MEDIUM", "UNASSESSED": "UNKNOWN"}[category],
            **extra}


class ApiTests(unittest.TestCase):
    def test_pagination_control_records_and_chronological_sort(self):
        table = Mock()
        cursor = {"zipcode": "00901", "condition-timestamp": "REPORT-source"}
        table.query.side_effect = [
            {"Items": [report("HEALTHY", 1), {**cursor, "status": "COMPLETED"}], "LastEvaluatedKey": cursor},
            {"Items": [report("DAMAGES", 2)]},
        ]
        result = main.get_reports("00901", main.filters(), table, 1, 0)
        self.assertEqual(result["total"], 2)
        self.assertEqual(result["next_offset"], 1)
        self.assertEqual(result["items"][0]["classification"], "DAMAGES")
        self.assertEqual(table.query.call_args.kwargs["ExclusiveStartKey"], cursor)

    def test_combined_filters_and_timezone_boundaries(self):
        table = Mock()
        table.query.return_value = {"Items": [report("DAMAGES", 2, flight_id="a", pole_id="p"), report("DAMAGES", 3, flight_id="b")]}
        result = main.matching_reports("00901", main.filters(
            classification="DAMAGES", severity="HIGH", start="2026-11-02T08:00:00-04:00",
            end="2026-11-02T12:00:00Z", flight_id="a", pole_id="p"), table)
        self.assertEqual(len(result), 1)

    def test_analytics_and_map_agree(self):
        table = Mock()
        table.query.return_value = {"Items": [
            report("HEALTHY", 1, location={"latitude": Decimal("18.4"), "longitude": Decimal("-66.1")}),
            report("DAMAGES", 2), report("UNASSESSED", 3),
            report("MAINTENANCE", 4, location={"latitude": 100, "longitude": 0}),
        ]}
        result = main.analytics("00901", main.filters(), table)
        self.assertEqual(result["attention_required"], 2)
        self.assertEqual(result["healthy_percentage"], 33.33)
        self.assertEqual(result["images_without_location"], 3)
        geo = main.map_reports("00901", main.filters(), table)
        self.assertEqual(geo["features"][0]["geometry"]["coordinates"], [-66.1, 18.4])
        self.assertEqual(len(geo["features"]), 1)

    def test_empty_analytics(self):
        table = Mock()
        table.query.return_value = {"Items": []}
        result = main.analytics("00901", main.filters(), table)
        self.assertIsNone(result["healthy_percentage"])
        self.assertEqual(result["total_images"], 0)

    def test_invalid_date_ranges(self):
        for params in ({"start": "2026-11-01"}, {"start": "garbage"},
                       {"start": "2026-11-02T00:00:00Z", "end": "2026-11-01T00:00:00Z"}):
            with self.assertRaises(HTTPException) as raised:
                main.filters(**params)
            self.assertEqual(raised.exception.status_code, 422)

    def test_database_failure(self):
        table = Mock()
        table.query.side_effect = ClientError({"Error": {"Code": "AccessDeniedException", "Message": "private"}}, "Query")
        with self.assertLogs(main.logger, "ERROR"):
            with self.assertRaises(HTTPException) as raised:
                main.matching_reports("00901", main.filters(), table)
        self.assertEqual(raised.exception.status_code, 503)
        self.assertNotIn("private", raised.exception.detail)

    def test_image_link_uses_report_reference_and_version(self):
        table, s3 = Mock(), Mock()
        table.query.return_value = {"Items": [report("HEALTHY", 1,
            image_s3_bucket="grid-guardian-images", image_s3_key="images/photo.webp", image_version_id="v1")]}
        s3.generate_presigned_url.return_value = "https://s3.example/signed"
        with patch.dict("os.environ", {"IMAGE_BUCKET": "grid-guardian-images", "IMAGE_PREFIX": "images/"}):
            result = main.report_image("00901", "HEALTHY-2026-11-01T12:00:00Z", table, s3)
        self.assertEqual(result, {"url": "https://s3.example/signed", "expires_in": 300})
        s3.head_object.assert_called_once_with(Bucket="grid-guardian-images", Key="images/photo.webp", VersionId="v1")
        self.assertEqual(s3.generate_presigned_url.call_args.kwargs["ExpiresIn"], 300)

    def test_image_rejects_missing_or_unapproved_references(self):
        for item in (None, report("HEALTHY", 1), report("HEALTHY", 1,
                     image_s3_bucket="other-bucket", image_s3_key="images/photo.webp")):
            table, s3 = Mock(), Mock()
            table.query.return_value = {"Items": [item] if item else []}
            with self.assertRaises(HTTPException) as raised:
                main.report_image("00901", "HEALTHY-time", table, s3)
            self.assertEqual(raised.exception.status_code, 404)
            s3.generate_presigned_url.assert_not_called()

    def test_image_read_failure_does_not_return_broken_link(self):
        table, s3 = Mock(), Mock()
        table.query.return_value = {"Items": [report("HEALTHY", 1,
            image_s3_bucket="grid-guardian-images", image_s3_key="images/photo.webp")]}
        s3.head_object.side_effect = ClientError({"Error": {"Code": "AccessDenied"}}, "HeadObject")
        with self.assertLogs(main.logger, "ERROR"):
            with self.assertRaises(HTTPException) as raised:
                main.report_image("00901", "HEALTHY-time", table, s3)
        self.assertEqual(raised.exception.status_code, 503)
        s3.generate_presigned_url.assert_not_called()

    def test_openapi_contract(self):
        schema = main.app.openapi()
        self.assertNotIn("post", schema["paths"].get("/reports", {}))
        for path in ("/reports/{zipcode}", "/analytics/{zipcode}", "/map/{zipcode}"):
            params = {p["name"] for p in schema["paths"][path]["get"]["parameters"]}
            self.assertTrue({"zipcode", "classification", "start", "end", "flight_id", "pole_id", "severity"} <= params)


if __name__ == "__main__":
    unittest.main()
