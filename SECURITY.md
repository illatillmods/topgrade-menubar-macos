# Security Policy

## Supported versions

Security fixes are made on `main` and included in the newest tagged release. Older releases are not
maintained separately.

## Report a vulnerability privately

Please do not open a public issue for a suspected vulnerability.

Use GitHub's **Security** tab and **Report a vulnerability** to send a private report. If private
reporting is unavailable, email `illatillmods@proton.me`.

Include:

- the affected commit or release;
- the macOS version and CPU architecture;
- a minimal reproduction;
- the expected and observed behavior; and
- the likely impact.

Do not include credentials, private Topgrade configuration, hostnames, or other sensitive system
data. Replace them with a sanitized reproducer.

## Project security boundary

The app provides a local, visible way to launch the fixed command `topgrade -r damp`. It does not
provide its own network client, update service, privilege escalation, or unattended scheduler.

Reports are in scope when they concern this repository's installer, local app bundle, login-item
handling, executable-path validation, command construction, terminal handoff, or reminder-state
handling.

Topgrade, terminal emulators, package managers, and commands configured inside Topgrade are separate
projects. Vulnerabilities in those components should be reported to their maintainers. A report is
still welcome here if this launcher handles one of those components in a way that creates an
additional vulnerability.

The project distributes source only. Locally built apps use an ad-hoc signature, not a Developer ID
signature or Apple notarization. No official prebuilt `.app`, DMG, or PKG is distributed by this
repository.
