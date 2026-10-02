# Notes for coding agents

- Versioning is SemVer. Bump `version` in `manifest.json` and `package.json`
  together, and add a CHANGELOG entry.
  - PATCH: bug fixes, wording, look-and-feel tweaks.
  - MINOR: new features that keep existing behaviour and settings.
  - MAJOR: removing or changing existing settings or behaviour.
- Randomness must come from `/dev/urandom`. Never use `Math.random()` or a
  plain `byte % n` for password characters; keep the rejection sampling in
  `lib/Gen.js`.
- Passwords must never be written to disk or logs, or passed to a program as a
  command-line argument. Use standard input.
- Do not mention third-party password sites or their authors anywhere in this
  repository.
- Run `npm test` and `omarchy plugin validate .` before any commit.
- Commits use the GitHub noreply email set in this repo's git config.
