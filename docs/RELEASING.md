# Releasing DocForge

DocForge ships a **per-user Windows installer** from GitHub Releases. The app
can update itself from the same release feed. This document covers versioning,
the release checklist, installer behaviour and signing.

## Versioning

DocForge starts at **1.0.0** and uses semantic versions:

| Change | Version | Example |
| --- | --- | --- |
| Bug fixes, small polish | patch | 1.0.0 → 1.0.1 → 1.0.2 |
| New features, larger changes | minor | 1.0.2 → 1.1.0 |
| Breaking changes | major | 1.1.0 → 2.0.0 |

The Flutter build number (`1.0.1+3`) increases on every public release. It is
not part of the installer filename or the Git tag.

Version numbers are stored in three places and must always agree:

| Source | Used for |
| --- | --- |
| `pubspec.yaml` | Flutter, and the exe's product/file version (CMake → `Runner.rc`) |
| `lib/core/app_info.dart` | About UI, update comparison, GitHub tag |
| `installer/docforge.iss` | Inno Setup default when ISCC is run without `/D` |

`test/app_info_test.dart` fails if they drift, and
`tool/package_windows.ps1` refuses to package mismatched sources.

### Bumping the version

```powershell
python tool/bump_version.py 1.0.1
flutter analyze
flutter test
```

The script increments the build number automatically (or accepts `--build N`)
and updates all three sources. Commit the result with the release changes.

```powershell
git add -A
git commit -m "release: DocForge 1.0.1"
git tag v1.0.1
git push origin main --follow-tags
```

The tag **must** be `v<version>`. CI fails the build when the tag and
`pubspec.yaml` disagree.

## What CI publishes

Pushing a `v*` tag runs `.github/workflows/build.yml`:

1. **Analyze and test** on Linux (`flutter analyze`, `flutter test`).
2. **Windows x64** on `windows-latest`:
   - builds with `--build-name <version> --build-number <build>`;
   - installs Inno Setup and runs `tool/package_windows.ps1 -SkipBuild`;
   - uploads `DocForge-Setup-<version>.exe`, `SHA256SUMS.txt` and a portable
     zip as workflow artifacts.
3. **Release** (tags only): verifies the tag, then runs `gh release create`
   with the installer and checksums, generated notes, and `--latest`.

The in-app updater scans `/releases?per_page=20` and takes the newest release
whose tag is `vX.Y.Z`, so the rolling `engines` release and drafts are ignored.
`--latest` keeps the public Releases page pointing at the newest app build.
If a build fails, fix it
and move the tag (`git tag -f v1.0.1 && git push --force origin v1.0.1`) only
if that version was never downloaded by users.

### Release notes

GitHub generates notes from commits. Write clear commit subjects before
tagging, or edit the release body afterwards. The app shows a trimmed version
of the body in **Settings → About DocForge**.

## Installer behaviour

`installer/docforge.iss` builds a **per-user** installer:

- `PrivilegesRequired=lowest` — never asks for administrator rights, never
  triggers UAC, and cannot interfere with how other apps elevate.
- `DefaultDirName={localappdata}\Programs\DocForge` — no writes to
  `Program Files` or `HKLM`.
- `AppId` stays constant, and `UsePreviousAppDir=yes`, so newer installers
  upgrade the existing copy in place instead of installing side by side.
- `CloseApplications=yes` and `AppMutex=DocForge.SingleInstance` let the
  installer close a running DocForge cleanly.
- Start menu shortcut, optional desktop shortcut, uninstaller, and the app icon
  on the exe, shortcuts and installer.
- Uninstalling removes the program folder but keeps settings, history and
  documents (they live under `%APPDATA%` and the output folder).

The Windows job also uploads a portable zip as a workflow artifact
(`DocForge-<version>-windows-x64.zip`, available from the Actions run while it
is retained). It is not attached to the GitHub release and does not self-update.

## App updates

**Settings → About DocForge → Check for updates**:

1. Fetches the GitHub release list and picks the newest app version tag.
2. Compares its tag with the running version.
3. Downloads `DocForge-Setup-<version>.exe` into `%TEMP%`.
4. Verifies the byte count and SHA-256 against `SHA256SUMS.txt`.
5. Starts the installer and exits DocForge so it can replace the executable.

Nothing is downloaded until the user clicks. If the checksum asset is missing,
the update is refused rather than run unverified. Update checks are subject to
GitHub's unauthenticated rate limit (60/hour per IP), which is fine for manual
checks.

## Local packaging

Prerequisites:

- Flutter 3.47.7+ with the Windows desktop toolchain
  (Visual Studio **Desktop development with C++**).
- [Inno Setup 6](https://jrsoftware.org/isdl.php) (`ISCC.exe`). The packaging
  script looks in the default install locations, or pass
  `-InnoCompiler <path>`.

```powershell
# Build + installer + checksums
powershell -ExecutionPolicy Bypass -File tool/package_windows.ps1

# Reuse an existing build\windows\x64\runner\Release
powershell -ExecutionPolicy Bypass -File tool/package_windows.ps1 -SkipBuild
```

Output:

```
dist\DocForge-Setup-1.0.0.exe
dist\SHA256SUMS.txt
```

Test the installer as a normal user: install, launch from the Start menu,
verify **Settings → About DocForge** shows the right version, then run the same
installer again and confirm it upgrades in place without a UAC prompt.

## Code signing (follow-up)

Builds are currently unsigned. Windows SmartScreen shows a "Windows protected
your PC" prompt on first run until the installer earns reputation or is signed.

To sign later:

1. Obtain an Authenticode code-signing certificate (OV or, preferably, EV).
2. Sign `docforge.exe` and the installer. Inno Setup can sign both: configure
   a `SignTool` in the IDE (or `ISCC /S<name>=...`) and add
   `SignTool=<name>` under `[Setup]` in `installer/docforge.iss`.
3. Store the certificate and password as CI secrets and extend the Windows job
   with the signing steps.

Signing does not change the installer layout; it only removes the warning.

## Release checklist

- [ ] `python tool/bump_version.py <version>` (patch or minor as appropriate)
- [ ] Update user-facing notes / README if behaviour changed
- [ ] `flutter analyze` and `flutter test` pass
- [ ] Commit, tag `v<version>`, push `main` and the tag
- [ ] Wait for the **Publish GitHub release** job
- [ ] Download the installer from the release and install it as a normal user
- [ ] Check **Settings → About DocForge** shows the new version
- [ ] Run the previous installer over it to confirm in-place upgrade (optional)
