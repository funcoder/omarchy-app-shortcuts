# App Shortcuts

An Omarchy shell plugin that shows the keyboard shortcuts for the app you're
using. Press **Super + Shift + K** and a cheat sheet opens for the focused
window, with a second tab for your Hyprland keybindings.

It works out what the focused window really is:

- **Web apps** are recognised by site, so X, YouTube or Teams show that site's
  shortcuts rather than Chromium's.
- **Terminals** show the shortcuts of the program in the foreground (nvim,
  lazygit, btop, claude…), or the terminal's own when you're at a prompt.
- **Everything else** is matched to its installed app by window class.

## The shortcut library

The plugin keeps an inventory of every installed app and one shortcut file per
app. When an app has no shortcuts yet, it asks the Claude CLI once and stores
the answer, so opening the sheet afterwards is instant and offline.

- At shell start, and whenever a `.desktop` file is added, changed or removed
  (pacman, flatpak, `omarchy-webapp-install`…), the service rescans installed
  apps and looks up any new ones.
- An app you focus that has no `.desktop` entry (a terminal program, say) is
  added to the inventory and looked up the first time you open the sheet.
- **Neovim** isn't looked up: its keymaps are read from Neovim itself, so
  the sheet shows your LazyVim/plugin/custom mappings grouped by their
  which-key groups. They're re-read whenever `~/.config/nvim` or your installed
  plugins change.
- **Other terminal programs** are often too new or niche for the model to
  know, so their lookup is grounded: the helper collects the program's
  `--help` output, its man page and the keys you have bound in your own config
  under `~/.config/<name>/`. Your config files are never sent anywhere — they
  are parsed here, and only the key combination and the action it runs are
  passed on, each checked against a strict format and length. Bindings changed
  in your config win over the defaults, and the lookup runs again when those
  files change. If that local material doesn't cover the program, the helper
  asks again from the web using only the app's name and package, so nothing
  read off your machine ever reaches a request that can browse.
- Failed lookups are retried after a day. **Ctrl + R** in the sheet looks the
  current app up again.

Files live in `~/.local/share/funcoder-app-shortcuts/`:

| Path | Contents |
| --- | --- |
| `apps.json` | Inventory of installed and discovered apps |
| `shortcuts/<key>.json` | Shortcuts for one app. Edit freely; set `"source": "user"` so it's never replaced |
| `config.json` | Model, concurrency, timeout, ignore patterns |
| `lookup.log` | Lookup failures |

App keys look like `web:x.com`, `tui:nvim` or `app:spotify`.

### Shortcuts included with the plugin

The plugin's `library/` folder holds shortcut files that ship with it, for
apps the model doesn't know well. They use the same format as
`shortcuts/<key>.json`, named after the app key with `:` replaced by `_`
(`app:hype` → `library/app_hype.json`). A bundled file is shown instead of
any looked-up shortcuts, and the app is never looked up. A local file marked
`"source": "user"` still overrides it.

### Settings (`config.json`)

| Key | Default | Meaning |
| --- | --- | --- |
| `model` | `claude-sonnet-5` | Model used for lookups |
| `concurrency` | `3` | Lookups run at once during a sync |
| `timeoutSeconds` | `180` | Per-lookup timeout |
| `retryFailedHours` | `24` | Wait before retrying a failed lookup |
| `claudePath` | `""` | Path to `claude` when it isn't on the shell's `PATH` |
| `ignore` | helper entries | Desktop file names (glob) never looked up |

Lookups run `claude -p` with no MCP servers and no settings files. Web and
desktop apps get no tools, so each is a single answer from the model's
knowledge. For terminal programs the grounded pass also runs with no tools;
only the follow-up web pass gets WebFetch and WebSearch, and it is sent
nothing but the app's identity.

## Requirements

- [Omarchy](https://omarchy.org) 4 (the Quickshell-based shell with plugins) and
  Python 3, both included with Omarchy.
- The [Claude Code](https://claude.com/claude-code) CLI (`claude`), signed in,
  for looking up apps that have no shortcuts yet. Without it the sheet still
  shows your Hyprland bindings, your Neovim keymaps and any shortcut files you
  write yourself.

## Install

```sh
omarchy plugin add https://github.com/funcoder/omarchy-app-shortcuts.git --enable
```

Then bind a key in `~/.config/hypr/bindings.lua` and run `hyprctl reload`:

```lua
o.bind("SUPER + SHIFT + K", "App shortcuts", "omarchy-shell shell toggle funcoder.app-shortcuts '{}'")
```

Update with `omarchy plugin update funcoder.app-shortcuts`.

## Remove

```sh
omarchy plugin remove funcoder.app-shortcuts
rm -rf ~/.local/share/funcoder-app-shortcuts   # optional: the shortcut library
```

Also delete the key binding from `~/.config/hypr/bindings.lua`.

## Development

`./deploy-local.sh` copies a checkout into `~/.config/omarchy/plugins` and
validates it. Re-run it after editing. The shell hot-reloads the copy.

## Command line

```bash
H=~/.config/omarchy/plugins/funcoder.app-shortcuts/shortcuts.py
$H current                 # shortcuts for the focused window
$H list                    # inventory with lookup status
$H show web:x.com          # one app
$H lookup tui:nvim --force # look an app up again now
$H sync                    # rescan and look up anything missing
```
