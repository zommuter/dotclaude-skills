# Flameshot broken on XFCE — `org.freedesktop.portal.Desktop` / Screenshot timeout

**Machine:** zomni (Manjaro XFCE, X11). Confirmed 2026-06-29.

Flameshot v14 (Qt6) routes screenshots through xdg-desktop-portal even on X11.
Two independent breakages on XFCE, with two different symptoms:

## Symptom 1 — `could not locate the org.freedesktop.portal.Desktop service`

The portal's systemd user unit has `Requisite=graphical-session.target`, but **XFCE
never activates `graphical-session.target`** (it's `RefuseManualStart`, only pulled in
by a proper systemd-managed DE session). So the unit refuses to start and on-demand
D-Bus activation fails.

- A systemd drop-in clearing `Requisite=` does **not** work — this systemd build does
  not honor the empty-string reset for that dependency.
- Fix: launch the portal directly from XFCE autostart. File
  `~/.config/autostart/xdg-desktop-portal.desktop`:

  ```ini
  [Desktop Entry]
  Type=Application
  Name=XDG Desktop Portal (XFCE workaround)
  Exec=sh -c 'dbus-update-activation-environment --systemd DISPLAY XAUTHORITY; exec /usr/lib/xdg-desktop-portal'
  OnlyShowIn=XFCE;
  X-XFCE-Autostart-Override=true
  ```

## Symptom 2 — `Screenshot portal timed out after 30 seconds`

Portal now runs, but has **no Screenshot backend**. XFCE's `xfce-portals.conf` routes
`org.freedesktop.impl.portal.Screenshot=xapp;gtk`, but only the `gtk` backend was
installed — and `gtk.portal` is `UseIn=gnome` and lists **no** Screenshot interface.

- Fix: `pamac install xdg-desktop-portal-xapp` (the XFCE/Cinnamon/MATE backend that
  actually provides Screenshot, Wallpaper, Background, Settings…).
- After install, the running portal must be restarted to discover the new backend;
  on next login the autostart handles it (the portal spawns `xdg-desktop-portal-xapp`
  automatically).

## Verify

```sh
busctl --user list | grep 'org.freedesktop.portal.Desktop '   # owned, not just activatable
pgrep -af xdg-desktop-portal-xapp                             # backend running
```

Then a normal (GUI) flameshot capture works. Note: launching the portal from a
detached/non-interactive shell needs `setsid -f` or the harness/shell reaps it on exit;
a headless `flameshot full -p file.png` may still time out for lack of a full session
context even when the interactive GUI capture works.

## If it recurs on cartmanjaro (or any Manjaro XFCE box)

Same two steps: the autostart `.desktop` + `xdg-desktop-portal-xapp`. Both are
idempotent and machine-independent.
