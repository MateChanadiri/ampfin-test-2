# Get the IPA

1. Push this folder to a GitHub repo on branch `main` (keep the hidden `.github` folder).
2. Repo → **Actions** → **Build IPA** (runs on every push, or *Run workflow*).
3. Open the finished run → **Artifacts** → `AmpFin-ipa` → download, unzip, you get `AmpFin.ipa`.
4. The IPA is unsigned: install it with AltStore, SideStore, Sideloadly or TrollStore.

If the build fails, the run has a `build-log` artifact with the full compiler output.
