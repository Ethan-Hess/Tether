# Uninstalling Tether

Tether keeps everything it creates in one place and never installs background services, login items or kernel extensions.

## In the app

**Settings → Storage → Remove Tether Data…** lets you choose what to delete and shows how big each part is:

| Part | What it is |
|------|------------|
| Bottles | Every bottle: installed games, Steam and **your saves inside them**. This can't be undone. |
| Wine runtimes | Runtimes you installed and imported components (the built-in runtime stays with the app). |
| Cache | Downloaded artwork. Safe to delete. |
| Settings and profiles | Your preferences and any game profiles you wrote. |

Stop every bottle first; the app refuses while something is running.

Then drag **Tether.app** to the Trash.

If you installed with Homebrew: `brew uninstall --cask tether` removes the app. Add `--zap` to also delete the data listed below, **including your bottles** (installed games and saves), so only do that if you mean it.

## By hand

Quit Tether, then delete:

```sh
rm -rf ~/Library/Application\ Support/Tether          # bottles, runtimes, cache, settings
rm -f  ~/Library/Preferences/dev.tether.Tether.plist  # app preferences (including update checks)
rm -rf ~/Library/Caches/dev.tether.Tether             # system caches
rm -rf ~/Library/Saved\ Application\ State/dev.tether.Tether.savedState
```

and the app itself (`/Applications/Tether.app`). If you started Tether with `TETHER_HOME`, delete that folder instead of the first path.

Games installed by Steam inside a bottle live inside that bottle, so they go with it. Steam's cloud saves are on Valve's servers and are unaffected.
