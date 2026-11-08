# Releasing Tether

A release is a DMG plus a Sparkle appcast on a GitHub release. The app checks the appcast of the **latest published** release (`https://github.com/Ethan-Hess/Tether/releases/latest/download/appcast.xml`), and the Homebrew cask points at the same DMG, so **publishing a release is what ships it** to both. This repository is also the Homebrew tap (`Casks/tether.rb`).

## The flow

1. Update `VERSION`, write `RELEASE_NOTES.md` (optional; otherwise GitHub generates notes), merge to `main`.
2. Push a tag that matches: `git tag v0.2.0 && git push origin v0.2.0`.
3. `release.yml` runs:
   - **build** (no secrets): checks the tag against `VERSION`, runs the tests, builds `Tether.app` with the runtime embedded (downloaded and checked against its pinned SHA-256), runs `scripts/verify-app.sh`, makes the DMG, and attests its build provenance.
   - **publish** (waits for your approval in the `release` environment, the only place the update-signing key exists): signs the appcast (with deltas from the previous release) and creates a **draft** release containing the DMG, `appcast.xml` and any `.delta` files.
4. Review the draft: download the DMG, check it opens and runs (Open Anyway applies to ad-hoc builds), look at the notes.
5. **Publish** the release. That switches the update feed and triggers `homebrew.yml`, which commits the new `Casks/tether.rb` (version and the DMG's SHA-256) to `main` of this repository.

Until you publish, nothing changes for users. A full run takes roughly 15 to 30 minutes on GitHub's runners, mostly DMG compression.

### Dry run

Run **Actions → Release → Run workflow** on any branch. It builds, verifies and packs everything and leaves the DMG as a 7-day artifact. It never touches the signing key and creates no release.

### Pull request checks

`ci.yml` runs on every PR and push to `main`: the test suite on macOS 15 and 26, a release build of every product, a bundle build with `verify-app.sh`, a `cask` job that renders the cask template and runs `brew style` and `brew audit` on it (and on the real `Casks/tether.rb` once a release has created it), and linting of scripts, JSON and workflows. Branch protection on `main` requires `test (macos-15)`, `test (macos-26)`, `app-bundle` and `lint`. Run **CI → Run workflow** with *install_cask* ticked to also install the published cask on a runner and uninstall it again.

## One-time setup

**Update-signing key.** Sparkle installs an update only if its EdDSA signature matches the public key inside the app.

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys      # creates the key; the private half goes to your login keychain
```

- The **public** key lives in `Packaging/sparkle_public_key.txt` (already done; it isn't secret).
- **Back up the private key** somewhere safe (a password manager). If it's lost, installed copies can never accept an update again.

**Put the key where CI can use it.** The workflow reads it from the `release` environment secret `SPARKLE_PRIVATE_KEY`. Sparkle's exporter only writes to a new file, so use a private temporary folder and delete it straight away:

```sh
tmp="$(mktemp -d)"; chmod 700 "$tmp"
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x "$tmp/key"
gh secret set SPARKLE_PRIVATE_KEY --env release < "$tmp/key"
rm -rf "$tmp"
```

Anyone who can approve the `release` environment and push a workflow to a `v*` tag can sign an update that every install will accept, so the environment is restricted:

```sh
printf '{"reviewers":[{"type":"User","id":%s}],"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}' \
  "$(gh api user --jq .id)" | gh api -X PUT repos/Ethan-Hess/Tether/environments/release --input -
gh api -X POST repos/Ethan-Hess/Tether/environments/release/deployment-branch-policies -f name='v*' -f type=tag
```

**Cask token.** `homebrew.yml` commits the cask to `main` with `TAP_TOKEN`: a *fine-grained personal access token* created in GitHub's web UI (Settings → Developer settings), limited to **this repository** with *Contents: read and write*. Then `gh secret set TAP_TOKEN` (a repository secret). It has to be your own token: `main` is protected by required checks, and a bot commit can't have passed them yet, so the push relies on you being an administrator and on branch protection not being enforced for administrators. Anyone with this token can push to `main`; keep it to this one repository, give it an expiry, and renew it.

**Signing (optional until you have a certificate).** Without a Developer ID, builds are ad-hoc signed and users approve "Open Anyway" once. Updates installed by Sparkle don't carry the download quarantine, so that approval isn't repeated per update. Homebrew installs the same ad-hoc app quarantined, so brew users see the same prompt (the cask doesn't strip it). Because the tap is this repository rather than a `homebrew-tether` repository, users tap it with its URL (`brew tap ethan-hess/tether https://github.com/Ethan-Hess/Tether`) and install with the full name (`brew install --cask ethan-hess/tether/tether`). Homebrew 6+ only loads casks from trusted taps; the full-name install trusts just that cask, and `brew trust --cask ethan-hess/tether/tether` does it explicitly. The official `homebrew-cask` requires a notarized app, so submitting there waits for a certificate.

To sign and notarize once you have a *Developer ID Application* certificate (the "Apple Distribution" certificate is for the App Store and can't notarize a download), use `SIGN_IDENTITY` and `NOTARY_PROFILE` with `scripts/release.sh`; wiring them into CI also needs the certificate imported on the runner. That path has **not been run yet**.

## Releasing from your own Mac

`scripts/release.sh 0.2.0` does the same build, DMG and appcast locally (key from your keychain), and prints the `gh release create` command instead of publishing. The pieces are separate scripts, used by both paths: `package-app.sh`, `verify-app.sh`, `make-dmg.sh`, `make-appcast.sh`.

## Rolling back a bad release

- **Not yet published:** delete the draft.
- **Published:** Sparkle only moves forward, so ship a fixed newer version. To stop *new* downloads right away, unpublish or delete the release (the feed then falls back to the previous release) and revert the cask commit on `main`. Copies that already updated stay updated.

## Testing an update

The updater needs a click-through, so this part is manual:

```sh
mkdir -p build/test/feed
scripts/package-app.sh --no-runtime --version 0.1.0 --build 100 --out build/test/v1
scripts/package-app.sh --no-runtime --version 0.1.1 --build 101 --out build/test/v2
scripts/make-dmg.sh build/test/v1/Tether.app build/test/feed/Tether-0.1.0.dmg
scripts/make-dmg.sh build/test/v2/Tether.app build/test/feed/Tether-0.1.1.dmg
APPCAST_URL_PREFIX=http://localhost:8123/ scripts/make-appcast.sh build/test/feed 0.1.1
(cd build/test/feed && python3 -m http.server 8123) &
# install v1 to /Applications, then:
TETHER_FEED_URL=http://localhost:8123/appcast.xml open -a Tether     # Tether menu → Check for Updates…
```

`TETHER_FEED_URL` only overrides *where* the feed is read; the update still has to carry a valid signature from your key. (If macOS's network rules block plain `http://localhost`, serve the folder over https instead.) What has been checked so far: the appcast carries valid signatures and a delta, and a modified file fails `sign_update --verify`. Installing an update through the dialogs has not been exercised.

## After release

- Confirm `https://github.com/Ethan-Hess/Tether/releases/latest/download/appcast.xml` serves the new appcast.
- Confirm the cask landed: `Casks/tether.rb` on `main`, then `brew tap ethan-hess/tether https://github.com/Ethan-Hess/Tether && brew trust --cask ethan-hess/tether/tether && brew info --cask ethan-hess/tether/tether`.
- Old DMGs and deltas stay in `build/release/old_updates/` on a local release; don't upload those.
