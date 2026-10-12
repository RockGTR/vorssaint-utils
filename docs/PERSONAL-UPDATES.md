# Personal builds and updates

The [Personal upstream build workflow](../.github/workflows/personal-upstream.yml)
checks `vorssaint/vorssaint-utils`'s `main` branch daily at 11:23 UTC. It builds
the personal branch `personal/scroll-and-bluetooth`, retaining the independent
trackpad scrolling and selective Bluetooth sleep changes. It also runs when
`main` or the personal branch receives a push, and can be run manually with
**Run workflow**. Select **rebuild** to rebuild unchanged source.

It merges upstream in the runner checkout, then builds, self-tests, runs unit
tests, and packages a DMG. A merge conflict produces a failed Actions run with
the conflicting filenames in the run summary. Resolve those files on the
personal branch and push the resolution. Build or test failures also stop
publication. The previous published release remains available.

After validation, a separate publishing job pushes the tested merge to the
personal branch and creates a fork release. The branch push is never forced;
a concurrent source change stops publication instead of being overwritten.
Each release contains `Vorssaint-Personal.dmg` and `build-info.json` recording
the exact source and upstream commits. The workflow checks that GitHub's
asset digest matches the built DMG before making the release public.

## Enable it on GitHub

1. Push these changes to `RockGTR/vorssaint-utils` on both the personal branch
   and `main`. Scheduled workflows must exist on the default branch (`main`).
2. Enable Actions for the fork if GitHub has disabled them. Ensure repository
   policy permits the publishing job's `contents: write` permission. No Apple
   certificates, custom access token, or third-party secrets are required.
3. Run **Personal upstream build**, or let a push trigger the first run.
4. Install its DMG once. Older installed builds still check upstream until
   they are replaced with a build containing this updater change.

The tracked Info.plist sets `VorssaintUpdateRepository` to
`RockGTR/vorssaint-utils`. The updater fetches that fork's latest public release
and requires the exact personal DMG name, a personal build tag, a fork download
URL, and GitHub's SHA-256 asset digest. It never falls back to upstream releases.
No GitHub credentials are stored in the app. The fork and its releases must be
public for these unauthenticated update checks.

The workflow stamps versions as `3.4.1+personal.1791760000`, using a UTC timestamp
as the build number. This makes a rebuild discoverable even when upstream's
version stays the same. Personal update selection compares build numbers;
official update selection retains normal semantic version comparison. Developer
builds remain excluded from real updates.

## Signing and installation

Personal CI builds are ad-hoc signed and are not Apple notarized. The personal
installer verifies the exact downloaded DMG checksum before mounting it, then
checks the version, fork metadata, bundle identifier, and bundle signature
before replacing the app. It retains the existing installer backup/rollback
and administrator-prompt behavior. Official bundles without fork metadata
continue to require the original Developer ID signature and Gatekeeper check.

The app keeps `com.vorssaint.utils` and the existing preferences. Because the
personal CI signature changes between builds, macOS Accessibility and Screen
Recording permissions may need to be granted again. The first downloaded build
may need macOS's **Open Anyway** approval. These are personal fork builds, not
official releases from the original maintainer.

To build the same update-enabled bundle locally:

```sh
VORSSAINT_PERSONAL_BUILD_NUMBER=$(date -u +%s) ./build.sh
./Tools/make-dmg.sh
```

Test merge behavior without changing the real repository:

```sh
python3 Tests/test_personal_upstream.py
```
