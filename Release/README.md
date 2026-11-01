# Publishing Cable

Publish a stable GitHub release tagged `vX.Y.Z` to build, notarize, and distribute Cable automatically. Drafts and prereleases do not publish updates.

## One-time setup

The repository is public, the `release` GitHub environment exists, and `SPARKLE_PRIVATE_KEY` is configured as a repository secret.

Add these secrets to the [release environment](https://github.com/stephenson/Cable/settings/environments):

| Secret | Value |
| --- | --- |
| `CERTIFICATE_P12` | Base64-encoded Developer ID Application certificate and private key. |
| `CERTIFICATE_PASSWORD` | Password protecting the P12. |
| `APPLE_ID` | Apple account authorized to notarize. |
| `APPLE_TEAM_ID` | Developer team ID matching the certificate. |
| `APPLE_APP_PASSWORD` | Apple app-specific password for notarization. |

Required reviewers and deployment tag restrictions are recommended for the environment. No personal access token is needed; the workflow uses `GITHUB_TOKEN`.

Keep the existing Sparkle key. Its public key is `SUPublicEDKey` in `Info.plist`; the private key must never be committed. Back it up securely. To export the runner’s existing key after a local build:

```bash
build/.sparkle/bin/generate_keys --account inc.phone.cable -x /secure/path/key
```

## Publish

1. Tag the finished commit with a higher stable version, such as `v1.2.2`, and push the tag.
2. Publish its GitHub release.
3. Wait for the **Release** workflow to succeed.

The workflow sets both app versions from the tag, signs and notarizes the app, and uploads `Cable.dmg`, `Cable.zip`, and Sparkle’s signed `appcast.xml`.

Only then does it update the stable feed on the `updates` branch:

https://raw.githubusercontent.com/stephenson/Cable/updates/appcast.xml

The previous feed stays available during builds and failures. The first successful release creates the branch; CI never modifies `main`. Sparkle uses HTTPS and verifies the update archive’s EdDSA signature before installation.

## Recovery

Retry failed workflow runs. Existing assets are reused and verified, not overwritten. Regressions and conflicting same-version feeds are rejected; an identical completed retry is a no-op. Correct a published bad release with a higher version rather than moving tags or editing assets. Avoid manually changing releases or the feed while CI runs.

Temporary signing files and the CI keychain are removed after the run. Versions before the updater-enabled release require one manual installation.

## Local signing

Set `CODE_SIGN_IDENTITY` to a Developer ID Application identity and `NOTARY_PROFILE` to a configured `notarytool` keychain profile when running `bash build.sh`. Without signing credentials, builds are ad-hoc signed and unnotarized.
