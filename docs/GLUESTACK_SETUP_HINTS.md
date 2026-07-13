# gluestack-ui — hands-on field notes & Android reality check

Field notes from a real compat spike: installing **gluestack-ui** in an Expo/RN app,
building it, and running it on a physical iOS device. Written so another engineer can
reproduce a known-good setup, skip the potholes, and understand the version-naming and
Android-version constraints before committing to gluestack.

Source stack for these notes: **React 19.2 / RN 0.86 / Expo 57 / NativeWind 4.2** —
converted a screen, built it, ran it on-device (TestFlight). Two things this adds
beyond a typical writeup: **hands-on verification** (it was actually built and run, not
just read about) and a **hard Android-version reality check**.

## ⚠️ Read first: the old-device blocker

If your app must support **old Android hardware** (e.g. 2011-era Android 4.x devices),
**gluestack-ui cannot meet that — and neither can any modern React Native.** gluestack forces modern NativeWind → modern RN
→ **minSdkVersion 24 (Android 7.0, 2016)**. There is *no* version combination that
gives you gluestack AND sub-2016 devices. If old-device support is a real, hard
requirement, **settle that before the UI-library choice** — it can rule out React
Native entirely (→ native Android). Full tables in the Android section below.

## Version naming — decoder (this trips everyone up)

"v2 / v3 / core@4 / core@5" are **three different numbering axes**, not one:
- **Product version** — the marketing name (gluestack-ui "v2", now **"v3"** on
  gluestack.io).
- **`@gluestack-ui/core` package version** — `4.x` or `5.x`, what actually lands in
  `package.json`. It tracks the **NativeWind/Tailwind generation**, NOT maturity.
- **NativeWind/Tailwind pairing** — v4/Tailwind-3 vs v5/Tailwind-4, which decides which
  `core` major the CLI pulls.

A higher `core` number is **not** "more stable." Our spike (NativeWind 4.2) pulled
`@gluestack-ui/core@4.0.0-alpha.0` — explicitly **alpha**. **Before committing, confirm
on npm exactly which `@gluestack-ui/core` package version "v3" resolves to and whether
that version is alpha or stable** — public messaging is inconsistent and moving, so
don't infer it from the product-version label.

## TL;DR

- gluestack-ui's install path **branches on your NativeWind/Tailwind major version**,
  and that choice decides which `@gluestack-ui/core` major you get. Get it right first.
  - **NativeWind v4 / Tailwind v3 → `@gluestack-ui/core@4.0.0-alpha`** — CONFIRMED
    **alpha** (the package literally carries `-alpha.0`). This is the path that
    produced all the pain below. ⚠️
  - **NativeWind v5 / Tailwind v4 → `@gluestack-ui/core@5.x`** — newer line targeting
    the newer styling engine. **Stability UNVERIFIED** — see the naming note below;
    do not assume it's production-stable without checking.
- **Version numbers are compatibility generations, not maturity** — see the "Version
  naming — decoder" section above. Confirm your target `@gluestack-ui/core` version's
  alpha/stable status on npm at setup time; don't infer it from the product version.
- The CLI itself is now **CI-friendly** (non-interactive flags exist) — the old
  "interactive/unverifiable" reputation is outdated.
- Budget time for **peer-dependency friction on React 19** and, on the alpha line,
  **manual dependency repair**.

## Compatibility matrix (choose your line deliberately)

| Your styling stack | `@gluestack-ui/core` the CLI picks | Stability | Notes |
|---|---|---|---|
| NativeWind **v4** + Tailwind **v3** | `@gluestack-ui/core@4.0.0-alpha` (`main-v4-alpha` branch) | **Alpha (confirmed)** | What this project hit; expect the workarounds below |
| NativeWind **v5** + Tailwind **v4** | `@gluestack-ui/core@5.x` | **Unverified** — messaging is contradictory (billed as both alpha and stable); confirm on npm | Likely the better long-term line, but check its status first |

The `core` major just follows your NativeWind/Tailwind major — it is not a
maturity ranking. If you start fresh, NativeWind v5 / Tailwind v4 is likely the
better long-term line, **but confirm `@gluestack-ui/core@5.x`'s release status before
betting on it** rather than trusting this table. The one thing that's certain: the
`4.x` line you land on with NativeWind v4 is explicitly alpha.

## Reproducible setup (non-interactive)

The CLI is a shadcn-style "copy component source into your repo" tool. It runs fully
non-interactively — no stdin prompts — with the flags below.

```bash
# 1. Init gluestack into an existing Expo app (NativeWind already installed).
#    CI=1 + --yes keeps it non-interactive (safe for CI / headless).
CI=1 npx gluestack-ui init --yes --nativewind --use-npm

# 2. Add only the components you need (they land in components/ui/<name>/).
CI=1 npx gluestack-ui add box vstack hstack text input textarea button switch pressable scroll-view --yes
```

What `init` does: clones `github.com/gluestack/gluestack-ui` (the branch matching your
NativeWind major) into `~/.gluestack/cache`, copies component source into
`components/ui/`, writes `gluestack-ui.config.json`, and adds deps to `package.json`.

Then wire the provider at the top of your app tree (below any SafeArea provider,
above navigation/your contexts):

```tsx
import { GluestackUIProvider } from '@/components/ui/gluestack-ui-provider';
// ...
<GluestackUIProvider mode="light">
  {/* existing providers / navigation */}
</GluestackUIProvider>
```

And extend Tailwind (do NOT remove your existing NativeWind preset — add on top):

```js
// tailwind.config.js
content: [/* your globs */, './components/**/*.{tsx,jsx}'],
// + gluestack's semantic-color theme tokens and safelist (the CLI adds these)
```

## Gotchas & workarounds (alpha line — NativeWind v4 / Tailwind v3)

Each is a real failure we hit, with the symptom and the fix. If you're on the v5
stable line, most of these should not apply — verify.

1. **React 19 peer-dependency conflict.**
   *Symptom:* `npm install` errors on peer deps — gluestack pulls
   `react-native-web` → `react-dom@^19` → `react@^19.2.7`, but your app may pin an
   earlier 19.x (e.g. `19.2.3`).
   *Workaround the CLI applies for you:* it writes `.npmrc` with
   `legacy-peer-deps=true`. Know that this makes **all** installs use legacy peer
   resolution — commit `.npmrc` so CI (`npm ci`) behaves identically. (`npm ci`
   honors `.npmrc`; we verified a clean `npm ci` + `expo export` both pass with it.)

2. **The install can REMOVE deps you depend on.**
   *Symptom:* after installing gluestack, `npm test` breaks with
   `Cannot find module 'react-native-worklets/plugin'` and/or the jest-expo preset
   fails.
   *Cause:* the alpha install pruned `react-native-worklets` (reanimated's babel
   plugin) and `@react-native/jest-preset` from the tree.
   *Fix:* re-pin them explicitly in `package.json`:
   ```
   "react-native-worklets": "^0.10.2",          // dependencies
   "@react-native/jest-preset": "^0.86.0"        // devDependencies (match your RN)
   ```

3. **Alpha packages under-declare their dependencies.**
   *Symptom:* runtime/bundler errors about missing `@react-aria/*` / `@react-stately/*`
   modules even though install "succeeded."
   *Cause:* the alpha imports ~13 `@react-aria/*` + ~9 `@react-stately/*`
   **subpackages directly**, but only declares the `react-aria` / `react-stately`
   meta-packages — and under `legacy-peer-deps` those subtrees don't get installed.
   *Fix:* hand-install the subpackages your components actually import (grep the
   `components/ui` source for `@react-aria/` and `@react-stately/` imports, then
   `npm i` each).

4. **`react-dom` gets dragged into a NATIVE bundle.**
   *Symptom:* `expo export` (or Metro) fails resolving `react-dom`.
   *Cause:* the provider (Overlay/Toast) and even `Switch`/`Button` chain through
   `@react-aria/utils` → `react-aria` → a top-level `require('react-dom')`.
   *Fix to make it BUILD:* `npm i react-dom@<your-react-version>`.
   *Caveat you cannot fix this way:* shipping react-aria's **web** hooks + react-dom
   inside a native React Native app is architecturally wrong. It bundles, and — tested on a
   real device (TestFlight, iOS) — **it does render and run without crashing** (a
   converted form screen with Input/Textarea/Switch/Button worked). So the risk here
   is dependency *hygiene* and bloat, NOT runtime breakage. Still **test on a real
   device early** rather than trusting a green `expo export` — but don't assume it
   will crash; on this stack it didn't.

5. **Alpha component source doesn't typecheck against NativeWind 4.2.x.**
   *Symptom:* `tsc` errors in the vendored `button`/`input` component source
   (stricter `cssInterop` types).
   *Fix:* a few minimal, commented type casts in the generated `components/ui/*`
   files. (Annoying because it's vendored code you now "own".)

6. **Lint noise.** The vendored source emits `import/no-duplicates` warnings
   (harmless, but noisy). Scope your linter or accept the warnings.

## DX assessment (candid — for the build-vs-not decision)

- **Component API quality: good.** Idiomatic compound components (`Input`/`InputField`,
  `Button`/`ButtonText`, `Box`/`HStack`/`VStack`), semantic color tokens
  (`text-foreground`, `border-border`) driven by provider CSS vars. Pleasant to write.
- **Packaging & deps: the weak point.** On the alpha line it's fragile: peer-dep
  papering-over, pruned deps, under-declared transitive deps, react-dom-in-native.
- **Runtime: it works.** On-device (TestFlight/iOS) the converted screen rendered and
  functioned with no crash — the react-dom-in-native concern did not manifest as
  breakage. The reason to avoid the alpha line is **dependency hygiene + long-term
  maintenance** (alpha packages, peer-dep hacks, vendored code you must patch), not
  "it'll crash."
- **gluestack is not a free restyle.** A 1:1 swap from RN primitives to gluestack
  components using the same NativeWind tokens produces **no visual change**. gluestack
  buys you a component system + semantic design tokens to *deliberately* design
  against — budget a real design pass to see value; don't expect the migration alone
  to improve the UI.
- **Verdict:** gluestack-ui is worth using **on its stable line (NativeWind v5 /
  Tailwind v4)**. Do NOT adopt the NativeWind-v4 alpha line for anything you intend
  to ship — not because it fails at runtime (it didn't), but because the alpha
  dependency footprint is a maintenance liability.
- **De-risk order for a new project:** (1) pin NativeWind v5 / Tailwind v4 up front;
  (2) get `@gluestack-ui/core@5.x` via the CLI; (3) wire the provider + convert ONE
  screen; (4) **build to a real device immediately** and confirm it renders/doesn't
  crash before converting more.

---

# Android `minSdkVersion` / old-device support

Reference tables for picking versions when you must support **old Android devices**.
Verified July 2026 from RN template `build.gradle` at git tags, the RN team's minSdk
bump announcements, Expo changelogs, and ground-truth reads of installed
`node_modules/**/build.gradle`. Sources at the bottom.

## The one thing to know up front

**API level 14 (Android 4.0, 2011) is NOT reachable with React Native — at all.**
RN's template floor has never been below **API 16** (Android 4.1). Hitting API 14
would mean patching and rebuilding RN's native modules against an unsupported
NDK/AGP toolchain — not a supported path, effectively infeasible. If a hard
requirement is genuinely 2011 Android 4.0 hardware, **RN is the wrong tool** — use
native Android (Java/Kotlin with `minSdk 14`) or drop the requirement.

## React Native → minSdkVersion

| RN line | minSdk | Android | Notes |
|---|---|---|---|
| 0.60 – 0.63 | **16** | 4.1 (2012) | oldest floor RN ever shipped; obsolete, pre-New-Arch |
| 0.64 – 0.73 | **21** | 5.0 (2014) | 0.73 (Dec 2023) is the LAST to support API 21 |
| 0.74 – 0.75 | **23** | 6.0 (2015) | |
| 0.76 – 0.86 (current) | **24** | 7.0 (2016) | no bump beyond 24 announced through 0.86 |

Transitions (confirmed): **16→21 at 0.64**, **21→23 at 0.74**, **23→24 at 0.76**.

## Expo SDK → minSdkVersion

Expo's floor has been **≥ 23 since SDK 49** and **24 since SDK 52** — so Expo has *no*
recent path to API 21. To target API 21 you need **bare RN 0.64–0.73** (or an Expo
SDK older than 49).

| Expo SDK | Wraps RN | minSdk |
|---|---|---|
| 49–51 | 0.72–0.74 | 23 |
| 52–57 | 0.76–0.86 | **24** |

## Per-dependency lookup (versions used here vs. old-device support)

"Used here" = the reference project (which resolves to **minSdk 24**). The last two
columns are the newest version of each dep that still reaches the given old API.
**Every "API 14" cell is N/A — nothing in the RN ecosystem reaches it.**

| Dependency | Version used here | minSdk of that version | Newest version for **API 21** (2014) | Newest for **API 16** (2012) | API 14 |
|---|---|---|---|---|---|
| react-native | 0.86.0 | 24 | 0.64–0.73 | ≤ 0.63 | ❌ none |
| expo (SDK) | 57 | 24 | *(none — Expo floor ≥23; use bare RN)* | ❌ | ❌ |
| nativewind | 4.2.6 | follows RN | any (styling only) | any | ❌ |
| @gluestack-ui/core | 4.0.0-alpha | follows RN, **needs NativeWind v4+** | ❌ incompatible¹ | ❌ | ❌ |
| react-native-reanimated | 4.5.0 | 24 (New-Arch-only²) | Reanimated **3.x** | — (unverified) | ❌ |
| react-native-screens | 4.25.2 | follows RN (fallback 21) | 3.x era (unverified) | — | ❌ |
| react-native-safe-area-context | 5.7.0 | follows RN (fallback 16) | older majors | older majors | ❌ |

¹ gluestack's current lines require modern NativeWind (v4+), which requires modern RN
(floor 24). **gluestack + old Android is contradictory** — you cannot use current
gluestack and target API 16/21 at the same time.
² Reanimated 4 is New-Architecture-only and its compat table covers RN 0.78–0.86 —
i.e. only RN versions whose floor is already 24. For an API-21 build you'd drop to
Reanimated 3.x.

None of the three native peers (safe-area-context, screens, reanimated) imposes a
floor *higher* than RN's own — the binding constraint is always **RN itself** and, for
the animation stack, the **New-Architecture requirement**.

## Device-era decision table

| Target device era | Min API | Viable stack |
|---|---|---|
| 2011 Android 4.0 | 14 | **Not achievable with RN.** Native Android, or drop the requirement. |
| 2012 Android 4.1 | 16 | RN ≤ 0.63 only — obsolete/insecure, no modern gluestack/NativeWind. Not recommended. |
| 2014 Android 5.0 | 21 | Bare RN 0.64–0.73. No current gluestack, no Reanimated 4. |
| 2016+ Android 7.0 | 24 | Everything current: RN 0.76–0.86, Expo 52–57, gluestack + NativeWind v4/v5, Reanimated 4. |

**If gluestack-ui is a requirement, your realistic Android floor is API 24 (Android
7.0, 2016).** There is no version combination that gives you both gluestack and
sub-2016 device support.

## Sources

- RN minSdk bumps: community discussions [#740](https://github.com/react-native-community/discussions-and-proposals/discussions/740) (0.74→23), [#802](https://github.com/react-native-community/discussions-and-proposals/discussions/802) (0.76→24)
- RN template `build.gradle` at tags v0.63.0 (16), v0.64.0 / v0.68.0 / v0.71.0 (21)
- [Expo SDK 52 changelog](https://expo.dev/changelog/2024-11-12-sdk-52) (minSdk 23→24)
- [Reanimated compatibility table](https://docs.swmansion.com/react-native-reanimated/docs/guides/compatibility/) (RN 0.78–0.86, New Arch only)
- [gluestack v2 stable / NativeWind v4.1](https://gluestack.io/blogs/gluestack-ui-v2-stable-release-with-nativewind-v4-1-support), [gluestack v5 alpha / NativeWind v5](https://github.com/gluestack/gluestack-ui/discussions/3366)
- Ground truth: `node_modules` `expo-modules-core` (default 24), `react-native-screens` (fallback 21), `react-native-safe-area-context` (fallback 16)

*Not fully verified: per-tag RN 0.60–0.62 (16 is the known floor, only 0.63 tag-checked); exact stable/alpha status of gluestack v5 / NativeWind v5 (contradictory public messaging); older-major Reanimated/screens exact floors (relevant only for a deliberately old-RN build).*
