# Changelog

## 0.1.1

Fixes.

- Closing the panel while new passwords were still being read could bring them back into the hidden panel. They are now dropped.
- Copying another password just as the clipboard check for the previous one ran could clear the new copy at once, or stop it from being cleared later. Each check now applies only to its own copy.
- With clipboard clearing turned off, the last copied password was kept in memory. It is no longer kept.

## 0.1.0

First release.

- Padlock in the bar that opens a panel with three new random passwords: 64 hexadecimal characters, 63 printable ASCII characters, and 63 letters and digits.
- Random bytes come from `/dev/urandom`; rejection sampling gives every character equal odds.
- Copy by clicking, with `1`–`3`, or with `Enter` on the highlighted row. `r` makes new passwords.
- Copies are passed to `wl-copy` on standard input and marked as sensitive for clipboard managers.
- The clipboard is cleared after 30 seconds (adjustable, or off) if it still holds the copied password.
- Passwords are discarded when the panel closes.
