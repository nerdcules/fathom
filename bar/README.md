# The bar's dropdowns

Every item on Omarchy's bar gets Fathom's own dropdown, in Quick settings'
look, now and as Omarchy adds items (#14). This folder holds them.

- `items.json`: every Omarchy bar item, and its Fathom dropdown (`fathom`),
  what's planned for it (`planned`), or why it has none (`none`).
  `tests/test_bar.py` fails when Omarchy has a bar item this list doesn't
  name, so a new one can't go unnoticed; and `follows`, the Omarchy files
  each dropdown copies behaviour from (see "Keeping up with Omarchy"). The
  bar's cluster
  (`fathom.desk`) stands for Omarchy's Bluetooth, network, volume and
  battery items.
- `plugin/<id>/kit`: a link to Fathom's kit (`kit/` at the top of the
  repo), which `install.sh` replaces with a copy in the installed plugin.
- `plugin/<id>/`: one Omarchy plugin per dropdown.

The kit is shared with the Command Deck and the desk (#22): the skin
(`Skin`: the look's values and Personalise's), `Label`, `Pill` (Fathom's
one button), `Glass` (Fathom's one panel), `Tip`, `Dot` and number
formatting (`Format.js`), and the dropdowns' own parts, all named `Drop…`.
A shell plugin can load only its own files, so each plugin's `kit/` is a
link in the repo and a copy once installed; `tests/test_one_look.py`
fails if a plugin grows its own copy of a kit part, asks the skin for
something it doesn't have, or takes the theme or its size differently.
In a dropdown a `Pill` sets `tabStop: false`, so Tab goes to the next
dropdown and the arrows reach the pill instead.

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
| `meter` | `key`, `label`, `trail`, `value` (0 to 1) | `picked(key, "doubleClick")` |
| `fields` | `key`, `fields: [{key, label, value, placeholder, digits}]`, `okLabel`, `cancelLabel` | `submitted(key, {field: text})`, `cancelled(key)` |
| `facts` | `items: [{label, value}]` | |
| `strip` | `key`, `items: [{key, glyph, name, detail}]` | |
| `search` | `key`, `text`, `placeholder`, `busy`, `busyLabel`, `autoFocus` (default true: the field takes the keyboard as it shows; false: the arrows reach it), `results: [{key, glyph, name, detail}]`, `chosen` | `edited(key, text)`, `moved(key, chosen)`, `submitted(key, {text, chosen})`, `cancelled(key)`, `picked(key, result key)` |
| `text` | `text`, `dim` | |

`hidden: true` leaves a section out. A new description, which every value
change makes, updates the parts in place, so a slider being dragged or the
control with the keyboard keeps it. An item that needs a picture of its
own puts its own QML in the card beside the sections, as the clock's
month does (`plugin/fathom.clock/MonthGrid.qml`), and can take keys of
its own first through the card's `keyHandler` (the clock's arrows step
the month, as Omarchy's do), and put the keyboard on a section by its key
with the card's `focusPart(key)` (Tailscale's `/`).

A dropdown can use Omarchy's own words, in every language Omarchy has:
its `t()` reads a key that starts with `@` from Omarchy's catalog
(Tailscale's `t("@tailscale.exitNodes")`), and its own keys from its
`i18n/en.json`. `tests/test_bar.py` checks that each `@` key exists in
Omarchy's English catalog.

### The look and the keys

`DropTheme` gives the kit the theme as Quick settings has it: Omarchy's
colours, font and corners, the menu's opacity and border, glass when
Hyprland blurs, the glow from Personalise, and Fathom's size for the
screen (the deck's and desk's rule). Sizes are Fathom's, not Omarchy's:
a dropdown's width is so many units times that size, as Quick settings'
is. The deck and the desk bind the same theme into the same skin. A theme
change restyles every
dropdown as it happens.

`DropCard` takes the keys as Omarchy's dropdowns do: the arrows or h j k l
walk the controls (round from the last to the first), Left and Right move
a slider, Return or Space presses, Tab and Shift+Tab go to the next or
previous dropdown on the bar, and Esc closes it. Nothing shows as chosen
until a key is used. In a search field, Up and Down choose a result, and
past the first or the last go on to the controls around it.

## Keeping up with Omarchy

A dropdown copies behaviour from Omarchy's own: its settings, IPC
methods, the scripts it runs, and for the clock, Omarchy's date code
(`Model.js`, copied unchanged). When Omarchy updates one of those, the
copy doesn't follow by itself. So `items.json` records, for each
dropdown, the Omarchy files it follows and the start of each one's
sha256 when it was last checked against it (`checkedWith` names the
Omarchy version), and the same for Omarchy's popup frame (`kitFollows`).
On a machine with Omarchy, `tests/test_bar.py` fails when one has
changed or gone, naming it. Then: read Omarchy's change, bring the
dropdown into line (or decide it needn't), try it, and write the new
fingerprint in.

What this doesn't catch: a change Omarchy makes somewhere the list
doesn't name, and the tests only run when someone runs them.

## Adding one

1. Give the item a `fathom` line in `items.json`, in place of `planned`,
   with `follows`: every Omarchy file it copies behaviour from.
2. Make `plugin/fathom.<name>/` as above, cloning the Omarchy item.
3. Test its `sections()` in `tests/bar.test.mjs`, which also checks it has
   the words it asks for; `tests/test_bar.py` checks it's a clone of its
   item.
4. Try it in the test VM: `install.sh --desk`, then its button, its keys
   and its Omarchy key; `uninstall.sh` must put Omarchy's back.
