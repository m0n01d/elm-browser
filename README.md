# elm-browser — with Debugger Diff Highlighting

This is a personal fork of [elm/browser](https://github.com/elm/browser) that adds **visual state-change highlighting** to the Elm time-travel debugger.

When you step through messages in the debugger, changed fields flash blue so you can see *what changed* at a glance — instead of reading the whole model tree.

![debugger diff highlighting](https://raw.githubusercontent.com/m0n01d/elm-browser/main/notes/demo.gif)

---

## What it does

- **Changed leaf values** flash with a blue animation when you step or jump between messages
- **Ancestor fields** (the path leading to the change) get a persistent blue left-stripe so you can see the nesting context
- **Consecutive changes to the same field** (e.g. a clock ticker) re-pulse every step — the DOM node is recreated via `Html.Keyed` to guarantee the animation fires even when the same field changes twice in a row
- Works with `Time.Posix`, plain `Int`/`String`/`Bool` fields, nested records, custom types, lists, dicts

---

## How to try it

Elm's package system doesn't support git dependencies, so this fork works by patching your local elm package cache. The `dev.sh` script handles that.

### Prerequisites

- Elm 0.19.1
- An Elm app that uses `elm/browser 1.0.2` (check your `elm.json`)

### Steps

**1. Clone this repo**

```bash
git clone git@github.com:m0n01d/elm-browser.git
cd elm-browser
```

**2. Sync to your app**

```bash
bash dev.sh --app /path/to/your/elm/app
```

This copies the modified debugger files into your local elm package cache and clears the precompiled artifacts so the compiler picks them up.

**3. Build your app in debug mode**

```bash
cd /path/to/your/elm/app

# with elm make:
npx elm make src/Main.elm --debug --output=index.html

# or with elm-watch:
npx elm-watch hot
# then click the mode button in the browser and switch to "debug"
```

**4. Open the debugger**

Click the debugger icon in the bottom-right corner of your app, then step through messages using the slider or arrow keys. Changed fields will flash.

### Test it with the included test app

```bash
bash dev.sh
open test-app/index.html
```

The test app has a counter with step size, history list, and label — good for seeing single-field and multi-field diffs.

---

## How the sync works

`dev.sh` copies two files:

```
src/Debugger/Expando.elm  →  ~/.elm/0.19.1/packages/elm/browser/1.0.2/src/Debugger/Expando.elm
src/Debugger/Main.elm     →  ~/.elm/0.19.1/packages/elm/browser/1.0.2/src/Debugger/Main.elm
```

It also deletes `artifacts.dat` (elm's precompiled cache) so the compiler rebuilds from source.

To undo: delete `~/.elm/0.19.1/packages/elm/browser/1.0.2/` and run `elm install elm/browser` in your app, which will re-download the original package.

---

## Feedback

If the highlighting is wrong (missed changes, false positives, layout issues), open an issue with:
- Your model shape (or a simplified version)
- Which message causes the unexpected behavior
- A screenshot if you can

---

## What's changed

Only two files are modified from upstream:

| File | Change |
|------|--------|
| `src/Debugger/Expando.elm` | `Diff` type, `computeDiff`, `Html.Keyed`-based animation, diff threading through all view functions |
| `src/Debugger/Main.elm` | `maybeDiff` and `diffFlip` in the debugger model, diff computed in `jumpUpdate`, CSS flash animation |

All other `elm/browser` functionality is unchanged.
