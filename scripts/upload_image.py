"""Upload a local photo with the S3 metadata expected by the analysis worker."""

import argparse
import io
import json
import re
import uuid
from datetime import datetime
from decimal import Decimal, InvalidOperation
from pathlib import Path

import boto3
from PIL import Image


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path, default=Path.home() / "Downloads" / "Utility-Pole-Kris-Tech-Wire.webp", help="PNG, WebP, or JPEG image; uploaded in its original format.")
    parser.add_argument("--zipcode", required=True, help="Actual ZIP code, or an explicitly chosen test ZIP; keep leading zeros.")
    parser.add_argument("--bucket", default="grid-guardian-images")
    parser.add_argument("--prefix", default="images/")
    parser.add_argument("--region", default="us-east-1")
    parser.add_argument("--profile", help="AWS CLI profile; otherwise uses AWS_PROFILE or the default credential chain.")
    parser.add_argument("--timestamp", help="Optional actual capture timestamp with timezone; omitted when unknown.")
    parser.add_argument("--latitude")
    parser.add_argument("--longitude")
    parser.add_argument("--flight-id")
    parser.add_argument("--pole-id")
    parser.add_argument("--dry-run", action="store_true", help="Validate locally without contacting AWS.")
    return parser, parser.parse_args()


def metadata_for(args, report_id):
    if not re.fullmatch(r"[0-9]{5}(?:-[0-9]{4})?", args.zipcode):
        raise ValueError("zipcode must be five digits or ZIP+4")
    metadata = {"report_id": report_id, "zipcode": args.zipcode}
    if args.timestamp:
        if datetime.fromisoformat(args.timestamp.replace("Z", "+00:00")).tzinfo is None:
            raise ValueError("timestamp must include a timezone")
        metadata["timestamp"] = args.timestamp
    if (args.latitude is None) != (args.longitude is None):
        raise ValueError("Supply latitude and longitude together")
    if args.latitude is not None:
        try:
            lat, lon = Decimal(args.latitude), Decimal(args.longitude)
        except InvalidOperation as exc:
            raise ValueError("Invalid GPS coordinates") from exc
        if not lat.is_finite() or not lon.is_finite() or not (-90 <= lat <= 90 and -180 <= lon <= 180):
            raise ValueError("GPS coordinates are out of range")
        metadata.update(latitude=args.latitude, longitude=args.longitude)
    for field in ("flight_id", "pole_id"):
        if getattr(args, field):
            metadata[field] = getattr(args, field)
    for value in metadata.values():
        value.encode("ascii")  # S3 user-defined metadata must be HTTP-header safe.
        if any(ord(character) < 32 or ord(character) == 127 for character in value):
            raise ValueError("Metadata cannot contain control characters")
    if sum(len(key) + len(value) for key, value in metadata.items()) > 2048:
        raise ValueError("S3 user-defined metadata exceeds 2 KiB")
    return metadata


def prepare_image(path):
    """Validate image contents and preserve the original bytes and format."""
    formats = {"JPEG": ("jpg", "image/jpeg"), "PNG": ("png", "image/png"), "WEBP": ("webp", "image/webp")}
    with path.open("rb") as source:
        data = source.read(3_932_161)
    if len(data) > 3_932_160:
        raise ValueError("Image exceeds the worker's 3.75 MiB limit")
    with Image.open(io.BytesIO(data)) as image:
        if image.format not in formats:
            raise ValueError("Only PNG, WebP, and JPEG images are supported")
        extension, content_type = formats[image.format]
        if max(image.size) > 8000:
            raise ValueError("Resize the image to at most 8000 pixels per dimension before uploading")
        image.verify()
    return io.BytesIO(data), extension, content_type


def main():
    parser, args = parse_args()
    report_id = str(uuid.uuid4())
    try:
        metadata = metadata_for(args, report_id)
        if not args.prefix.strip("/"):
            raise ValueError("Use a nonempty upload prefix, normally images/")
        image, extension, content_type = prepare_image(args.image)
    except (ValueError, OSError) as exc:
        parser.error(str(exc))
    key = f"{args.prefix.strip('/')}/{report_id}.{extension}"
    summary = {
        "s3_uri": f"s3://{args.bucket}/{key}", "metadata": metadata,
        "content_type": content_type, "image_bytes": image.getbuffer().nbytes,
        "dry_run": args.dry_run,
    }
    if not args.dry_run:
        session = boto3.Session(profile_name=args.profile, region_name=args.region)
        session.client("s3").upload_fileobj(
            image, args.bucket, key,
            ExtraArgs={"ContentType": content_type, "Metadata": metadata},
        )
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
