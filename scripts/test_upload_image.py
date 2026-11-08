import tempfile
import unittest
from pathlib import Path

from PIL import Image

from upload_image import prepare_image


class ImageFormatTests(unittest.TestCase):
    def test_supported_formats_preserve_original_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            for image_format, extension, content_type in (
                ("JPEG", "jpg", "image/jpeg"),
                ("PNG", "png", "image/png"),
                ("WEBP", "webp", "image/webp"),
            ):
                with self.subTest(format=image_format):
                    path = Path(directory) / f"photo.{extension}"
                    Image.new("RGB", (8, 8), "blue").save(path, format=image_format)
                    payload, actual_extension, actual_type = prepare_image(path)
                    self.assertEqual(payload.read(), path.read_bytes())
                    self.assertEqual((actual_extension, actual_type), (extension, content_type))

    def test_rejects_unsupported_format_even_with_jpeg_extension(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "photo.jpg"
            Image.new("RGB", (8, 8), "blue").save(path, format="BMP")
            with self.assertRaisesRegex(ValueError, "Only PNG, WebP, and JPEG"):
                prepare_image(path)


if __name__ == "__main__":
    unittest.main()
