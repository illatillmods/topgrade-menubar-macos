# Topgrade Menubar for macOS

[![CI](https://github.com/illatillmods/topgrade-menubar-macos/actions/workflows/ci.yml/badge.svg)](https://github.com/illatillmods/topgrade-menubar-macos/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A small native menu-bar launcher and 24-hour reminder for
[Topgrade](https://github.com/topgrade-rs/topgrade). Click the icon to run the fixed command
`topgrade -r damp` in a visible terminal window. The icon turns red when no session has started yet
or the stored last-started time is at least 24 hours old.

The app is deliberately local and narrow: no telemetry, no network client, no background updater,
and no extra terminal emulator dependency. It can use the Terminal.app built into macOS, and
Topgrade is its only third-party runtime dependency.

## Features

- Runs Topgrade interactively, where its commands and prompts remain visible.
- Uses `damp` mode, which prints each updater command and then executes it.
- Shows a red menu-bar reminder after 24 hours.
- Remembers a compatible terminal detected during installation and provides a terminal chooser.
- Starts at login through Apple's native login-item API, with a menu toggle.
- Keeps reminder, terminal-preference, and error state local to the Mac.
- Builds entirely from inspectable Swift and shell source.

The reminder records that a Topgrade terminal session actually started. A session still counts as
used when Topgrade later exits with an error; the timestamp is not a claim that every updater
succeeded. It is also not an update-availability check: the app does not inspect package
repositories, and a red or normal icon does not prove whether updates are available.

## Requirements

- macOS 13 Ventura or newer.
- Topgrade available as an executable in your normal shell.
- Apple Command Line Tools for the one-time local build (`git`, Swift, and code-signing tools).

If the Command Line Tools are missing, macOS will offer to install them when a developer command is
used. You can also request them explicitly with `xcode-select --install`, then rerun the installer.
They are a build prerequisite, not a runtime dependency.

## Install

If Topgrade is already installed, installation is three commands and does not use `sudo`:

```sh
git clone https://github.com/illatillmods/topgrade-menubar-macos.git
cd topgrade-menubar-macos
Scripts/install.sh
```

With Homebrew, a new Topgrade installation plus the app takes four commands:

```sh
brew install topgrade
git clone https://github.com/illatillmods/topgrade-menubar-macos.git
cd topgrade-menubar-macos
Scripts/install.sh
```

Topgrade may also be installed through another supported method. The installer locates it and
confirms that it is an absolute, executable file rather than assuming an Apple Silicon or Intel
Homebrew path. It does not authenticate Topgrade's provenance; install Topgrade from a source you
trust.

The local build also records only the absolute directory entries from the installer's `PATH`. This
lets an app started from the menu bar find the same package-manager tools without saving the rest of
your shell environment. Rerun the installer after making substantial changes to your `PATH`.

The installer runs the checks, builds `~/Applications/Topgrade Menu.app`, applies a local ad-hoc
signature, verifies the bundle, registers it as a login item, and opens it. If macOS reports that
login startup requires approval, right-click the menu-bar icon and choose **Approve Launch at
Login…**.

Do not run the installer with `sudo`. It installs only for the current user.

## Terminal selection

When the installer can identify the terminal from which it was invoked, it saves that compatible
terminal as the initial choice. The right-click menu lets you change the choice later or return to
**Automatic**.

Automatic selection prefers a recognized non-Apple terminal registered by macOS LaunchServices to
open the bundled `.command` file. If Terminal.app is the registered handler but exactly one
recognized third-party terminal is installed, it selects that terminal; otherwise it falls back to
Terminal.app. A compatible third-party terminal can register itself for executable shell scripts;
for example, current Ghostty releases offer **Set Ghostty as Default Terminal App**.

The chooser recognizes installed copies of Terminal, Ghostty, iTerm2, Warp, kitty, WezTerm, and
Alacritty. The app uses a terminal's native launch interface where that is needed to keep the
Topgrade session visible; otherwise it opens the `.command` file through macOS. Unknown terminals
still have the built-in Terminal fallback. Merely installing a terminal does not necessarily make
it compatible or selected.

## Use

- Left-click the circular update icon to run `topgrade -r damp`.
- Right-click to see the last-run state, choose a terminal, control launch at login, mark the
  reminder due, or quit.
- Hold Command and drag the icon to position it among the other menu-bar items.

Read-only diagnostic status is available from the installed app:

```sh
"$HOME/Applications/Topgrade Menu.app/Contents/MacOS/TopgradeMenu" --status
```

This does not run Topgrade.

## Update

The app does not download or install its own updates. Update from the source checkout:

```sh
cd topgrade-menubar-macos
git pull --ff-only
Scripts/install.sh
```

The installer preserves the existing launch-at-login choice and keeps a recoverable copy of the
previous app before replacement.

## Uninstall

From the source checkout:

```sh
cd topgrade-menubar-macos
Scripts/uninstall.sh
```

The uninstaller unregisters login startup, quits the app, and moves the application to Trash. It
does not remove Topgrade or the cloned repository. See the script's output for the optional command
to remove the non-sensitive local app preferences as well.

## Source-built distribution

This project intentionally publishes source rather than downloadable `.app`, DMG, or PKG binaries.
Each user builds and ad-hoc-signs their own local copy. Signature verification can detect later
changes to the assembled bundle, but an ad-hoc signature does not identify the author and is not
Apple notarization.

No Apple Developer membership is used. Do not disable Gatekeeper or remove quarantine attributes to
run a prebuilt copy from elsewhere; this repository does not distribute one. The reviewed source and
the local build are the trust boundary.

## Security model

The menu-bar app itself has no network client and never asks for administrator privileges. Topgrade
and the package managers it invokes do use the network and may request `sudo` interactively when an
update genuinely requires it.

The launch command is fixed as `topgrade -r damp`. No menu input is interpolated into a shell
command. However, Topgrade intentionally supports custom commands, remote hosts, and configuration
files. This launcher does not audit or restrict that configuration. Review your Topgrade config and
use `topgrade --dry-run` when you want to inspect planned steps without executing them.

See [SECURITY.md](SECURITY.md) for private vulnerability reporting and the supported security
boundary.

## Development and verification

```sh
swift run TopgradeMenuChecks
Scripts/build-app.sh
```

The checks cover reminder boundaries and the fixed launch contract. The build script also validates
the property list and local code signature. Automated checks do not run a real Topgrade upgrade,
approve a login item, log out and back in, or visually inspect the menu-bar icon.

## License and upstream project

This project is licensed under the [MIT License](LICENSE).

Topgrade is a separate project licensed under GPL-3.0-or-later. Topgrade Menubar for macOS is an
unofficial companion and is not affiliated with or endorsed by the Topgrade maintainers.
