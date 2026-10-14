# Neobrutalist UI chrome

Light mode speaks a neobrutalist chrome adapted from [neobrutalism.dev](https://neobrutalism.dev): hard
outlines, flat fills and a blur-free offset shadow. It is a **light-only, per-surface** language — dark
mode keeps the flat grouped-list chrome it had before. [AGENTS.md](../../AGENTS.md) states the rule; this
page explains how the mechanism is wired.

The tokens are the single source of truth, not this page: [ColorTokens](../../apps/mobile-flutter/lib/ui/theme/color_tokens.dart)
and the components in `apps/mobile-flutter/lib/ui/widgets/common/`.

## The two-language switch

Every neo branch is gated on `ColorTokens.neobrutalism` — `true` in light, `false` in dark. A neo surface
opts in by branching on that flag; the legacy chrome is the `else` branch, so dark is untouched.

- Palette ([ColorTokens](../../apps/mobile-flutter/lib/ui/theme/color_tokens.dart)): `neoEdge`, `neoShadow`,
  `brandInk` (pure black in light), `actionFill` (bright lime `#7AE60F`), `gridLine`.
- Metrics (`Neo`, same file): `edge = 2.0` (outline width), `lift = 4.0` (shadow offset), `radius = R.sm`
  (`6.0`), `gridStep = 70.0`.

Never hardcode the black edge, the shadow or the lime fill — read the token.

## Components

Shared primitives live in `apps/mobile-flutter/lib/ui/widgets/common/`:

- [NeoCard](../../apps/mobile-flutter/lib/ui/widgets/common/neo_card.dart) — the neo block, plus the
  `neoShadow()` helper. It owns both chromes: while `neobrutalism` is true it is a `Neo.edge`-px outline
  with `Neo.radius` corners and a zero-blur shadow offset `Neo.lift` on both axes; otherwise it paints the
  flat pre-neo card described by its `legacy*` parameters.
- [NeoButton](../../apps/mobile-flutter/lib/ui/widgets/common/neo_button.dart) — brand / quiet tones. Press
  feedback lives here: the block translates into its own shadow (`_NeoPress`).
- [NeoCodeBlock](../../apps/mobile-flutter/lib/ui/widgets/common/neo_code_block.dart) — outlined container
  for machine-readable data (addresses, payload hex); a no-op in dark.
- [GridBackground](../../apps/mobile-flutter/lib/ui/widgets/common/grid_background.dart) — the
  `Neo.gridStep` reference grid; also light-only.
- [neoAppBar](../../apps/mobile-flutter/lib/ui/widgets/common/neo_app_bar.dart) — the title bar (see
  below); every neo surface with an AppBar goes through it.

## Where it is applied

Neo chrome covers the Vault home ([accounts](../../apps/mobile-flutter/lib/ui/screens/accounts/)),
[Account Detail](../../apps/mobile-flutter/lib/ui/screens/account_detail/),
[History](../../apps/mobile-flutter/lib/ui/screens/history/history_screen.dart),
[Settings](../../apps/mobile-flutter/lib/ui/screens/settings/), and the whole onboarding / signing flow:
[Welcome](../../apps/mobile-flutter/lib/ui/screens/welcome/),
[Unlock](../../apps/mobile-flutter/lib/ui/screens/unlock/) + Set PIN, the mnemonic flows
(`generate_mnemonic`, `import_mnemonic`, `verify_mnemonic`, `verify`, `enigma`, `enigma_mnemonic`,
`entropy`, `backup_seed`, `seed_export`), the [Stand-in](../../apps/mobile-flutter/lib/ui/screens/stand_in/)
harness, and the [transaction](../../apps/mobile-flutter/lib/ui/screens/transaction/) screens.

Every neo surface sits on the pale-lime page tint with the reference grid behind its body. `MainScreen`
paints that grid for all three tabs; **every other full-screen route wraps its own body**:

```dart
Scaffold(
  // `groupedBg` is the pale-lime page tint in light and equals `bg` in dark,
  // so this only affects light mode.
  backgroundColor: c.groupedBg,
  appBar: neoAppBar(c: c, title: Text(/* … */)),
  body: GridBackground(
    child: /* the screen body */,
  ),
)
```

`neoAppBar` ([neo_app_bar.dart](../../apps/mobile-flutter/lib/ui/widgets/common/neo_app_bar.dart)) builds
the title bar: a white block closed by a hard `Neo.edge` rule in light, the theme's own seamless bar in
dark. Pass `darkBackground:` only when dark must keep a bar colour other than the theme's `surface`, and
`ruleWidth:` for the app shell's heavier rule.

The app's default `ThemeMode` is `system`, so a device in light mode lands on the neo chrome out of the
box, and [Welcome](../../apps/mobile-flutter/lib/ui/screens/welcome/welcome_screen.dart) carries the
display-mode switch (top-left) so the mode can be chosen before a wallet exists.

[TxDetailsCard](../../apps/mobile-flutter/lib/ui/widgets/tx_details_card.dart) is shared with the signing
screen, so it does **not** read `neobrutalism` itself — it takes an explicit `neo` flag. A neo surface
passes `neo: c.neobrutalism`; every other caller leaves it `false`.

## Building a new neo surface

- Gate every branch on `c.neobrutalism`; keep the legacy chrome for the `else`.
- Set the page background to `c.groupedBg` and wrap the `body` in `GridBackground` (see the snippet
  above). Component-level chrome alone is not enough.
- Build the title bar with `neoAppBar` instead of hand-rolling the `neobrutalism ? … : …` branches.
- Reuse `NeoCard` / `NeoButton` / `NeoCodeBlock` and the `Neo` metrics rather than re-deriving the look.
- Leave room for the offset shadow: stacked blocks need at least `Neo.lift` on the right/bottom (the Vault
  list uses a 14px gap in light, 10px in dark).
- `clip: true` on `NeoCard` whenever a child fills the block edge to edge.
- Shared widgets that must serve both languages take an explicit `neo` flag instead of reading the token.

## Visual spec

The design gallery (`tool/gallery/`, ADR-005) renders screens against the real theme and is the place to
eyeball a neo surface. Run it with `flutter run -t tool/gallery/main.dart -d chrome`
(see [BUILDING.md](../../BUILDING.md)). Its tokens page lists the core palette, the `neo*` tokens and the
`Neo` metrics.
