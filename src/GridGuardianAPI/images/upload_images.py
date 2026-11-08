"""Cycle local pole photos into the analyzer's S3 input prefix."""

import argparse
import json
import random
import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path


BUCKET = "grid-guardian-images"
MAX_IMAGE_BYTES = 3_932_160
# Synthetic observation locations, not the photos' actual capture locations.
# Approximate test rectangles, not official ZIP boundaries.
# Each entry is (ZIP, (min latitude, max latitude), (min longitude, max longitude)).
# ZIP codes remain strings so their leading zeros survive.
LOCATIONS = (
    ("00901", (18.4645, 18.4665), (-66.1120, -66.1050)),  # San Juan
    ("00730", (18.0050, 18.0250), (-66.6250, -66.6050)),  # Ponce
    ("00680", (18.1900, 18.2100), (-67.1450, -67.1250)),  # Mayaguez
    ("00612", (18.4550, 18.4700), (-66.7300, -66.7050)),  # Arecibo
    ("00725", (18.2250, 18.2450), (-66.0600, -66.0400)),  # Caguas
)
CONTENT_TYPES = {
    ".jpeg": "image/jpeg", ".webp": "image/webp",
}


def validate_image(path):
    if path.suffix.lower() not in CONTENT_TYPES:
        raise ValueError(f"{path.name}: only .jpeg and .webp files are allowed")
    if not 0 < path.stat().st_size <= MAX_IMAGE_BYTES:
        raise ValueError(f"{path.name}: image must be nonempty and at most 3.75 MiB")
    with path.open("rb") as source:
        header = source.read(12)
    valid = (
        header.startswith(b"\xff\xd8\xff")
        if path.suffix.lower() == ".jpeg"
        else header.startswith(b"RIFF") and header[8:12] == b"WEBP"
    )
    if not valid:
        raise ValueError(f"{path.name}: contents do not match the image extension")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--count", type=int, default=100, help="Total uploads (default: 100, numbered 0-99).")
    parser.add_argument("--profile", help="AWS profile; otherwise use the standard credential chain.")
    parser.add_argument("--dry-run", action="store_true", help="Validate and print uploads without contacting AWS.")
    args = parser.parse_args()
    if args.count < 1:
        parser.error("--count must be positive")
    directory = Path(__file__).resolve().parent
    images = sorted(p for p in directory.iterdir() if p.is_file() and p.suffix.lower() in CONTENT_TYPES)
    if not images:
        parser.error(f"Add .jpeg or .webp pole photos to {directory}")
    try:
        # Validate every source before starting any uploads.
        for image in images:
            validate_image(image)
    except (OSError, ValueError) as exc:
        parser.error(str(exc))

    s3 = None
    if not args.dry_run:
        import boto3  # Already included in the API dependencies.

        s3 = boto3.Session(profile_name=args.profile, region_name="us-east-1").client("s3")
    batch_id = str(uuid.uuid4())
    started = datetime.now(timezone.utc)
    completed = 0
    used_coordinates = set()
    try:
        for index in range(args.count):
            image = images[index % len(images)]
            zipcode, latitude_range, longitude_range = LOCATIONS[index % len(LOCATIONS)]
            while True:
                latitude = f"{random.uniform(*latitude_range):.7f}"
                longitude = f"{random.uniform(*longitude_range):.7f}"
                coordinates = (latitude, longitude)
                if coordinates not in used_coordinates:
                    used_coordinates.add(coordinates)
                    break
            record_id = f"{batch_id}-{index}"
            key = f"images/{batch_id}/{index}{image.suffix.lower()}"
            metadata = {
                "record-id": record_id,
                "report-id": record_id,
                "zipcode": zipcode,
                "latitude": latitude,
                "longitude": longitude,
                # Distinct times prevent the analyzer's condition-timestamp key
                # from colliding when duplicates receive the same classification.
                "timestamp": (started + timedelta(microseconds=index)).isoformat(timespec="microseconds"),
                "pole-id": f"synthetic-pole-{index}",
                "flight-id": f"synthetic-{batch_id}",
            }
            if s3 is not None:
                s3.upload_file(str(image), BUCKET, key, ExtraArgs={
                    "Metadata": metadata, "ContentType": CONTENT_TYPES[image.suffix.lower()],
                })
            completed += 1
            print(json.dumps({"source": image.name, "s3_uri": f"s3://{BUCKET}/{key}",
                              "metadata": metadata, "dry_run": args.dry_run}), flush=True)
    except Exception as exc:
        print(f"Stopped after {completed}/{args.count} uploads: {exc}", file=sys.stderr)
        return 1
    print(f"{'Planned' if args.dry_run else 'Uploaded'} {completed} images; batch {batch_id}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
