# Pylos Core

<img src=".github/logo.png" width="96" align="right" alt="Pylos Core">

The base that every Pylos addon builds on. It holds no game data and does nothing on its own. For an addon of the family it provides:

- the settings page: one category "Pylos" in the game options, one page per addon below it, built from a data table (`ns.options`);
- saved data with defaults and a shape number (`_schema`) for migrations;
- the minimap button and the slash command;
- texts (`ns.L`) and a small set of shared colors;
- an on/off check: an addon that needs a service which is missing or too old is switched off (`ns.off`), and the chat and the "Pylos" page say what to update.

Core's contract version is "core" 1.0 (the service `core`, version `1.0`). The contract version is not the package version.

## Announcing an addon

Every addon of the family announces itself in its first file, `Init.lua`, and then describes its menu in `ns.options`:

```lua
local addonName, ns = ...

-- requires: the services (and their versions) this addon was written against
if not PylosCore.Module(addonName, ns, { requires = { core = "1.0" } }) then return end
-- from here on ns.L exists; every other file starts with: if ns.off then return end
```

```lua
-- Core.lua of the addon (any file loaded before its ADDON_LOADED)
local addonName, ns = ...
if ns.off then return end

ns.options = {
    savedVariable = "MyAddonDB",             -- must also stand under ## SavedVariables in the TOC
    title = "My Addon",
    intro = ns.L["One sentence on what the addon does."],
    icon = "Interface\\Icons\\INV_Misc_Gear_01",
    slash = "/myaddon",
    slashLeftClick = true,                   -- /myaddon = left-click, /myaddon options = options
    defaults = { minimapAngle = 225 },       -- may override Core's defaults
    onLeftClick = function() print("clicked") end,
    leftClickText = ns.L["Do the thing"],
    onLoad = function(db)                    -- once, after the menu is built
        ns.eventFrame = CreateFrame("Frame")
    end,

    { type = "checkbox", key = "hint", label = ns.L["Show a hint"], default = true,
        tooltip = ns.L["More text for the tooltip."] },
    { type = "color", key = "hintColor", label = ns.L["Hint color"], default = "blue" },
    { type = "header", label = ns.L["More"] },
    { type = "minimap" },
    { type = "page", label = ns.L["List"], init = function(frame) end },
}
```

`PylosCore.Module(name, ns, info)` returns `true` when the addon may run. It returns `false` and sets `ns.off = true` when a service in `info.requires` is missing or older than asked. Announcing the same addon twice counts once.

## Stable surface (core 1.0)

A name is stable from the day the first published addon needs it. Stable names may only be added to, never removed, renamed or changed in meaning, except with a new major version.

### Function

| Name | Meaning |
|---|---|
| `PylosCore.Module(addonName, ns, { requires = { core = "1.0" } })` | Announces an addon. Returns a boolean. |

### Fields Core puts into `ns`

| Name | When | Meaning |
|---|---|---|
| `ns.off` | right after `PylosCore.Module` | `true` when the addon must not run. |
| `ns.L` | right after `PylosCore.Module` | The addon's texts. Writable. A missing key falls back to Core's texts, then to the key itself. |
| `ns.GetColor` | at the addon's `ADDON_LOADED`, when the options are built | `ns.GetColor(key)` returns an array `{ r, g, b }` for a color key. White for an unknown key. The array is only read: never change it. |
| `ns.SetAlert` | at the addon's `ADDON_LOADED`, when the options are built | `ns.SetAlert(on)` shows or hides the hint on the minimap button. |

### Reserved names

The set of fields Core writes into `ns` is frozen with 1.0. Core writes only: `off`, `L`, `db`, `minimapButton`, `GetColor`, `SetOption`, `IsModifierHeld`, `SetAlert`. It never overwrites a field the addon set itself (`db` excepted). Core reads `ns.options`. Anything new comes as a field of `ns.options` or as a function on `PylosCore`, never as another `ns` field. Do not use these names for your own `ns` fields.

Only `off`, `L`, `GetColor` and `SetAlert` are stable. `db`, `minimapButton`, `SetOption` and `IsModifierHeld` are reserved but provisional (see below).

### `ns.options`: head

| Field | Meaning |
|---|---|
| `savedVariable` | Name of the addon's saved variable. Required. It must stand under `## SavedVariables` in the TOC. Without it the options are not built and the status page shows a problem. |
| `title` | Display name. Default: the addon name. |
| `intro` | One sentence at the top of the page. |
| `icon` | Texture of the minimap button. |
| `slash` | Slash command that opens the options. |
| `slashLeftClick` | If true, the slash command alone acts like a left-click on the button, the sub-command `options` opens the options, anything else prints help. The English word `options` is stable: it ends up in player macros. |
| `defaults` | Stored values without a menu entry. May override Core's defaults such as `minimapAngle`. |
| `onLeftClick` | Called on a left-click on the button. |
| `leftClickText` | Tooltip line for `onLeftClick`. |
| `onTooltip` | `onTooltip(tooltip)` adds lines to the button tooltip. |
| `onLoad` | `onLoad(db)` runs once, after the menu is built. |
| `alertDims` | If true, the button icon is gray while no alert is set with `ns.SetAlert`. |

### `ns.options`: entries

The array part of `ns.options` lists the entries, in order.

| Type | Required fields | Optional fields |
|---|---|---|
| `checkbox` | `key`, `label`, `default` | `tooltip`, `onChange` |
| `color` | `key`, `label`, `default` | `onChange` |
| `minimap` | none | `onChange` |
| `header` | `label` | none |
| `page` | `label`, `init` | none |

- `onChange(value)` is available on every entry that has a `key`, and on the `minimap` entry.
- `page`: a subpage below the addon; `init(frame)` runs every time the page is shown.
- `color` values are color keys.

### Color keys

`gray`, `lightgray`, `white`, `yellow`, `orange`, `red`, `pink`, `purple`, `blue`, `turquoise`, `green`.

### Saved data

Core writes the keys `minimap`, `minimapAngle` and `_schema` into the addon's saved variable. These names are reserved: do not use them for your own entries. Each entry with a `key` adds that key. Keys nobody names are kept.

### Timing

`ns.options` is read once, at the addon's `ADDON_LOADED`, after all its files are loaded. Later changes to the table have no effect. Afterwards `ns.db`, `ns.minimapButton`, `ns.GetColor` and `ns.SetAlert` exist, and `onLoad(db)` runs once, before `PLAYER_LOGIN`.

### Behavior

Left-click on the minimap button runs `onLeftClick`, right-click opens the options, dragging moves the button around the minimap.

### Global names

`PylosCore`, `<Addon>MinimapButton` (the addon name plus `MinimapButton`), `SLASH_<ADDON>1` (the upper-case addon name), and the settings category "Pylos".

## Versions

A service has a version `major.minor`. An addon declares in `requires` what it was written against.

- A change that only adds is a new minor: a new function on `PylosCore`, a new optional field in `ns.options`, a new entry type, a new optional last argument, a new color key. Never a new field in `ns`.
- Removing, renaming or changing the meaning of a stable name (arguments, return value, meaning), changing a default value of a stable field for everyone, renaming a reserved saved key, or changing the timing is a new major.
- A bug fix that restores documented behavior changes only the package version.
- A newer Core keeps offering the old major beside the new one while a published addon still asks for it.

## Unknown fields and types

- An unknown field in the head of `ns.options` or in an entry is ignored.
- An unknown entry `type` is an error of the addon: Core skips that row, reports a problem on the "Pylos" status page, and builds the rest of the menu.
- An addon that needs a newer field or type requires the matching minor of `core`.

## Stability levels

- **stable**: a published addon uses it. Listed here. Changes only additively.
- **provisional**: reachable, but not listed here (for example `PylosCore.Provide`, `PylosCore.Get`, `PylosCore.NewLocale`, `PylosCore.Saved`, `ns.db`, `ns.SetOption`, `ns.IsModifierHeld`, `ns.minimapButton`, the other entry types and fields). May change in any release.
- **internal**: only Core's own files. Not reachable, changes at any time.

## Deprecated

Nothing yet.
