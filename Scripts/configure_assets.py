#!/usr/bin/env python3
"""Write the ignored local Xcode setting from the asset URL environment variable."""
import os
from pathlib import Path
from urllib.parse import urlsplit

url = os.environ.get("BREAKWATER_ASSET_BASE_URL", "").strip()
parts = urlsplit(url)
if (parts.scheme != "https" or not parts.netloc or parts.username or parts.password
        or parts.query or parts.fragment or any(c in url for c in '$" \t\n\r')):
    raise SystemExit("Set BREAKWATER_ASSET_BASE_URL to an HTTPS URL without credentials, query, or fragment")
destination = Path(__file__).resolve().parents[1] / "App/Config.local.xcconfig"
# In xcconfig files, bare // starts a comment; $() expands to the empty string.
destination.write_text("BREAKWATER_ASSET_BASE_URL = " + url.replace("://", ":/$()/", 1) + "\n")
destination.chmod(0o600)
print("Wrote the ignored local Xcode asset setting.")
