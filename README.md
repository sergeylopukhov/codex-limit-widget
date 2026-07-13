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

Codex Limit Widget shows your remaining 5-hour and weekly Codex limits, reset times, plan, and usage stats without keeping the Codex desktop app open. It runs in the menu bar, refreshes in the background, and keeps the macOS widget updated.

## What It Shows

- Remaining 5-hour and weekly limits.
- Reset time for each limit.
- Current Codex plan.
- Usage stats: total tokens, peak day, last day, streak, and max turn.
- Compact or detailed menu bar status.
- One macOS widget in Small, Medium, and Large sizes.
- Two designs: Dark and Beige.

## Install

1. Download the latest `.dmg` from [GitHub Releases](https://github.com/sergeylopukhov/codex-limit-widget/releases/latest).
2. Open it and drag `Codex Limit Widget.app` to `Applications`.
3. Launch the app.

Requirements:

- macOS 14 or newer.
- Codex CLI installed and authenticated.

## Add The Widget

Open the macOS widget gallery, find `Codex Limit Widget`, and choose Small, Medium, or Large.

The widget design is controlled in the app settings. Choose `Dark` or `Beige`; already-added widgets update while the app is running.

## Menu Bar

The menu bar item can show detailed limits or a compact percent indicator. Click it to open a popover with both limit windows, reset times, freshness, and settings.

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

Use settings to choose the window design, menu bar mode, and percent source.

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

## Privacy

Codex Limit Widget reads data from the local Codex CLI session and stores a small local snapshot for widgets. It does not send data to its own server.

## Uninstall

Quit Codex Limit Widget and delete the app from Applications.

If the widget still appears after deleting the app, restart your Mac and remove any other local copies of `Codex Limit Widget.app`.
