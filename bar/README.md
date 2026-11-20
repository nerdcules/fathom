# The bar's dropdowns

Every item on Omarchy's bar gets Fathom's own dropdown, in Quick settings'
look, now and as Omarchy adds items (#14). This folder holds them.

- `items.json`: every Omarchy bar item, and its Fathom dropdown (`fathom`),
  what's planned for it (`planned`), or why it has none (`none`).
  `tests/test_bar.py` fails when Omarchy has a bar item this list doesn't
  name, so a new one can't go unnoticed. The bar's cluster
  (`fathom.desk`) stands for Omarchy's Bluetooth, network, volume and
  battery items.
- `kit/`: what every dropdown is made of, copied into each plugin as
  `kit/` by `install.sh`.
- `plugin/<id>/`: one Omarchy plugin per dropdown.

## How a dropdown is made

Each plugin is a **clone** of the Omarchy item it replaces: its
`manifest.json` says `"omarchy": { "clonedFrom": "omarchy.monitor" }`. That
is Omarchy's own way to replace one of its items (`omarchy plugin clone`):

- turning the clone on puts it where Omarchy's was, with that entry's
  settings;
- turning it off puts Omarchy's back the same way;
- `omarchy-shell shell toggle omarchy.monitor`, and so Omarchy's keys
  (Super+Ctrl+D), reach the clone. Inside, the clone keeps Omarchy's id as
  its `moduleName` and IPC target, so `omarchy-shell omarchy.monitor
  brightness 40` and the like still work.

A plugin has three parts:

- **`<Name>.js`**, the arithmetic: parsing what the machine says, and
  `sections(state, t)`, the dropdown as a description (below).
  `tests/bar.test.mjs` tests it under Node.
- **`<Name>.qml`**, the glue: the bar button (Omarchy's `BarIconButton`),
  reading and changing the machine, and Omarchy's popup frame
  (`KeyboardPanel`) with a `DropCard` inside, holding a `DropSections`
  drawn from `sections()`; and a `DropTheme`, given the frame's screen. It needs
  Omarchy's shell, so it's tried in the test VM.
- **`i18n/en.json`**, its words, with the kit's `drop.on` and `drop.off`.

### The factory

`kit/DropSections.qml` draws a dropdown from a list of sections, so a new
item needs a description, not a new screen:

| type | fields | sends |
|---|---|---|
| `slider` | `key`, `glyph`, `tip`, `value` (0 to 1), `label`, `steps` | `moved(key, value)` |
| `choices` | `key`, `title`, `options: [{value, label}]`, `chosen` | `picked(key, value)` |
| `rows` | `key`, `title`, `rows: [{key, glyph, name, detail, trail, active, busy, clickable}]`, `busyLabel` | `picked(key, row key)` |
| `switch` | `key`, `glyph`, `name`, `detail`, `on` | `toggled(key, !on)` |
| `actions` | `key`, `buttons: [{key, label, glyph, primary}]` | `picked(key, button key)` |
| `text` | `text`, `dim` | |

`hidden: true` leaves a section out. A new description, which every value
change makes, updates the parts in place, so a slider being dragged or the
control with the keyboard keeps it. An item that needs a picture of its
own (a calendar, say) puts its own QML in the card beside the sections.

### The look and the keys

`DropTheme` gives the kit the theme as Quick settings has it: Omarchy's
colours, font and corners, the menu's opacity and border, glass when
Hyprland blurs, the glow from Personalise, and Fathom's size for the
screen (the deck's and desk's rule). Sizes are Fathom's, not Omarchy's:
a dropdown's width is so many units times that size, as Quick settings'
is. `tests/test_one_look.py` fails if the kit's look drifts from the deck's
or the desk's. A theme change restyles every
dropdown as it happens.

`DropCard` takes the keys as Omarchy's dropdowns do: the arrows or h j k l
walk the controls (round from the last to the first), Left and Right move
a slider, Return or Space presses, Tab and Shift+Tab go to the next or
previous dropdown on the bar, and Esc closes it. Nothing shows as chosen
until a key is used.

## Adding one

1. Give the item a `fathom` line in `items.json`, in place of `planned`.
2. Make `plugin/fathom.<name>/` as above, cloning the Omarchy item.
3. Test its `sections()` in `tests/bar.test.mjs`, which also checks it has
   the words it asks for; `tests/test_bar.py` checks it's a clone of its
   item.
4. Try it in the test VM: `install.sh --desk`, then its button, its keys
   and its Omarchy key; `uninstall.sh` must put Omarchy's back.
