---
name: Neutral Monochrome
colors:
  surface: '#131313'
  surface-dim: '#131313'
  surface-bright: '#393939'
  surface-container-lowest: '#0e0e0e'
  surface-container-low: '#1b1b1b'
  surface-container: '#1f1f1f'
  surface-container-high: '#2a2a2a'
  surface-container-highest: '#353535'
  on-surface: '#e2e2e2'
  on-surface-variant: '#c4c7c8'
  inverse-surface: '#e2e2e2'
  inverse-on-surface: '#303030'
  outline: '#8e9192'
  outline-variant: '#444748'
  surface-tint: '#c6c6c7'
  primary: '#ffffff'
  on-primary: '#2f3131'
  primary-container: '#e2e2e2'
  on-primary-container: '#636565'
  inverse-primary: '#5d5f5f'
  secondary: '#c6c6cb'
  on-secondary: '#2f3034'
  secondary-container: '#46464b'
  on-secondary-container: '#b5b4ba'
  tertiary: '#ffffff'
  on-tertiary: '#2f3034'
  tertiary-container: '#e2e2e7'
  on-tertiary-container: '#636469'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#e2e2e2'
  primary-fixed-dim: '#c6c6c7'
  on-primary-fixed: '#1a1c1c'
  on-primary-fixed-variant: '#454747'
  secondary-fixed: '#e3e2e7'
  secondary-fixed-dim: '#c6c6cb'
  on-secondary-fixed: '#1a1b1f'
  on-secondary-fixed-variant: '#46464b'
  tertiary-fixed: '#e2e2e7'
  tertiary-fixed-dim: '#c6c6cb'
  on-tertiary-fixed: '#1a1c1f'
  on-tertiary-fixed-variant: '#45474b'
  background: '#131313'
  on-background: '#e2e2e2'
  surface-variant: '#353535'
  surface-grouped: '#0B0B0D'
  surface-card: '#1C1C1E'
  surface-elevated: '#2C2C2E'
  hairline-separator: '#38383A'
  zinc-subtle: '#71717A'
  silver-track: '#E5E5EA'
  status-success: '#30D158'
  status-warning: '#FF9F0A'
  status-info: '#0A84FF'
  status-review: '#BF5AF2'
  status-error: '#FF453A'
typography:
  headline-xl:
    fontFamily: Inter
    fontSize: 34px
    fontWeight: '600'
    lineHeight: 41px
    letterSpacing: -0.4px
  headline-xl-mobile:
    fontFamily: Inter
    fontSize: 30px
    fontWeight: '600'
    lineHeight: 36px
    letterSpacing: -0.4px
  headline-lg:
    fontFamily: Inter
    fontSize: 22px
    fontWeight: '600'
    lineHeight: 28px
    letterSpacing: -0.3px
  headline-md:
    fontFamily: Inter
    fontSize: 17px
    fontWeight: '600'
    lineHeight: 22px
    letterSpacing: -0.4px
  body-lg:
    fontFamily: Inter
    fontSize: 17px
    fontWeight: '400'
    lineHeight: 22px
    letterSpacing: -0.4px
  body-md:
    fontFamily: Inter
    fontSize: 15px
    fontWeight: '400'
    lineHeight: 20px
    letterSpacing: -0.2px
  label-md:
    fontFamily: Inter
    fontSize: 13px
    fontWeight: '400'
    lineHeight: 18px
    letterSpacing: -0.1px
  label-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
    letterSpacing: 0px
  caption:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '400'
    lineHeight: 14px
    letterSpacing: 0.1px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  gutter: 1rem
  margin: 1rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.25rem
  space-xl: 1.5rem
---

## Brand & Style

This design system delivers the architectural restraint, optical poise, and structural discipline of an ultra-clean, first-party Apple monochrome utility. Designed for high-stakes executive job search and autonomous application orchestration, it completely eliminates non-essential decorative styling—renouncing teal glows, vibrant marketing accents, synthetic gradients, and playful embellishments.

The visual style embodies Minimalist and Modern iOS architectural idioms: pure obsidian depths, sharp black-and-white tonal contrast, surgical 0.5px hairline boundaries, continuous squircle geometry, and typographic hierarchy rooted in silver-white clarity. Every interface element is deterministic, legible, and unhurried. Users experience absolute control, privacy, and calm efficiency during career-defining workflows.

## Colors

The color palette is stripped of chromatic brand saturations, relying on a pure monochromatic hierarchy calibrated for OLED displays and iOS dark mode fidelity. High-contrast white and silver fulfill functional priority states, while subtle zinc and charcoal grays govern structure and tertiary metadata.

### Architectural Tiers
- **Base Canvas:** `#000000` (Pure System Black for infinite contrast and zero battery consumption).
- **Grouped Canvas:** `#0B0B0D` (Subtle off-black for grouped list view channels and background depth).
- **Base Container / Cards:** `#1C1C1E` (Standard inset grouped cards, list cells, and nested containers).
- **Elevated Modals / Popovers:** `#2C2C2E` (Top-level sheets, floating inspectors, and interactive popups).
- **Hairline Separators:** `#38383A` (Sub-pixel 0.5px borders, outlines, and structural row dividers).

### Monochrome Foreground Accents
- **Primary Accent / Pure White:** `#FFFFFF` (Solid primary interactive pills, active selection glyphs, active ring strokes, and high-visibility titles).
- **Bright Silver Accent:** `#E5E5EA` (Active progress meter bars, bright silver rings, selected pill backgrounds, and hover highlights).
- **Secondary Zinc Accent:** `#8E8E93` and `#71717A` (Inactive ring tracks, disabled states, unselected navigation icons, and secondary metadata).

### Subdued Semantic Signals
Semantic colors are strictly demoted to subtle contextual status dots, tabular badges, and minor tags—never used as dominating buttons, ambient glows, or brand accents:
- **Submitted / Finished:** `#30D158` (Muted indicator dot or low-opacity badge).
- **Pending / Action Required:** `#FF9F0A` (Subdued amber note).
- **Synthesizing / Agent Active:** `#0A84FF` (Subtle system blue).
- **Human Review Checkpoint:** `#BF5AF2` (Restrained purple indicator).
- **Rejected / Parsing Failure:** `#FF453A` (Desaturated system red badge).

## Typography

The type system is built on **Inter**, optimized to mimic Apple's San Francisco optical pacing with extreme structural discipline. The hierarchy employs two core weights: Regular (`400`) for data tables and body copy, and Semibold (`600`) for structural headings and primary control labels.

### Typographic Principles
- **Tracking Tightness:** All headings and body elements above 14px enforce calibrated negative letter-spacing (`-0.2px` to `-0.4px`) to preserve optical cohesion across high-DPI displays.
- **Tabular Figures:** All numeric metrics—match ratios, application counters, compensation figures, and elapsed run-times—must mandate `font-variant-numeric: tabular-nums` to guarantee non-shifting data columns.
- **Title Compaction:** Navigation Large Titles (`headline-xl`, 34px) smoothly condense into compact centered top bar titles (`headline-md`, 17px) as the canvas scrolls under the frosted chrome navigation bar.
- **Single-Line Truncation:** Subtitles and entity rows utilize trailing ellipsis truncation without wrapping to prevent grid misalignment.

## Layout & Spacing

Layouts follow Apple's Inset Grouped paradigm, governed by a rigid 8-point base spacing rhythm with half-step 4px micro-spacings.

### Layout Philosophy
- **Inset Boundaries:** Root canvas views maintain a standard 16px (`margin: 1rem`) screen margin on mobile devices, ensuring elements float clear of hardware borders.
- **Card Margins & Gutters:** Inset cards preserve 16px to 20px vertical margins. Internal card padding consistently uses 16px (`space-md`) or 20px (`space-lg`) to balance dense tabular utility with scanning comfort.
- **Inset Dividers:** In grouped list containers, 0.5px dividers do not extend full width; they are inset from the leading edge by 16px (or by 54px when clearing leading profile or application glyphs) to maintain continuous vertical alignment with label baselines.

### Responsive Breakpoints
- **Mobile (< 768px):** Single-column stacked cards with safe area insets (34px bottom home bar buffer). Fixed 83px frosted glass tab bar.
- **Tablet / Split View (768px – 1024px):** Two-column master-detail layout. Grouped sidebar pinned at 320px with main work canvas utilizing 20px gutters.
- **Desktop (> 1024px):** Fixed centered viewport capped at 720px for singular execution streams, or an unadorned 3-column architectural workspace (Feed, Detail, Action Inspector) utilizing a 12-column grid with 16px gutters and 24px margins.

## Elevation & Depth

Visual hierarchy is constructed entirely through tonal luminance stepping, sub-pixel hairline boundaries, and translucent frosted glass. Volumetric, colorful, or diffuse drop shadows are strictly prohibited.

### Tonal Stratification
- **Ground Floor (`#000000`):** Root view layer.
- **Grouped Track Floor (`#0B0B0D`):** Inset grouping base layer.
- **Primary Cards & Cells (`#1C1C1E`):** Distinct structural objects sitting atop the canvas.
- **Elevated Modals & Sheets (`#2C2C2E`):** Floating inspector surfaces, interactive sheets, and contextual popovers.

### Structural Hairlines
Every edge, card boundary, and horizontal divider is rendered as a clean 0.5px hairline boundary using `#38383A`. This produces razor-sharp definition between black and charcoal surfaces without relying on heavy structural outlines.

### Frosted Chrome Surfaces
Top navigation headers, contextual floating docks, and bottom tab bars utilize `backdrop-filter: blur(20px)` over an 85% opaque black surface (`rgba(0, 0, 0, 0.85)`). The boundary between scrolling content and frozen chrome is defined by a single 0.5px hairline divider in `#38383A`.

## Shapes

The interface embraces Apple's continuous curvature (squircle) shape language, eliminating sharp mechanical radius corners in favor of fluid geometric arcs.

### Geometry Specifications
- **Cards & Primary Modules:** Strict 20px squircle corner radius (`rounded-lg` adaptation). Applied to all grouped containers, application overview modules, and review cards.
- **Interactive Controls & Inputs:** 12px pill/squircle corner radius. Applied to action buttons, search bars, text fields, and segmented control segments.
- **Meta Chips & Mini Indicators:** Pill-shaped (`rounded-full`, 9999px) for status badges and filtering chips.
- **Floating Modals & Sheets:** 28px top corner radius for presentation sheets, complete with an inset 36px × 5px rounded grabber handle rendered in 30% translucent white.

## Components

### Buttons & Action Controls
- **Primary Buttons:** High-contrast solid pure white (`#FFFFFF`) or bright silver (`#E5E5EA`) pill with 12px squircle radius, filled with pure black text (`#000000`, 17px Semibold). Touch targets maintain an exact 44px or 48px height. Only one primary white action is rendered per view state.
- **Secondary Buttons:** Subtle charcoal container (`#2C2C2E`) with bright silver text (`#E5E5EA`) and 0.5px hairline border (`#38383A`). Under press, background shifts to `#38383A`.
- **Tertiary / Ghost Actions:** Plain text rendered in `#8E8E93` or `#FFFFFF`, transitioning to 10% white background tint upon interaction.

### Progress Bars & Active Rings
- **Progress Meters:** 4px to 6px linear tracks constructed with `#2C2C2E`, filled with an active neutral silver-white indicator (`#E5E5EA` to `#FFFFFF`). No gradients or color tints.
- **Circular Status Rings:** 2.5px gauge track in `#2C2C2E` paired with an active silver-white (`#FFFFFF`) stroke indicating match percentages, completion progress, or pipeline stage counters.

### Inset Grouped Cards & Lists
- Cards feature an outer `#1C1C1E` background, 20px continuous squircle radius, and a continuous 0.5px `#38383A` outline.
- Internal list rows feature 0.5px dividers (`#38383A`) starting 16px from the leading margin to separate items cleanly.
- Row tap states trigger a momentary highlight to `#2C2C2E`.

### Form Fields & Inputs
- Search and text inputs utilize `#1C1C1E` backings with a 12px squircle radius and a 0.5px `#38383A` border.
- On focus, the hairline border shifts to a crisp pure white (`#FFFFFF`) or bright silver (`#E5E5EA`) ring without diffuse blur.
- Placeholder text is rendered in `#71717A`. Integrated clear buttons and accessory symbols use monochrome `#8E8E93`.

### Selection Controls (Checkboxes & Radios)
- **Checkboxes:** 20px squircle with a 0.5px border (`#38383A`). When active, fills with solid `#FFFFFF` with a `#000000` checkmark.
- **Radio Buttons:** Concentric circular rings. Active state displays an outer `#FFFFFF` ring encasing an internal solid white center on a pure black bed.

### Status Chips & Pills
- Rendered as compact 24px tall pills (`rounded-full`). Background is set to a restrained 10% opacity wash of the semantic token with a 0.5px matching border; text is set to the respective subdued semantic color (e.g., `#30D158` green text over `rgba(48, 209, 88, 0.10)`).
- When monochrome chips are required (e.g., tags, roles, skills), they utilize `#2C2C2E` containers with `#E5E5EA` text and `#38383A` hairline borders.

### Navigation Chrome
- **Header:** Inset large title with collapsible scroll interpolation into a centered 17px Semibold label.
- **Tab Bar:** Frosted `#000000` (85% opacity, 20px blur) with a 0.5px top divider (`#38383A`). Inactive tabs render in `#8E8E93` outline glyphs; active tabs render in filled `#FFFFFF` glyphs with bright silver titles.