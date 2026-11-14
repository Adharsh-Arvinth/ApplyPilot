# ApplyPilot Design System

*Crafted under Damir Sokolovsky's [unslop](https://github.com/heydamir/unslop) principles. Modern minimalist, calm, editorial.*

---

## 1. Creative Direction

- **Product**: Autonomous job application cockpit for a high-performing engineering candidate.
- **Character**: `Calm, exact, editorial`. No AI hype words, no glowing gradients, no floating decorative orbs.
- **World**: Analog ivory paper, India ink, precision chronometer instruments.
- **Moments**:
  1. *The Daily Application Gauge*: A crisp hairline circular gauge tracking applications against the daily cap with tabular numbers.
  2. *The Application Proof Sheet*: Side-by-side view of the ATS submission screenshot and the tailored resume text diff.
- **Signature**: A discreet 6px live status indicator (`● PC Active — 14ms`) in quiet Geist Mono.

---

## 2. Color Palette & Roles

Built around a single tinted warm neutral ramp with quiet chrome and one restrained deep green accent.

| Token Name | Light Value | Dark Value | Purpose |
|:---|:---|:---|:---|
| `canvas` | `#FAFAF7` | `#121212` | Main screen background |
| `surface` | `#FFFFFF` | `#1C1C1C` | Raised cards, modal sheets |
| `surfaceSubtle` | `#F4F4F0` | `#242424` | Input fields, chips, secondary surfaces |
| `borderHairline` | `#E7E6E0` | `#2D2D2D` | 1dp hairline component borders |
| `textPrimary` | `#111111` | `#F0F0EE` | Headings, key figures |
| `textSecondary`| `#555550` | `#9E9E98` | Subtitles, labels, descriptions |
| `textMuted` | `#8E8E88` | `#666662` | Timestamps, counters, captions |
| `accent` | `#1B4332` | `#52B788` | Primary button, active switch, selection |
| `accentOnAccent`| `#FFFFFF` | `#111111` | Text rendered on top of accent |
| `semanticWarning`| `#7A5C2E` | `#DDA15E` | "Needs You" badge & attention indicator |
| `semanticBlocked`| `#8A2828` | `#E57373` | Exclusions, errors, skipped jobs |

**Unslop Rules**:
- No hue-to-hue gradients.
- No colored shadows (all elevation via hairline 1dp borders and 1px neutral shadows at 4% opacity).
- No saturated icon backgrounds or emoji badges.

---

## 3. Spacing System (4-pt Grid)

All layout paddings, margins, gaps, and heights are strictly multiples of 4:
- `space-4`: 4dp (nudge / micro-gap)
- `space-8`: 8dp (gap between icon and label, chip padding)
- `space-12`: 12dp (internal card element separation)
- `space-16`: 16dp (standard card interior padding)
- `space-20`: 20dp (large card padding)
- `space-24`: 24dp (screen gutter / outer padding)
- `space-32`: 32dp (section gap)

---

## 4. Typography Scale

- **Family**: Inter or Geist, paired with Geist Mono for numbers and metadata.
- **Font Feature Settings**: `['tnum']` (tabular numbers enabled globally).
- **Scale**:
  - `Display Large`: 32sp, weight 500, tabular figures.
  - `Display Medium`: 24sp, weight 500, tabular figures.
  - `Title`: 18sp, weight 500, sentence case.
  - `Body`: 14sp, weight 400, line height 1.45.
  - `Body Medium`: 14sp, weight 500.
  - `Caption`: 12sp, weight 400, Geist Mono, muted.

---

## 5. Component Geometry (Nested Radii)

- Outer Radius = Inner Radius + Padding.
  - Cards: `radius: 16dp`, border: `1dp #E7E6E0`.
  - Buttons & Inputs: `radius: 8dp`.
  - Chips & Badges: `radius: 4dp`.
- Touch Targets: Guaranteed minimum `48x48dp` tap targets.

---

## 6. Iconography & Copy

- **Icons**: Lucide outline icons, `18dp` size, `1.5dp` stroke.
- **Copy Guidelines**:
  - Sentence case everywhere (e.g., `Today's queue`, never `TODAY'S QUEUE`).
  - No exclamation marks in UI text.
  - Comparisons must state their reference (`+12 vs yesterday`).
  - Labels are concise: `Search`, `Pause queue`, `Save & resume`.
