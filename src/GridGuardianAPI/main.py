"""Read-only inspection API; image analysis is owned by the upload worker."""
from collections import Counter
from datetime import datetime, timezone
from functools import lru_cache
from math import isfinite
import logging
import os
from typing import Literal

import boto3
from boto3.dynamodb.conditions import Key
from botocore.exceptions import BotoCoreError, ClientError
from fastapi import Depends, FastAPI, HTTPException, Path, Query
from fastapi.middleware.cors import CORSMiddleware
from mangum import Mangum

app = FastAPI(title="GridGuardian API", version="0.2.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "*").split(","),
    allow_methods=["GET"], allow_headers=["*"],
)
Classification = Literal["HEALTHY", "MAINTENANCE", "DAMAGES", "UNASSESSED"]
Severity = Literal["NONE", "MEDIUM", "HIGH", "UNKNOWN"]
CLASSES = ("HEALTHY", "MAINTENANCE", "DAMAGES", "UNASSESSED")
ZIP_PATTERN = r"^[0-9]{5}(?:-[0-9]{4})?$"
logger = logging.getLogger(__name__)


@lru_cache
def get_table():
    return boto3.resource("dynamodb").Table(os.getenv("TABLE_NAME", "GridGuardian"))


def parse_time(value):
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("timestamp must include a timezone")
    return parsed.astimezone(timezone.utc)


def filters(
    classification: Classification | None = None,
    severity: Severity | None = None,
    start: str | None = None,
    end: str | None = None,
    flight_id: str | None = None,
    pole_id: str | None = None,
):
    try:
        start_time = parse_time(start) if start else None
        end_time = parse_time(end) if end else None
    except ValueError as exc:
        raise HTTPException(422, "start/end must be ISO 8601 timestamps with timezone") from exc
    if start_time and end_time and start_time > end_time:
        raise HTTPException(422, "start must be before or equal to end")
    return dict(classification=classification, severity=severity, start=start_time,
                end=end_time, flight_id=flight_id, pole_id=pole_id)


def coordinates(report):
    location = report.get("location") or {}
    try:
        lat, lon = float(location["latitude"]), float(location["longitude"])
        if isfinite(lat) and isfinite(lon) and -90 <= lat <= 90 and -180 <= lon <= 180:
            return [lon, lat]
    except (KeyError, TypeError, ValueError, OverflowError):
        pass
    return None


def matching_reports(zipcode, selection, table):
    condition = Key("zipcode").eq(zipcode)
    if selection["classification"]:
        condition &= Key("condition-timestamp").begins_with(selection["classification"] + "-")
    kwargs = {"KeyConditionExpression": condition}
    reports = []
    try:
        while True:
            page = table.query(**kwargs)
            for item in page.get("Items", []):
                key = item.get("condition-timestamp", "")
                # Control items use REPORT-<source_id>; only condition-prefixed items are reports.
                category = next((c for c in CLASSES if key.startswith(c + "-")), None)
                if category is None:
                    continue
                if selection["classification"] and category != selection["classification"]:
                    continue
                if any(selection[f] is not None and item.get(f) != selection[f]
                       for f in ("severity", "flight_id", "pole_id")):
                    continue
                timestamp = item.get("timestamp") or key[len(category) + 1:]
                try:
                    observed = parse_time(timestamp)
                except (ValueError, TypeError, AttributeError):
                    continue
                if selection["start"] and observed < selection["start"]:
                    continue
                if selection["end"] and observed > selection["end"]:
                    continue
                reports.append({**item, "timestamp": observed.isoformat().replace("+00:00", "Z"),
                                "classification": None if category == "UNASSESSED" else category})
            if not page.get("LastEvaluatedKey"):
                break
            kwargs["ExclusiveStartKey"] = page["LastEvaluatedKey"]
    except (BotoCoreError, ClientError):
        logger.exception("Failed to query inspection reports")
        raise HTTPException(503, "Reports are temporarily unavailable")
    reports.sort(key=lambda r: (parse_time(r["timestamp"]), r["condition-timestamp"]), reverse=True)
    return reports


@app.get("/")
def root():
    return {"message": "GridGuardian API running!"}


@app.get("/health")
def health():
    return {"status": "healthy"}


@app.get("/reports/{zipcode}")
def get_reports(
    zipcode: str = Path(pattern=ZIP_PATTERN),
    selection: dict = Depends(filters), table=Depends(get_table),
    limit: int = Query(default=100, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
):
    reports = matching_reports(zipcode, selection, table)
    following = offset + limit
    return {"items": reports[offset:following], "total": len(reports),
            "next_offset": following if following < len(reports) else None}


@app.get("/analytics/{zipcode}")
def analytics(zipcode: str = Path(pattern=ZIP_PATTERN),
              selection: dict = Depends(filters), table=Depends(get_table)):
    reports = matching_reports(zipcode, selection, table)
    counts = Counter(r["classification"] or "UNASSESSED" for r in reports)
    assessed = len(reports) - counts["UNASSESSED"]
    daily = {}
    for report in reports:
        day = report["timestamp"][:10]
        daily.setdefault(day, Counter())[report["classification"] or "UNASSESSED"] += 1
    mapped = sum(coordinates(r) is not None for r in reports)
    return {
        "total_images": len(reports), "assessed_images": assessed,
        "by_classification": {c: counts[c] for c in CLASSES},
        "attention_required": counts["MAINTENANCE"] + counts["DAMAGES"],
        "healthy_percentage": round(100 * counts["HEALTHY"] / assessed, 2) if assessed else None,
        "images_with_location": mapped, "images_without_location": len(reports) - mapped,
        "daily": [{"date": day, **{c: values[c] for c in CLASSES}}
                  for day, values in sorted(daily.items())],
        "latest_observation": reports[0]["timestamp"] if reports else None,
    }


@app.get("/map/{zipcode}")
def map_reports(zipcode: str = Path(pattern=ZIP_PATTERN),
                selection: dict = Depends(filters), table=Depends(get_table)):
    reports = matching_reports(zipcode, selection, table)
    features = []
    for report in reports:
        point = coordinates(report)
        if point is not None:
            features.append({"type": "Feature", "geometry": {"type": "Point", "coordinates": point},
                             "properties": report})
    return {"type": "FeatureCollection", "features": features,
            "total_images": len(reports), "images_without_location": len(reports) - len(features)}


handler = Mangum(app)
