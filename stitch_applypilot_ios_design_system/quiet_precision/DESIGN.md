---
name: Quiet Precision
colors:
  surface: '#faf9f6'
  surface-dim: '#dbdad7'
  surface-bright: '#faf9f6'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f4f3f0'
  surface-container: '#efeeeb'
  surface-container-high: '#e9e8e5'
  surface-container-highest: '#e3e2df'
  on-surface: '#1b1c1a'
  on-surface-variant: '#46464c'
  inverse-surface: '#2f312f'
  inverse-on-surface: '#f2f1ee'
  outline: '#76777c'
  outline-variant: '#c6c6cc'
  surface-tint: '#5a5e6a'
  primary: '#161a25'
  on-primary: '#ffffff'
  primary-container: '#2b2f3a'
  on-primary-container: '#9396a4'
  inverse-primary: '#c3c6d4'
  secondary: '#605e59'
  on-secondary: '#ffffff'
  secondary-container: '#e3dfd8'
  on-secondary-container: '#64625d'
  tertiary: '#000e5a'
  on-tertiary: '#ffffff'
  tertiary-container: '#001c90'
  on-tertiary-container: '#7c8eff'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#dfe2f1'
  primary-fixed-dim: '#c3c6d4'
  on-primary-fixed: '#171b26'
  on-primary-fixed-variant: '#434752'
  secondary-fixed: '#e6e2db'
  secondary-fixed-dim: '#c9c6bf'
  on-secondary-fixed: '#1c1c17'
  on-secondary-fixed-variant: '#484741'
  tertiary-fixed: '#dee0ff'
  tertiary-fixed-dim: '#bbc3ff'
  on-tertiary-fixed: '#000f5d'
  on-tertiary-fixed-variant: '#2137b0'
  background: '#faf9f6'
  on-background: '#1b1c1a'
  surface-variant: '#e3e2df'
typography:
  headline-xl:
    fontFamily: Inter
    fontSize: 34px
    fontWeight: '600'
    lineHeight: 41px
  headline-xl-mobile:
    fontFamily: Inter
    fontSize: 28px
    fontWeight: '600'
    lineHeight: 34px
  headline-lg:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 30px
  headline-md:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 25px
  body-lg:
    fontFamily: Inter
    fontSize: 17px
    fontWeight: '400'
    lineHeight: 22px
  body-lg-medium:
    fontFamily: Inter
    fontSize: 17px
    fontWeight: '600'
    lineHeight: 22px
  body-sm:
    fontFamily: Inter
    fontSize: 15px
    fontWeight: '400'
    lineHeight: 20px
  body-sm-medium:
    fontFamily: Inter
    fontSize: 15px
    fontWeight: '600'
    lineHeight: 20px
  label-md:
    fontFamily: Inter
    fontSize: 13px
    fontWeight: '400'
    lineHeight: 18px
  label-md-medium:
    fontFamily: Inter
    fontSize: 13px
    fontWeight: '600'
    lineHeight: 18px
  label-sm:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '600'
    lineHeight: 13px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  gutter: 1rem
  gutter-mobile: 0.75rem
  margin: 1rem
  margin-tablet: 1.5rem
  margin-desktop: 2rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.25rem
  space-xl: 1.5rem
---

## Brand & Style

This design system channels an uncompromising, Apple-grade iOS sensibility inspired by Apple Health, Wallet, and Notes. The visual tone is calm, spacious, refined, and quietly luxurious. It avoids decorative ornament, high-saturation gradients, and aggressive shadows in favor of deliberate whitespace, immaculate optical alignment, and tactile hairline boundaries.

### Core Principles
- **Restraint Over Expression:** Color is an instrument of status and data, never decoration. Interactive surfaces use monochromatic authority rather than vivid fills.
- **Structural Legibility:** Hierarchy is communicated strictly through typographic weight, scale, and subtle surface steps rather than floating planes.
- **Physicality via Hairlines:** Containers do not float via drop shadows; they rest flush against the canvas, demarcated by crisp 1px borders that mimic physical paper and matte hardware materials.
- **Tactile Familiarity:** Component sizing, radii, and gesture spaces directly adhere to ergonomic native iOS patterns, delivering zero friction and immediate trust.

## Colors

The palette operates on neutral luxury with an austere, monochromatic interaction layer and a distinct, functional data palette.

### Light Mode (Default Primary)
- **Canvas Base:** `#F5F4F1` (warm bone-white backdrop that eliminates harsh optical glare)
- **Surfaces & Cards:** `#FFFFFF` (pure white elevated card containers)
- **Borders & Dividers:** `#E7E5E0` (subtle hairline separation)
- **Primary Text & Headings:** `#1A1A18` (deep charcoal-carbon)
- **Secondary Text:** `#77756F` (balanced stone gray for supporting meta)
- **Tertiary Text & Icons:** `#A8A6A0` (muted ash for subtle hints and inactive states)
- **Primary Interactive Accent:** `#2B2F3A` (deep ink)

### Dark Mode (Variant)
- **Canvas Base:** `#0F0F0F` (deep obsidian canvas)
- **Surfaces & Cards:** `#1A1A19` (elevated dark slate card fill)
- **Borders & Dividers:** `#2A2A28` (low-contrast structural hairlines)
- **Primary Text & Headings:** `#F2F1EE` (warm off-white)
- **Secondary Text:** `#9A9892` (medium neutral gray)
- **Tertiary Text & Icons:** `#6B6A65` (subtle dark ash)
- **Primary Interactive Accent:** `#F2F1EE` (high-contrast off-white stroke and fill)

### Data-Only Visualization Palette
Strictly reserved for metrics, analytics, status dots, and score indicators. These must never be repurposed as general UI fills or brand accents:
- **Indigo:** `#4B5FD6` (primary metrics, primary completion)
- **Teal:** `#1F9E8F` (positive deltas, healthy status)
- **Amber:** `#E3A33B` (pending states, cautionary indicators)
- **Coral:** `#E0674F` (critical alerts, negative variances)
- **Violet:** `#8C70D1` (secondary metrics, categorical segments)
- **Slate:** `#6B7A90` (neutral baselines, historical data points)

## Typography

The typography system relies exclusively on **Inter**, configured for optimal iOS legibility.

### Typographic Rules
- **Weights:** Restricted strictly to two weights: `400` (Regular) and `600` (Semi-Bold).
- **Tabular Figures:** All numeric data, counters, monetary values, timestamps, and metrics must enforce `font-feature-settings: "tnum" 1` to ensure rigid columnar alignment across tabular interfaces.
- **Letter Spacing:** Headlines utilize tight tracking (`-0.015em` to `-0.022em`) mirroring iOS SF Pro display rendering, while metadata labels under 13px utilize neutral or slightly open tracking (`0.01em`).
- **Hierarchy Mapping:** `headline-xl` functions as the large title for view transitions, `headline-md` anchors card modules, `body-lg` represents the native standard body tier (17pt), and `label-sm` defines uppercase section captions.

## Layout & Spacing

The layout operates on a strict **8pt dimensional grid** with a 4pt sub-grid for tight icon and micro-label pairings.

### Layout Principles
- **Screen Margins:** Mobile viewport canvas utilizes a fixed `16px` (`1rem`) outer margin. Tablet breakpoints expand to `24px` (`1.5rem`), and desktop or large split-view contexts anchor at `32px` (`2rem`).
- **Grid Architecture:** 
  - **Mobile:** 4-column fluid layout with `12px` or `16px` gutters.
  - **Tablet:** 8-column fluid layout with `16px` gutters.
  - **Desktop:** 12-column fixed/fluid layout with maximum readable container widths capping at `768px` for focused flows and `1120px` for multi-column dashboards.
- **Vertical Rhythm:** Grouped cards and form elements space out at `16px` (`space-md`) increments. Content sections within the main scroll view separate by `24px` (`space-xl`) or `32px`.

## Elevation & Depth

This design system deliberately excludes diffuse blur shadows and ambient drop shadows to preserve a clean, physical clarity.

### Depth Strategy
- **Flat Architectural Planarity:** Depth is communicated strictly via surface lightness differences and crisp hairline boundaries:
  - Base level: Canvas color (`#F5F4F1` light / `#0F0F0F` dark).
  - Raised level (Cards, Modals): Elevated pure fill (`#FFFFFF` light / `#1A1A19` dark).
- **Hairline Outlines:** All elevated containers feature a continuous `1px` solid border (`#E7E5E0` light / `#2A2A28` dark). This replicates the precision of physical bevels.
- **Translucency & Blurs:** Navigation bars, status bars, and floating utility bars utilize native Apple frosted glass styling:
  - Light mode: `rgba(245, 244, 241, 0.82)` with `backdrop-filter: blur(20px) saturate(180%)`.
  - Dark mode: `rgba(15, 15, 15, 0.82)` with `backdrop-filter: blur(20px) saturate(180%)`.
- **Modals & Overlays:** Dimming scrim uses an un-tinted black wash (`rgba(0, 0, 0, 0.3)` light / `rgba(0, 0, 0, 0.6)` dark).

## Shapes

The design system uses deliberate, smooth continuous curvature (squircle-like profiles) standard across iOS interface design.

### Corner Radius Standards
- **Cards & Primary Groupings:** Exactly `20px` corner radius.
- **Action Buttons & Standard Inputs:** Exactly `14px` corner radius.
- **Bottom Sheets & Modal Overlays:** Exactly `28px` top corner radius for natural bottom-anchored pull sheets.
- **Chips, Pills, & Status Badges:** Fully rounded capsule/pill shape (`9999px` / `round-full`).
- **Micro-Indicators & Checkboxes:** `6px` corner radius for discrete selection targets.

## Components

### Buttons
- **Primary Action Button:**
  - Height: `48px`.
  - Radius: `14px`.
  - Fill: `#2B2F3A` (Light mode) / `#F2F1EE` (Dark mode).
  - Typography: `body-sm-medium` (15px, weight 600). Text color: `#FFFFFF` (Light) / `#1A1A18` (Dark).
  - State: Active press triggers subtle opacity shift to `0.88` or a native `0.98` scale transition. No drop shadows.
- **Secondary Action Button:**
  - Height: `48px`, Radius: `14px`.
  - Fill: Transparent. Border: `1px` solid `#E7E5E0` (Light) / `#2A2A28` (Dark).
  - Text: `#1A1A18` (Light) / `#F2F1EE` (Dark).
- **Tertiary / Ghost Button:**
  - Height: `44px` minimum tap target. Fill: Transparent. Text: `#77756F`.

### Cards
- **Geometry:** Border radius of `20px`, internal padding of `20px` (`space-lg`), `1px` solid hairline border (`#E7E5E0` light, `#2A2A28` dark).
- **Fill:** `#FFFFFF` (Light) / `#1A1A19` (Dark).
- **Grouping:** Nested card rows use native iOS inset group styles: inner rows divided by `1px` hairline offset by label padding (`16px`), omitting outer box borders when grouped inside an enclosing card.

### Chips & Badges
- **Status Badges:** Capsule radius (`9999px`), padding `4px 10px`. 
- **Style:** Subtle, low-opacity tint matching the corresponding data color (e.g., Indigo badge uses `rgba(75, 95, 214, 0.1)` background with `#4B5FD6` text). Typography: `label-sm` (11px, weight 600).
- **Filter Chips:** Capsule radius, `36px` height. Inactive: `#FFFFFF` with `1px` border `#E7E5E0`. Active: `#2B2F3A` background with white text.

### Form Inputs & Controls
- **Text Inputs:**
  - Height: `48px`. Corner radius: `14px`.
  - Fill: `#FFFFFF` (Light) / `#1A1A19` (Dark).
  - Border: `1px` solid `#E7E5E0`. Focus state replaces border with `#2B2F3A` (Light) / `#F2F1EE` (Dark); no outer glow rings.
  - Padding: `0 16px`. Placeholder: `#A8A6A0`.
- **Checkboxes & Radios:**
  - Dimensions: `22px x 22px`.
  - Checkbox radius: `6px`; Radio radius: `11px`.
  - Selected state: Deep ink fill (`#2B2F3A`) with a pure white check/dot glyph.

### Bottom Sheets
- **Structure:** Anchored to viewport bottom with `28px` top-left and top-right radii.
- **Surface:** `#FFFFFF` (Light) / `#1A1A19` (Dark).
- **Handle:** Center-aligned grab handle (`36px` width, `5px` height, radius `2.5px`, fill `#D1CFCA`). Margin top: `8px`.
- **Border:** `1px` hairline running continuously along the top perimeter.

### Data Rings & Metric Displays
- **Score Indicators:** Concentric progress rings with a fixed `8px` or `12px` stroke weight.
- **Track Color:** Neutral track set to `#E7E5E0` (Light) / `#2A2A28` (Dark).
- **Active Stroke:** Strict mapping to data palette (`#4B5FD6`, `#1F9E8F`, etc.) with clean rounded caps and tabular numeric display centered at `headline-xl`.