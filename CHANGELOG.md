# Changelog

## 1.0.0
- First release as part of Pylos addons on Pylos Core. Core's contract version is "core" 1.0.
- Settings page: one category "Pylos" in the game options, one page per addon, built from `ns.options`; a status page lists every addon and what to update.
- Saved data with defaults and a shape number (`_schema`) for migrations.
- Minimap button and slash command (left-click action, `options` sub-command).
- Texts (`ns.L`) and a shared set of colors.
- `ns.SetAlert` and the `alertDims` option: a hint on the minimap button.
- An addon whose required service is missing or too old is switched off (`ns.off`) and the chat and the status page say what to update.
- The stable surface is listed in README.md.
