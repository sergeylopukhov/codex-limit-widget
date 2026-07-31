# Codex Limit Widget

<p align="center">
  <a href="README.md"><strong>English</strong></a> · <a href="README.ru.md">Русский</a>
</p>

<div align="center">
  <img src="assets/screenshots/readme/beige-large.png" width="520" alt="Codex Limit Widget large widget in Beige design">

  <p>
    A macOS menu bar app and desktop widget for keeping Codex limits visible.
  </p>

  <p>
    <a href="https://github.com/sergeylopukhov/codex-limit-widget/releases/latest"><img alt="Download latest release" src="https://img.shields.io/badge/download-latest_release-222222?style=for-the-badge"></a>
    <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-777777?style=for-the-badge">
    <img alt="WidgetKit" src="https://img.shields.io/badge/WidgetKit-enabled-6f8f5f?style=for-the-badge">
  </p>
</div>

Codex Limit Widget keeps the limit windows returned for your account visible in the macOS menu bar and on the desktop. Weekly-only accounts see weekly data without a stray 5-hour label or empty 5-hour space. Accounts that still have the 5-hour window see both limits. Reset times, plan details, and usage history remain available without keeping Codex Desktop open.

While the app is running, it refreshes the local data once per minute and passes the latest snapshot to WidgetKit.

## What It Shows

- Every limit window available to the account: weekly, plus 5-hour when Codex provides it.
- Reset date and time for each available limit.
- Current Codex plan.
- Usage stats: total tokens, peak day, last day, streak, and max turn.
- Compact or detailed menu bar status.
- One macOS widget in Small, Medium, and Large sizes.
- Two designs: Dark and Beige.
- A visible notice and an `Update now` button when a newer release is available.

## Install

1. Download the latest `.dmg` from [GitHub Releases](https://github.com/sergeylopukhov/codex-limit-widget/releases/latest).
2. Open it and drag `Codex Limit Widget.app` to `Applications`.
3. Launch the app.

Starting with version 1.1.8, later releases can be installed from inside the app.

Requirements:

- macOS 14 or newer.
- Codex CLI installed and authenticated.

## Add The Widget

Open the macOS widget gallery, find `Codex Limit Widget`, and choose Small, Medium, or Large.

The widget design is controlled in the app settings. Choose `Dark` or `Beige`; already-added widgets update while the app is running.

## Menu Bar

The menu bar item can show detailed limits or a compact percent indicator. Click it to open a popover with the available limit windows, reset times, data freshness, and settings. When a new release is ready, an update arrow appears next to the menu bar value and the popover shows an update card.

<table>
  <tr>
    <td width="50%" align="center">
      <img src="assets/screenshots/readme/popover-window-beige.png" width="100%" alt="Menu bar popover in Beige design"><br>
      <sub>Beige</sub>
    </td>
    <td width="50%" align="center">
      <img src="assets/screenshots/readme/popover-window-dark.png" width="100%" alt="Menu bar popover in Dark design"><br>
      <sub>Dark</sub>
    </td>
  </tr>
</table>

## Widgets

<table>
  <tr>
    <td width="40%" align="center">
      <img src="assets/screenshots/readme/beige-large.png" width="100%" alt="Large Codex Limit Widget in Beige design"><br>
      <sub>Large</sub>
    </td>
    <td width="38%" align="center">
      <img src="assets/screenshots/readme/beige-medium.png" width="100%" alt="Medium Codex Limit Widget in Beige design"><br>
      <sub>Medium</sub>
    </td>
    <td width="22%" align="center">
      <img src="assets/screenshots/readme/beige-small.png" width="100%" alt="Small Codex Limit Widget in Beige design"><br>
      <sub>Small</sub>
    </td>
  </tr>
</table>

<table>
  <tr>
    <td width="40%" align="center">
      <img src="assets/screenshots/readme/dark-large.png" width="100%" alt="Large Codex Limit Widget in Dark design"><br>
      <sub>Large</sub>
    </td>
    <td width="38%" align="center">
      <img src="assets/screenshots/readme/dark-medium.png" width="100%" alt="Medium Codex Limit Widget in Dark design"><br>
      <sub>Medium</sub>
    </td>
    <td width="22%" align="center">
      <img src="assets/screenshots/readme/dark-small.png" width="100%" alt="Small Codex Limit Widget in Dark design"><br>
      <sub>Small</sub>
    </td>
  </tr>
</table>

## Settings

Use settings to choose the window design and menu bar mode. When both limit windows are available, you can also choose which one supplies the compact percent. The Updates section shows the installed version, the latest check result, and the update action.

<table>
  <tr>
    <td width="50%" align="center">
      <img src="assets/screenshots/readme/settings-window-beige.png" width="100%" alt="Settings window with Beige design selected"><br>
      <sub>Beige</sub>
    </td>
    <td width="50%" align="center">
      <img src="assets/screenshots/readme/settings-window-dark.png" width="100%" alt="Settings window with Dark design selected"><br>
      <sub>Dark</sub>
    </td>
  </tr>
</table>

## Updates

A check against the latest public GitHub Release runs at startup and every four hours after that. You can also run a check from Settings at any time.

If a newer version is available, the menu bar, popover, and Settings all show it. Press `Update now` to download the official macOS ZIP. Before installation, verification covers the SHA-256 digest published by GitHub, bundle identifier, version, and code signature. After verification, the copy in `Applications` is replaced and the new version opens.

If the `Applications` folder cannot be changed, use `Open release page` and install the DMG manually.

## Privacy

Codex usage and limit data stay on your Mac. The app reads the local Codex CLI session and stores a small snapshot for widgets. Update checks include the installed version number in the request to the public GitHub Releases API; they do not include Codex usage data. The project has no server of its own.

## Uninstall

Quit Codex Limit Widget and delete the app from Applications.

If the widget still appears after deleting the app, restart your Mac and remove any other local copies of `Codex Limit Widget.app`.
