# ApplyPilot Design System & Token Specification (`docs/design-system.md`)

*Minimalist, restrained, editorial engineering cockpit. No AI hype, no neon glows, no glassmorphism, no gradient fills.*

---

## 1. Core Philosophy & Direction
- **Identity**: Single-tenant autonomous career engine for a verified engineering candidate.
- **Aesthetic**: Instrument-grade precision. High contrast, muted chromas, hairline borders, single accent tone.
- **One Accent Rule**: A single calm sage green in dark mode (`#7FD1A8`) and deep forest green in light mode (`#2F6F4F`). Never combine multiple decorative hues.
- **Containment**: A single layer of containment with hairline 1px borders. Zero drop shadows.

---

## 2. Color System & Tokens

### Dark Theme (Default)
| Token | Hex Value | Role | Contrast vs BG |
|:---|:---|:---|:---|
| `bg` | `#0E0F0E` | Main canvas background | — |
| `surface` | `#161816` | Cards, app bars, sheets | 1.15:1 |
| `raised` | `#1C1F1C` | Dialogs, elevated chips | 1.25:1 |
| `border` | `#262926` | 1px hairline borders | 1.4:1 |
| `text` | `#ECEEEC` | Primary headings & high-emphasis copy | 14.8:1 (AAA) |
| `muted` | `#8A908A` | Subtitles, timestamps, captions | 5.2:1 (AA) |
| `accent` | `#7FD1A8` | Single accent: active tabs, primary actions | 9.8:1 (AAA) |
| `warning` | `#E6B450` | Attention indicator, Needs You badge | 8.5:1 (AAA) |
| `danger` | `#E5736B` | Paused states, errors, blockers | 6.8:1 (AA) |

### Light Theme (System Follower)
| Token | Hex Value | Role | Contrast vs BG |
|:---|:---|:---|:---|
| `bg` | `#FAFAF7` | Warm off-white canvas | — |
| `surface` | `#FFFFFF` | Cards, app bars, sheets | 1.05:1 |
| `raised` | `#F0F0EC` | Neutral input backgrounds | 1.12:1 |
| `border` | `#E3E3DE` | 1px hairline card borders | 1.28:1 |
| `text` | `#111111` | Primary text and headers | 17.5:1 (AAA) |
| `muted` | `#6E736E` | Secondary captions, timestamps | 5.0:1 (AA) |
| `accent` | `#2F6F4F` | Single deep green accent | 5.8:1 (AA) |
| `warning` | `#996500` | Warning, pending actions | 4.8:1 (AA) |
| `danger` | `#C0392B` | Alert, errors, blockers | 5.1:1 (AA) |

---

## 3. Typography Scale (Inter)
Font family: `Inter, -apple-system, BlinkMacSystemFont, sans-serif`.
Weights: strictly `400` (Regular) and `600` (SemiBold).
Tabular figures (`fontFeatures: [FontFeature.tabularFigures()]`) applied to all numerical data, timers, and metrics. Zero extra letter spacing.

| Token | Size | Weight | Line Height | Purpose |
|:---|:---|:---|:---|:---|
| `displayLarge` | 32sp | 600 | 38sp | Hero counters (e.g. "42 / 100") |
| `displayMedium` | 22sp | 600 | 28sp | Screen titles, section anchors |
| `title` | 16sp | 600 | 22sp | Card titles, modal sheet headings |
| `body` | 14sp | 400 | 20sp | Primary body text, descriptions |
| `caption` | 12sp | 400 | 16sp | Metadata, status text, timestamps |

---

## 4. Spacing & Geometry
- **Grid**: Strictly 8-pt base grid (8, 16, 24, 32, 48).
- **Margins**: Screen outer margin = 16dp. Section separation = 24dp.
- **Card Geometry**: Corner radius = 16px. Border = 1px solid `border`. Drop shadows = None (0 elevation).
- **Interactive Targets**: Minimum tap target size = 48×48 dp.
- **App Bar**: Surface color (`#161816` / `#FFFFFF`), 0 tint, 1px bottom border.
- **Bottom Navigation**: Surface color, regular-weight labels, small accent indicator dot (no pill backgrounds).

---

## 5. Status & Score Indicators
- **Status Representation**: Small 6px colored dot + text label (Never tinted full-bleed pills).
  - Active / Submitted: `#7FD1A8` dot + "Applied" / "Live"
  - Paused / Circuit Breaker: `#E5736B` dot + "Paused: circuit breaker"
  - Needs You / Pending: `#E6B450` dot + "Needs You"
  - Dry-Run / Neutral: `#8A908A` dot + "Dry-Run"
- **Fit Score**: Colored dot + tabular number (e.g., `● 4.3`).

---

## 6. Motion & Animation Timing
- **Standard Duration**: 150ms – 250ms.
- **Easing Curve**: `Cubic(0.2, 0.0, 0.0, 1.0)` (Standard clean ease-out). No bouncy springs.
- **Number Transitions**: Smooth rolling tabular count-up on load (150ms).
- **Tabs**: Shared-axis fade & subtle horizontal slide.

---

## 7. State Foundations
Every screen defines 3 essential states:
1. **Empty State**: Centered icon, one concise line of text (e.g., "No jobs pending in queue"), one primary action button.
2. **Loading State**: Content-shaped skeleton placeholders using subtle pulse between `surface` and `raised`.
3. **Error State**: Concise neutral description, single "Retry" action.
