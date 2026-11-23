---
name: Academic Institutional Modern
colors:
  surface: '#f9f9ff'
  surface-dim: '#cfdaf2'
  surface-bright: '#f9f9ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f0f3ff'
  surface-container: '#e7eeff'
  surface-container-high: '#dee8ff'
  surface-container-highest: '#d8e3fb'
  on-surface: '#111c2d'
  on-surface-variant: '#44474d'
  inverse-surface: '#263143'
  inverse-on-surface: '#ecf1ff'
  outline: '#75777e'
  outline-variant: '#c4c6ce'
  surface-tint: '#4f5f79'
  primary: '#000e23'
  on-primary: '#ffffff'
  primary-container: '#13243b'
  on-primary-container: '#7b8ca7'
  inverse-primary: '#b7c7e5'
  secondary: '#006a65'
  on-secondary: '#ffffff'
  secondary-container: '#93f0e8'
  on-secondary-container: '#006f69'
  tertiary: '#170c00'
  on-tertiary: '#ffffff'
  tertiary-container: '#332001'
  on-tertiary-container: '#a4865c'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#d4e3ff'
  primary-fixed-dim: '#b7c7e5'
  on-primary-fixed: '#0a1c33'
  on-primary-fixed-variant: '#374760'
  secondary-fixed: '#96f3eb'
  secondary-fixed-dim: '#79d6cf'
  on-secondary-fixed: '#00201e'
  on-secondary-fixed-variant: '#00504c'
  tertiary-fixed: '#ffddb1'
  tertiary-fixed-dim: '#e4c192'
  on-tertiary-fixed: '#291800'
  on-tertiary-fixed-variant: '#5a431e'
  background: '#f9f9ff'
  on-background: '#111c2d'
  surface-variant: '#d8e3fb'
typography:
  display-kpi:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.02em
  display-kpi-compact:
    fontFamily: Inter
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 36px
    letterSpacing: -0.02em
  headline-page:
    fontFamily: Inter
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 36px
    letterSpacing: -0.02em
  headline-page-mobile:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '700'
    lineHeight: 32px
    letterSpacing: -0.01em
  headline-section:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
    letterSpacing: -0.01em
  headline-card:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '600'
    lineHeight: 24px
  body-primary:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  body-secondary:
    fontFamily: Inter
    fontSize: 13px
    fontWeight: '400'
    lineHeight: 18px
  caption:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
  button-text:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 20px
    letterSpacing: 0.01em
  badge-label:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
  table-header:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.04em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  gutter: 1.5rem
  gutter-mobile: 1rem
  margin: 2rem
  margin-mobile: 1rem
  space-2xs: 0.25rem
  space-xs: 0.5rem
  space-sm: 0.75rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2rem
  space-2xl: 2.5rem
  space-3xl: 3rem
---

## Brand & Style

This design system establishes an authoritative, dependable, and efficient visual framework tailored for university governance, club administrations, student bodies, and campus event organizers. It reflects the operational gravity of higher education institutions while maintaining friction-free consumer utility for student life.

### Design Movement: Modern Corporate & Institutional

The aesthetic operates firmly within modern institutional standards:
- **Clean Structure:** Built on rigorous structural alignment, visible containment, and quiet functional hierarchy.
- **Dignified Restraint:** Strictly no glassmorphism, no neon highlights, and no decorative rainbow gradients. Surface depth is communicated via subtle boundary borders rather than expressive lighting.
- **Academic Trust:** Grounded in deep architectural navy and institutional teal accents that convey authority, fiscal reliability, and scholastic prestige.
- **Iconography:** Cohesive 1.5px to 2px monoline outline icons (Lucide icon style) rendered at 16px, 20px, and 24px bounding boxes, matching text colors precisely.

### Localization & Contextual Conventions
- **Currency:** Formatted with ISO prefix `LKR` and localized thousands separators (e.g., `LKR 2,500.00`).
- **Date Formatting:** Explicit alphanumeric day-month-year convention (`DD MMM YYYY`, e.g., `02 Nov 2026`) to avoid ambiguity between student administrative cycles.
- **Time Representation:** Standard 12-hour meridiem format (`h:mm A`, e.g., `9:30 AM`).

## Colors

The color architecture enforces accessibility, contrast compliance, and role-based chromatic semantics across administrative dashboards and public-facing event directories.

### Core Swatches
- **Primary Brand (Deep Navy):** `#13243B` — Used for main navigation structures, top headers, primary buttons, and key brand anchors.
- **Primary Hover:** `#1D3553` — Interactive state transition for primary brand elements.
- **Accent Brand (Scholastic Teal):** `#087E78` — Focus rings, active states, key interactive links, secondary action triggers, and publication tags.
- **Accent Hover:** `#066862` — Interaction state for accent surfaces.

### Surfaces & Backgrounds
- **App Canvas:** `#F4F7FB` — Cool, low-saturation slate foundation providing separation from white content containers.
- **Card & Modal Surface:** `#FFFFFF` — Primary elevated surface for content density and readability.
- **Secondary Surface:** `#EEF2F6` — Structural sidebars, table headers, inactive tabs, and segmented control wells.
- **Input Field Background:** `#FFFFFF` — Distinct crisp focus layer against modal and page backgrounds.

### Typography Hierarchy
- **Primary Text:** `#1E293B` — High-contrast slate for headings, active labels, and primary body content (WCAG AAA compliant against white).
- **Secondary Text:** `#64748B` — Sub-headings, metadata, table headers, and supporting descriptions.
- **Muted Text:** `#94A3B8` — Placeholders, non-interactive hints, disabled counters, and icons.
- **Text on Dark:** `#FFFFFF` — Applied against primary navy surfaces and status chips.

### Structural Lines
- **Default Border:** `#DFE6EE` — 1px outer stroke for cards, input fields, containers, and structural dividers.
- **Subtle Dividers:** `#E8EDF2` — Horizontal table rules, nested list item lines, and metadata separators.

### State & Workflow Color Pairs
Status tokens follow a strict two-tone pairing (600/700 text paired with 50/100 tinted background):
- **Success:** `#15803D` text on `#ECFDF3` background (Approved bookings, completed payments, active clubs).
- **Warning / Pending:** `#B45309` text on `#FFF7E6` background (Pending Dean approval, awaiting venue confirmation).
- **Error / Cancelled:** `#B42318` text on `#FEF3F2` background (Rejected proposals, cancelled sessions, payment failures).
- **Information:** `#1D4ED8` text on `#EFF6FF` background (Important announcements, ticketing instructions).
- **Published:** `#087E78` text on `#E6F5F4` background (Publicly listed campus events).
- **Draft:** `#64748B` text on `#F1F5F9` background (Unsubmitted event proposals, staged announcements).

## Typography

The type scale leverages **Inter** across all roles, engineered for clarity in data-dense user interfaces, tabular university reports, and public schedules.

### Typography Guidelines
- **Tabular Figures:** For all metric tables, currency amounts (`LKR`), dates, and KPI values, apply OpenType tabular figure features (`tnum`) to maintain vertical column integrity.
- **Section Headers vs. Page Headers:** Never use `headline-page` within modular cards. Reserve `headline-page` exclusively for top-level view headers. Inside cards, dashboards, and modal components, start hierarchy with `headline-section` or `headline-card`.
- **Form Labels:** Field labels leverage `body-secondary` with a medium (`500`) or semibold (`600`) weight at 13px, while help text drops to `caption` (12px).
- **Table Headers:** All data table headers must use `table-header` in uppercase format with wide tracking (`letterSpacing: 0.04em`) using the Secondary Text color (`#64748B`).

## Layout & Spacing

The design system is governed by a strict 8-point spatial grid, using a half-step 4px unit exclusively for fine-grained alignment (micro-padding inside badges, icon offsets, and form input prefixes).

### Grid Increments
- **4px (`space-2xs`):** Sub-element spacing, badge vertical padding, icon-to-label gaps.
- **8px (`space-xs`):** Button vertical padding, dense table cell spacing, input field gaps.
- **12px (`space-sm`):** Stacked form field gaps, card header element gaps.
- **16px (`space-md`):** Component internal padding, standard layout gutter, toolbar spacing.
- **24px (`space-lg`):** Card inner padding, section separation, grid gutters on desktop.
- **32px (`space-xl`):** Primary section vertical spacing, modal padding.
- **40px (`space-2xl`):** Major workflow divisions, empty state margins.
- **48px (`space-3xl`):** Outer page wrapper padding and top-level layout sections.

### Responsive Layout Rules
- **Desktop (1024px+):** Fixed 260px administrative navigation sidebar on the left. The content area employs a 12-column fluid grid with 24px gutters (`gutter: 1.5rem`) and 32px canvas margins (`margin: 2rem`). Max container width: 1440px centered.
- **Tablet (768px - 1023px):** Collapsible sidebar, 8-column fluid grid, 16px gutters, 24px canvas margins.
- **Mobile (< 768px):** Off-canvas drawer navigation, 4-column fluid grid, 16px gutters (`gutter-mobile: 1rem`), and 16px screen margins (`margin-mobile: 1rem`).

## Elevation & Depth

Visual hierarchy relies on crisp borders and structured low-contrast tonal layering rather than heavy ambient or colored shadows. Depth is tactile, administrative, and restrained.

### Layering Model
- **Base Layer (Elevation 0):** Canvas background `#F4F7FB`.
- **Surface Layer (Elevation 1):** Cards, panels, and data tables `#FFFFFF` with a crisp structural border (`1px solid #DFE6EE`) and a micro-diffused shadow: `0 1px 2px 0 rgba(19, 36, 59, 0.05)`.
- **Interactive Hover Layer (Elevation 2):** Hovered cards and active menu items lift with an expanded subtle outline and shadow: `0 4px 6px -1px rgba(19, 36, 59, 0.07), 0 2px 4px -2px rgba(19, 36, 59, 0.05)`.
- **Overlay Layer (Elevation 3):** Dropdown menus, popovers, and date pickers use `#FFFFFF`, a `1px solid #DFE6EE` stroke, and `0 10px 15px -3px rgba(19, 36, 59, 0.08), 0 4px 6px -4px rgba(19, 36, 59, 0.04)`.
- **Modal & Drawer Layer (Elevation 4):** Campus approval dialogs, drawer panels, and event creation wizards use a deep backdrop scrim (`rgba(19, 36, 59, 0.45)`) paired with `0 20px 25px -5px rgba(19, 36, 59, 0.1), 0 8px 10px -6px rgba(19, 36, 59, 0.06)`.

## Shapes

The design system employs a geometric, structured radius system where corner values directly map to the component's functional footprint.

### Corner Radii Assignment
- **Badges & Status Chips:** 6px radius (`rounded-sm`). Compact, tag-like corners prevent visual noise across dense tabular listings.
- **Buttons, Inputs, & Form Elements:** 8px radius (`rounded-md`). Provides ergonomic touch and click feedback without drifting into casual rounded shapes.
- **Cards, Panels, & Modal Dialogs:** 12px radius (`rounded-lg`). Encapsulates content groups clearly while maintaining architectural alignment.
- **Avatar Elements:** 9999px (Circular) for individual student/faculty profiles; 8px (`rounded-md`) with 1px border for university club and society crests.

## Components

### Buttons
- **Primary Button:**
  - Background: `#13243B`; Text: `#FFFFFF`; Border: None.
  - Hover: `#1D3553`; Active: `#0D1929`.
  - Dimensions: Desktop height 40px (padding 0 16px); Mobile height 44px minimum touch target.
  - Border Radius: 8px. Typography: 14px Semibold (`button-text`).
- **Accent Button:**
  - Background: `#087E78`; Text: `#FFFFFF`.
  - Hover: `#066862`; Active: `#05524D`.
  - Used for positive conversion actions (e.g., "Publish Event", "Approve Proposal").
- **Secondary / Outline Button:**
  - Background: `#FFFFFF`; Text: `#1E293B`; Border: `1px solid #DFE6EE`.
  - Hover: Background `#EEF2F6`, Border `#CBD5E1`.
- **Destructive Button:**
  - Background: `#FEF3F2`; Text: `#B42318`; Border: `1px solid #FECDCA`.
  - Hover: Background `#FEE4E2`.

### Input Fields & Controls
- **Text Inputs & Dropdowns:**
  - Height: 40px desktop, 44px mobile.
  - Background: `#FFFFFF`; Border: `1px solid #DFE6EE`; Radius: 8px.
  - Padding: Horizontal 12px (`space-sm`).
  - Text: 14px Regular (`#1E293B`); Placeholder: `#94A3B8`.
  - Focus State: Border color `#087E78`; Ring: `0 0 0 3px rgba(8, 126, 120, 0.15)`. Outline: None.
  - Error State: Border color `#B42318`; Ring: `0 0 0 3px rgba(180, 35, 24, 0.12)`.
- **Checkboxes & Radios:**
  - Size: 18x18px (checkbox radius 4px; radio full circular).
  - Unchecked: Background `#FFFFFF`, Border `1.5px solid #DFE6EE`.
  - Checked: Background `#087E78`, Border `#087E78`, White interior checkmark icon.

### Status Badges & Chips
- Corner radius: 6px. Padding: 4px 10px (`space-2xs` vertical, `space-xs`+2px horizontal).
- Typography: 12px Semibold (`badge-label`).
- Variants:
  - **Success:** Text `#15803D`, BG `#ECFDF3`, Border `1px solid rgba(21, 128, 61, 0.15)`.
  - **Warning / Pending:** Text `#B45309`, BG `#FFF7E6`, Border `1px solid rgba(180, 83, 9, 0.15)`.
  - **Error / Cancelled:** Text `#B42318`, BG `#FEF3F2`, Border `1px solid rgba(180, 35, 24, 0.15)`.
  - **Information:** Text `#1D4ED8`, BG `#EFF6FF`, Border `1px solid rgba(29, 78, 216, 0.15)`.
  - **Published:** Text `#087E78`, BG `#E6F5F4`, Border `1px solid rgba(8, 126, 120, 0.20)`.
  - **Draft:** Text `#64748B`, BG `#F1F5F9`, Border `1px solid rgba(100, 116, 139, 0.15)`.

### Cards & Panels
- Background: `#FFFFFF`; Border: `1px solid #DFE6EE`; Radius: 12px.
- Internal Padding: 24px (`space-lg`) on desktop; 16px (`space-md`) on mobile.
- Card Header: Displays `headline-card` (16px, 600) with a bottom divider `1px solid #E8EDF2` when separating distinct sub-panels.

### KPI Stat Cards
- Background: `#FFFFFF`; Radius: 12px; Border: `1px solid #DFE6EE`; Padding: 20px.
- Structure:
  - Header: 13px Regular (`#64748B`) with optional Lucide icon (20px) top right.
  - Value: 28px-32px Bold (`#1E293B`) using tabular numerals (`display-kpi`).
  - Context Footer: 12px Regular (`#64748B`) displaying comparative trends or timestamps.

### Data Tables
- Header Row: Background `#EEF2F6`, Border bottom `1px solid #DFE6EE`.
- Header Cells: 12px Semibold (`#64748B`), uppercase, tracking 0.04em, padding 12px 16px.
- Data Rows: Height 52px; Background `#FFFFFF`, Border bottom `1px solid #E8EDF2`. Hover state: `#F8FAFC`.
- Action Columns: Fixed right alignment with 32px icon buttons (`#64748B`).