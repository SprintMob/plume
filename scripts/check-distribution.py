#!/usr/bin/env python3
"""Focused checks for the release availability gate (no network required)."""
import importlib.util
import base64
import json
import tempfile
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



class ReleaseAuthenticationTests(unittest.TestCase):
    COMMON = {
        "MACOS_CERTIFICATE_P12": base64.b64encode(b"dummy certificate contents").decode(),
        "MACOS_CERTIFICATE_PASSWORD": "dummy-p12-password-private-marker",
        "MACOS_SIGN_IDENTITY": "Developer ID Application: Dummy (DUMMYTEAM)",
    }
    API = {
        "MACOS_NOTARY_KEY_ID": "dummy-key-id-private-marker",
        "MACOS_NOTARY_ISSUER_ID": "dummy-issuer-private-marker",
        "MACOS_NOTARY_KEY_P8": "dummy-private-key-line-one\ndummy-private-key-line-two\n",
    }
    LEGACY = {
        "MACOS_NOTARY_APPLE_ID": "dummy-apple-id@example.invalid",
        "MACOS_NOTARY_TEAM_ID": "dummy-team-private-marker",
        "MACOS_NOTARY_APP_PASSWORD": "dummy-app-password-private-marker",
    }
    SCRIPT = Path(__file__).with_name("release-signed.sh")

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="plume-auth-tests-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "effects.jsonl"
        # All release-effect commands fail if reached during preflight. Nothing
        # invokes a host keychain, compiler or Apple endpoint in these tests.
        for command in ["mktemp", "security", "openssl", "xcrun", "swift", "codesign", "ditto"]:
            self.stub(command, "import os, pathlib, sys\npathlib.Path(os.environ['AUTH_TEST_LOG']).write_text(sys.argv[0])\nsys.exit(93)\n")

    def stub(self, command, body):
        path = self.bin / command
        path.write_text("#!/usr/bin/env python3\n" + body)
        path.chmod(0o755)

    def run_script(self, values, preflight=True):
        env = {key: value for key, value in os.environ.items() if not key.startswith("MACOS_")}
        env.update(values)
        env.update(PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                   RUNNER_TEMP=str(self.root), AUTH_TEST_LOG=str(self.log))
        result = subprocess.run(["/bin/bash", str(self.SCRIPT)] + (["--preflight"] if preflight else []),
                                env=env, capture_output=True, text=True)
        for value in values.values():
            for line in value.splitlines():
                if line:
                    self.assertNotIn(line, result.stdout + result.stderr)
        return result

    def assert_preflight_failure(self, values, missing):
        for preflight in [True, False]:
            with self.subTest(preflight=preflight, missing=missing):
                result = self.run_script(values, preflight=preflight)
                self.assertEqual(result.returncode, 1)
                self.assertIn("required release secret is absent: " + missing, result.stderr)
                self.assertFalse(self.log.exists(), "Preflight invoked a release-effect command")
                self.assertEqual(list(self.root.glob("plume-signing.*")), [])

    def test_api_auth_selected_even_with_complete_legacy(self):
        result = self.run_script(self.COMMON | self.API | self.LEGACY)
        self.assertEqual(result.returncode, 0)
        self.assertIn("notary authentication: api", result.stdout)
        self.assertFalse(self.log.exists())

    def test_legacy_auth_selected_with_empty_github_api_envs(self):
        empty_api = {key: "" for key in self.API}
        result = self.run_script(self.COMMON | self.LEGACY | empty_api)
        self.assertEqual(result.returncode, 0)
        self.assertIn("notary authentication: apple-id", result.stdout)
        self.assertFalse(self.log.exists())

    def test_every_missing_common_credential_fails_in_both_auth_modes(self):
        for auth in [self.API, self.LEGACY]:
            for missing in self.COMMON:
                for empty in [False, True]:
                    values = self.COMMON | auth
                    if empty:
                        values[missing] = ""
                    else:
                        del values[missing]
                    self.assert_preflight_failure(values, missing)

    def test_every_missing_api_credential_fails_without_fallback(self):
        for missing in self.API:
            for empty in [False, True]:
                values = self.COMMON | self.API | self.LEGACY
                if empty:
                    values[missing] = ""
                else:
                    del values[missing]
                self.assert_preflight_failure(values, missing)

    def test_one_api_value_with_complete_legacy_is_rejected(self):
        for present, value in self.API.items():
            values = self.COMMON | self.LEGACY | {present: value}
            missing = next(key for key in self.API if key != present)
            self.assert_preflight_failure(values, missing)

    def test_every_missing_legacy_credential_fails(self):
        for missing in self.LEGACY:
            for empty in [False, True]:
                values = self.COMMON | self.LEGACY
                if empty:
                    values[missing] = ""
                else:
                    del values[missing]
                self.assert_preflight_failure(values, missing)

    def test_invalid_identity_fails_before_effects_and_never_leaks(self):
        for auth in [self.API, self.LEGACY]:
            for preflight in [True, False]:
                result = self.run_script(self.COMMON | auth | {"MACOS_SIGN_IDENTITY": "invalid-private-marker"},
                                         preflight=preflight)
                self.assertEqual(result.returncode, 1)
                self.assertIn("Developer ID Application identity", result.stderr)
                self.assertFalse(self.log.exists())

    def install_store_credentials_mocks(self):
        # Only dummy files are written in our test temp directory. The real
        # keychain/Apple commands are replaced; a simulated store failure halts
        # before bundle.sh and tests the existing cleanup trap as well.
        (self.bin / "mktemp").unlink()
        self.stub("openssl", "print('dummy-keychain-password')\n")
        self.stub("security", "import json, os, pathlib, sys\nwith pathlib.Path(os.environ['AUTH_TEST_LOG']).open('a') as log:\n log.write(json.dumps({'command': 'security', 'args': sys.argv[1:]}) + '\\n')\n")
        self.stub("xcrun", r"""import json, os, pathlib, stat, sys
args = sys.argv[1:]
record = {'command': 'xcrun', 'args': args}
if '--key' in args:
    key = pathlib.Path(args[args.index('--key') + 1])
    record['key_mode'] = stat.S_IMODE(key.stat().st_mode)
    record['work_mode'] = stat.S_IMODE(key.parent.stat().st_mode)
    record['key_contents'] = key.read_text()
with pathlib.Path(os.environ['AUTH_TEST_LOG']).open('a') as log:
    log.write(json.dumps(record) + '\n')
sys.exit(72)
""")

    def test_api_default_profile_private_raw_key_and_failure_cleanup(self):
        self.install_store_credentials_mocks()
        result = self.run_script(self.COMMON | self.API, preflight=False)
        self.assertEqual(result.returncode, 72)
        records = [json.loads(line) for line in self.log.read_text().splitlines()]
        store = next(record for record in records if record['command'] == 'xcrun')
        self.assertEqual(store['args'][:3], ['notarytool', 'store-credentials', 'plume-notary'])
        self.assertIn('--key-id', store['args'])
        self.assertIn('--issuer', store['args'])
        self.assertNotIn('--apple-id', store['args'])
        self.assertEqual(store['key_mode'], 0o600)
        self.assertEqual(store['work_mode'], 0o700)
        self.assertEqual(store['key_contents'], self.API['MACOS_NOTARY_KEY_P8'])
        keychain = Path(store['args'][store['args'].index('--keychain') + 1])
        key = Path(store['args'][store['args'].index('--key') + 1])
        self.assertEqual(key.parent, keychain.parent)
        self.assertFalse(key.parent.exists())
        self.assertTrue(any(record['command'] == 'security' and record['args'][0] == 'delete-keychain'
                            for record in records))

    def test_legacy_explicit_profile_is_preserved_without_api_key_file(self):
        self.install_store_credentials_mocks()
        # Profile names are intentionally absent from output too.
        values = self.COMMON | self.LEGACY | {'MACOS_NOTARY_PROFILE': 'explicit-legacy-profile'}
        result = self.run_script(values, preflight=False)
        self.assertEqual(result.returncode, 72)
        records = [json.loads(line) for line in self.log.read_text().splitlines()]
        store = next(record for record in records if record['command'] == 'xcrun')
        self.assertEqual(store['args'][:3], ['notarytool', 'store-credentials', 'explicit-legacy-profile'])
        self.assertIn('--apple-id', store['args'])
        self.assertIn('--team-id', store['args'])
        self.assertIn('--password', store['args'])
        self.assertNotIn('--key', store['args'])
        self.assertNotIn('key_contents', store)
        self.assertEqual(list(self.root.glob('plume-signing.*')), [])

    def test_workflow_uses_shared_preflight_and_exposes_both_auth_paths(self):
        workflow = (self.SCRIPT.parent.parent / '.github/workflows/release.yml').read_text()
        self.assertIn('run: ./scripts/release-signed.sh --preflight', workflow)
        self.assertNotIn('for name in MACOS_CERTIFICATE_P12', workflow)
        for name in self.API | self.LEGACY:
            self.assertEqual(workflow.count('${{ secrets.' + name + ' }}'), 2)


class ReleaseKeychainTests(unittest.TestCase):
    def setUp(self):
        self.auth = ReleaseAuthenticationTests()
        self.auth.setUp()
        self.addCleanup(self.auth.doCleanups)
        self.fixture = self.auth.root / "repository with spaces"
        scripts = self.fixture / "scripts"
        scripts.mkdir(parents=True)
        # Run the production lifecycle in an isolated repository. Only the
        # unrelated absolute plist-reader path is routed to a mock too.
        self.auth.SCRIPT = scripts / "release-signed.sh"
        self.auth.SCRIPT.write_text(ReleaseAuthenticationTests.SCRIPT.read_text()
                                   .replace("/usr/libexec/PlistBuddy", "plistbuddy"))
        self.auth.root = self.auth.root / "runner temp with spaces"
        self.auth.root.mkdir()
        self.state_path = self.auth.root / "mock-state.json"
        self.original = ["/Users/Dummy/Keychains/login with spaces.keychain-db",
                         "/Library/Keychains/System.keychain"]
        self.external = ["/Users/Dummy/Keychains/external addition.keychain-db"]
        self.write_state()
        (self.auth.bin / "mktemp").unlink()
        mock = r"""import json, os, pathlib, signal, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
state_path = pathlib.Path(os.environ['MOCK_KEYCHAIN_STATE'])
state = json.loads(state_path.read_text())
with pathlib.Path(os.environ['AUTH_TEST_LOG']).open('a') as log:
    log.write(json.dumps({'command': name, 'args': args, 'search': state['search'][:]}) + chr(10))
def finish(status=0):
    state_path.write_text(json.dumps(state))
    sys.exit(status)
if name == 'security':
    command = args[0]
    if command == 'create-keychain':
        state['temporary'] = args[-1]
        pathlib.Path(args[-1]).write_text('dummy keychain file')
    elif command == 'list-keychains':
        if '-s' in args:
            state['search'] = args[args.index('-s') + 1:]
            if state['mode'] == 'registration-failure' and state['temporary'] in state['search']:
                finish(68)
        elif state['mode'] == 'malformed-list':
            print('not a quoted keychain path')
        else:
            for path in state['search']:
                print('    "' + path + '"')
    elif command == 'delete-keychain':
        # Deliberately leave the mock search list alone: cleanup must remove
        # TEMP itself instead of tests accidentally relying on deletion doing it.
        if state['mode'] in ['interrupt', 'terminate']:
            # A repeated signal during cleanup must not leave private files.
            os.kill(os.getppid(), signal.SIGTERM)
        pathlib.Path(args[1]).unlink(missing_ok=True)
    elif command == 'default-keychain':
        finish(97)
    elif command not in ['set-keychain-settings', 'unlock-keychain', 'import', 'set-key-partition-list']:
        finish(98)
elif name == 'openssl':
    print('dummy-keychain-password')
elif name == 'xcrun':
    if args[:2] in [['notarytool', 'store-credentials'], ['notarytool', 'submit']]:
        if state['temporary'] not in state['search']:
            finish(77)
    if args[:2] == ['notarytool', 'submit']:
        print('<plist version="1.0"><dict><key>status</key><string>Accepted</string></dict></plist>')
elif name == 'codesign' and '--sign' in args:
    keychain = args[args.index('--keychain') + 1]
    if keychain != state['temporary'] or keychain not in state['search']:
        finish(77)
    if not state.get('external_updated'):
        state['search'].extend(state['external'])
        if state.get('external_remove'):
            state['search'].remove(state['external_remove'])
        state['external_updated'] = True
    if state['mode'] == 'codesign-failure':
        finish(71)
    if state['mode'] in ['interrupt', 'terminate']:
        state_path.write_text(json.dumps(state))
        os.kill(os.getppid(), signal.SIGINT if state['mode'] == 'interrupt' else signal.SIGTERM)
elif name == 'ditto':
    pathlib.Path(args[-1]).write_text('dummy ZIP')
elif name == 'plistbuddy':
    print('Accepted')
elif name == 'shasum':
    print('0' * 64 + '  ' + args[-1])
finish()
"""
        for command in ["security", "openssl", "xcrun", "codesign", "ditto", "spctl", "shasum", "plistbuddy"]:
            self.auth.stub(command, mock)
        (scripts / "bundle.sh").write_text("#!/bin/bash\nset -e\nmkdir -p dist/Plume.app\nprintf dummy > dist/Plume.app/executable\n")
        (scripts / "dmg.sh").write_text("""#!/bin/bash
set -e
keychain=""
while [ "$#" -gt 0 ]; do
  case "$1" in --keychain) keychain="$2"; shift 2 ;; *) shift ;; esac
done
printf dummy > dist/plume-macos-arm64.dmg
codesign --keychain "$keychain" --sign "$MACOS_SIGN_IDENTITY" dist/plume-macos-arm64.dmg
""")
        (scripts / "bundle.sh").chmod(0o755)
        (scripts / "dmg.sh").chmod(0o755)

    def write_state(self, mode="success", original=None, external_remove=None):
        self.state_path.write_text(json.dumps({
            "search": self.original if original is None else original,
            "external": self.external, "mode": mode,
            "default": self.original[0], "external_remove": external_remove,
        }))

    def run_release(self):
        result = self.auth.run_script(self.auth.COMMON | self.auth.API
                                      | {"MOCK_KEYCHAIN_STATE": str(self.state_path)}, preflight=False)
        self.state = json.loads(self.state_path.read_text())
        self.records = [json.loads(line) for line in self.auth.log.read_text().splitlines()]
        return result

    def assert_cleanup(self, expected):
        self.assertEqual(self.state['search'], expected)
        self.assertEqual(self.state['default'], self.original[0])
        self.assertFalse(any(record['command'] == 'security' and record['args'][0] == 'default-keychain'
                             for record in self.records))
        self.assertFalse(Path(self.state['temporary']).exists())
        self.assertFalse(Path(self.state['temporary']).parent.exists())
        self.assertEqual(list(self.auth.root.glob('plume-signing.*')), [])

    def test_registered_before_notary_and_signing_then_preserves_external_additions(self):
        result = self.run_release()
        self.assertEqual(result.returncode, 0, result.stderr)
        temporary = self.state['temporary']
        sets = [record['args'][4:] for record in self.records
                if record['command'] == 'security' and record['args'][:4] == ['list-keychains', '-d', 'user', '-s']]
        self.assertEqual(sets, [[temporary] + self.original, self.original + self.external])
        signs = [record for record in self.records if record['command'] == 'codesign' and '--sign' in record['args']]
        self.assertEqual(len(signs), 2)
        notary = [record for record in self.records if record['command'] == 'xcrun' and record['args'][0] == 'notarytool']
        self.assertEqual(len(notary), 3)
        for record in signs + notary:
            self.assertIn(temporary, record['search'])
        self.assertIn(' ', temporary)
        self.assert_cleanup(self.original + self.external)

    def test_failure_during_signing_removes_only_temp_and_preserves_external_additions(self):
        self.write_state(mode="codesign-failure")
        result = self.run_release()
        self.assertEqual(result.returncode, 71)
        self.assert_cleanup(self.original + self.external)

    def test_failed_registration_is_cleaned_even_if_command_partially_changed_list(self):
        self.write_state(mode="registration-failure")
        result = self.run_release()
        self.assertEqual(result.returncode, 68)
        self.assert_cleanup(self.original)

    def test_handled_interrupt_and_termination_clean_up_current_list(self):
        for mode, code in [('interrupt', 130), ('terminate', 143)]:
            with self.subTest(signal=mode):
                self.write_state(mode=mode)
                if self.auth.log.exists():
                    self.auth.log.unlink()
                result = self.run_release()
                self.assertEqual(result.returncode, code)
                self.assert_cleanup(self.original + self.external)

    def test_cleanup_preserves_external_removal_instead_of_restoring_snapshot(self):
        self.write_state(external_remove=self.original[1])
        result = self.run_release()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_cleanup([self.original[0]] + self.external)

    def test_quoted_spaces_and_metacharacters_are_literal_without_eval(self):
        marker = self.auth.root / 'must-not-exist'
        special = '/Users/Dummy/Keychains/quoted "value" \\ $(touch ' + str(marker) + '); space.keychain-db'
        original = self.original + [special]
        self.write_state(original=original)
        result = self.run_release()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_cleanup(original + self.external)
        self.assertFalse(marker.exists())

    def test_empty_original_list_is_restored_without_unbound_array_errors(self):
        self.external = []
        self.write_state(original=[])
        result = self.run_release()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_cleanup([])

    def test_malformed_list_fails_without_overwriting_unrelated_entries(self):
        self.write_state(mode="malformed-list")
        result = self.run_release()
        self.assertEqual(result.returncode, 1)
        self.assertIn('could not parse', result.stderr)
        self.assertFalse(any(record['command'] == 'security' and '-s' in record['args'] for record in self.records))
        self.assert_cleanup(self.original)


if __name__ == "__main__":
    unittest.main()
