#!/usr/bin/env python3
"""Focused checks for the release availability gate (no network required)."""
import importlib.util
import os
import subprocess
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("distribution", Path(__file__).with_name("build-distribution.py"))
distribution = importlib.util.module_from_spec(spec)
spec.loader.exec_module(distribution)


class AvailabilityTests(unittest.TestCase):
    def test_default_keeps_functioning_cli_primary(self):
        readme, site, honesty = distribution.render({"dmgAvailable": False, "stableRelease": None})
        self.assertIn(distribution.CLI, site)
        self.assertIn(distribution.CLI, readme)
        self.assertNotIn('href="' + distribution.URL, site)
        self.assertIn("v0.1.0", honesty)

    def test_signed_stable_release_gets_ordinary_download_link(self):
        readme, site, honesty = distribution.render({"dmgAvailable": True, "stableRelease": "v0.2.0"})
        self.assertIn('href="' + distribution.URL + '"', site)
        self.assertIn(distribution.URL, readme)
        self.assertIn("Applications", site)
        self.assertIn("461 MB", site)
        self.assertIn("notarized release", honesty)
        self.assertNotIn(distribution.CLI, site)

    def test_prerelease_or_missing_release_cannot_enable_download(self):
        for release in [None, "", "v0.2.0-rc.1", "main"]:
            with self.assertRaises(ValueError):
                distribution.render({"dmgAvailable": True, "stableRelease": release})

    def test_public_release_preflight_fails_before_any_signing_effect(self):
        names = ["MACOS_CERTIFICATE_P12", "MACOS_CERTIFICATE_PASSWORD", "MACOS_SIGN_IDENTITY",
                 "MACOS_NOTARY_PROFILE", "MACOS_NOTARY_APPLE_ID", "MACOS_NOTARY_TEAM_ID",
                 "MACOS_NOTARY_APP_PASSWORD"]
        env = {key: value for key, value in os.environ.items() if key not in names}
        script = Path(__file__).with_name("release-signed.sh")
        for missing in names:
            result = subprocess.run(["/bin/bash", str(script)], env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("required release secret is absent: " + missing, result.stderr)
            env[missing] = "preflight-placeholder"
        result = subprocess.run(["/bin/bash", str(script)], env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Developer ID Application identity", result.stderr)


if __name__ == "__main__":
    unittest.main()
