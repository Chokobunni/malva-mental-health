# UI/UX Design Specification

**Malva Mental Health App**

| Field | Value |
|---|---|
| Platform | Android (primary), Web, Windows Desktop |
| Design System | Material 3 |
| Theme | Light + Dark mode |
| Date | 2026-07-30 |

---

## 1. Design Principles

| Principle | Description |
|---|---|
| **Calming** | Soft colors, rounded corners, minimal visual noise |
| **Accessible** | Clear typography, sufficient contrast, intuitive navigation |
| **Consistent** | Unified spacing, iconography, and interaction patterns |
| **Privacy-first** | Sensitive data protected, clear consent controls |
| **Professional** | Clean dashboard for clinical workflows |

## 2. Color System

### 2.1 Primary Palette

| Name | Light Mode | Dark Mode | Usage |
|---|---|---|---|
| Primary | `#6750A4` | `#D0BCFF` | Buttons, links, active states |
| On Primary | `#FFFFFF` | `#381E72` | Text on primary |
| Primary Container | `#EADDFF` | `#4F378B` | FAB, chips |
| Secondary | `#625B71` | `#CCC2DC` | Secondary actions |
| Tertiary | `#7D5260` | `#EFB8C8` | Accent elements |
| Error | `#B3261E` | `#F2B8B5` | Error states |

### 2.2 Malva Custom Colors

| Name | Hex | Usage |
|---|---|---|
| Orchid | `#B388FF` | Primary brand color |
| Calm Blue | `#82B1FF` | Positive states |
| Warm Amber | `#FFD54F` | Warning states |
| Soft Green | `#69F0AE` | Success states |
| Alert Red | `#FF5252` | Crisis / critical |

### 2.3 Mood Colors

| Mood | Color | Icon |
|---|---|---|
| Great | `#69F0AE` (Green) | `sentiment_very_satisfied` |
| Good | `#82B1FF` (Blue) | `sentiment_satisfied_alt` |
| Okay | `#FFD54F` (Amber) | `sentiment_neutral` |
| Sad | `#FFAB40` (Orange) | `sentiment_dissatisfied` |
| Awful | `#FF5252` (Red) | `sentiment_very_dissatisfied` |

## 3. Typography

### 3.1 Type Scale

| Style | Size | Weight | Usage |
|---|---|---|---|
| Display Large | 57sp | Regular | Hero headings |
| Display Medium | 45sp | Regular | Section titles |
| Headline Large | 32sp | Regular | Screen titles |
| Headline Medium | 28sp | Regular | Card titles |
| Title Large | 22sp | Medium | AppBar titles |
| Title Medium | 16sp | Medium | List item titles |
| Body Large | 16sp | Regular | Body text |
| Body Medium | 14sp | Regular | Secondary text |
| Body Small | 12sp | Regular | Captions |
| Label Large | 14sp | Medium | Buttons |
| Label Medium | 12sp | Medium | Chips, badges |

### 3.2 Font Family

- **Android:** Roboto (system default)
- **Web:** Roboto
- **Windows:** Segoe UI

## 4. Spacing System

| Token | Value | Usage |
|---|---|---|
| `space-xs` | 4px | Icon padding |
| `space-sm` | 8px | Tight spacing |
| `space-md` | 16px | Standard padding |
| `space-lg` | 24px | Section spacing |
| `space-xl` | 32px | Large gaps |
| `space-xxl` | 48px | Screen margins |

## 5. Border Radius

| Token | Value | Usage |
|---|---|---|
| `radius-sm` | 8px | Small chips, badges |
| `radius-md` | 12px | Cards, buttons |
| `radius-lg` | 16px | Bottom sheets, dialogs |
| `radius-xl` | 28px | FAB, large buttons |

## 6. Screen Layouts

### 6.1 Splash Screen

```
┌─────────────────────────┐
│                         │
│                         │
│      [Malva Logo]       │
│                         │
│       "Hello!"          │
│      "Welcome to"       │
│      "Malva"            │
│                         │
│                         │
└─────────────────────────┘
```

Duration: 1.8 seconds, then transitions to Login or Home.

### 6.2 Login Screen

```
┌─────────────────────────┐
│  [Back]     Malva Login │
├─────────────────────────┤
│                         │
│  Email                  │
│  ┌───────────────────┐  │
│  │ user@email.com    │  │
│  └───────────────────┘  │
│                         │
│  Password               │
│  ┌───────────────────┐  │
│  │ ••••••••          │  │
│  └───────────────────┘  │
│                         │
│  Role: [Patient] [Prof] │
│                         │
│  [Professional ID]      │
│  ┌───────────────────┐  │
│  │ 1234567890123456  │  │
│  └───────────────────┘  │
│                         │
│  ┌───────────────────┐  │
│  │      Login        │  │
│  └───────────────────┘  │
│                         │
│  Belum punya akun?      │
│  [Daftar di sini]       │
│                         │
└─────────────────────────┘
```

### 6.3 Patient Shell (Bottom Navigation)

```
┌─────────────────────────┐
│         AppBar          │
├─────────────────────────┤
│                         │
│      Active Page        │
│      (IndexedStack)     │
│                         │
│                         │
├─────────────────────────┤
│  🏠  😊  💊  📝  💬  ⋯  │
│ Home Mood Med  Diary Chat More│
└─────────────────────────┘
```

### 6.4 Home Screen (Patient)

```
┌─────────────────────────┐
│  Good morning, User!    │
│  How are you today?     │
├─────────────────────────┤
│  ┌───────────────────┐  │
│  │  😊  Check-in     │  │
│  │  Mood harianmu    │  │
│  └───────────────────┘  │
│                         │
│  ┌───────────────────┐  │
│  │  💊  Obat         │  │
│  │  Sertraline 50mg  │  │
│  │  [Take Now]       │  │
│  └───────────────────┘  │
│                         │
│  ┌───────────────────┐  │
│  │  📋  Screening    │  │
│  │  PHQ-9 + GAD-7    │  │
│  └───────────────────┘  │
│                         │
│  ┌───────────────────┐  │
│  │  💬  Chat         │  │
│  │  Dr. Budi Sp.KJ.  │  │
│  └───────────────────┘  │
│                         │
│  ┌───────────────────┐  │
│  │  🚨  Crisis       │  │
│  │  Butuh bantuan?   │  │
│  └───────────────────┘  │
│                         │
├─────────────────────────┤
│  🏠  😊  💊  📝  💬  ⋯  │
└─────────────────────────┘
```

### 6.5 Mood Screen

```
┌─────────────────────────┐
│  ←  Mood Check-in       │
├─────────────────────────┤
│                         │
│  How are you today?     │
│                         │
│  😄  😊  😐  😟  😢     │
│ Great Good Okay Sad Awful│
│                         │
│  Sleep: [7.5] hours     │
│  ──●────────────── 0-24 │
│                         │
│  Energy:    [4] /10     │
│  Anxiety:   [2] /10     │
│  Irritable: [1] /10     │
│                         │
│  Note:                  │
│  ┌───────────────────┐  │
│  │ Feeling good today│  │
│  └───────────────────┘  │
│                         │
│  ┌───────────────────┐  │
│  │    Save Check-in  │  │
│  └───────────────────┘  │
│                         │
│  ── Chart ──            │
│  [Mood trend line]      │
│                         │
├─────────────────────────┤
│  🏠  😊  💊  📝  💬  ⋯  │
└─────────────────────────┘
```

### 6.6 Medication Screen

```
┌─────────────────────────┐
│  ←  Medications         │
├─────────────────────────┤
│                         │
│  ┌───────────────────┐  │
│  │ 💊 Sertraline     │  │
│  │ 50mg tablet       │  │
│  │ ⏰ 08:00 after meal│  │
│  │ 📦 Stock: 30      │  │
│  │ [Take Now]        │  │
│  └───────────────────┘  │
│                         │
│  ┌───────────────────┐  │
│  │ + Add Medication  │  │
│  └───────────────────┘  │
│                         │
│  ── History ──          │
│  ✅ 08:05 - Taken       │
│  ✅ 08:02 - Taken       │
│  ❌ 08:10 - Missed      │
│                         │
├─────────────────────────┤
│  🏠  😊  💊  📝  💬  ⋯  │
└─────────────────────────┘
```

### 6.7 Chat Screen

```
┌─────────────────────────┐
│  ←  Dr. Budi Sp.KJ.    │
│     ● Online             │
├─────────────────────────┤
│                         │
│         Halo Doc!       │
│              10:00 👤   │
│                         │
│   10:05 👤              │
│         Ada yang bisa   │
│         saya bantu?     │
│                         │
│         Bagaimana       │
│         kondisi saya?   │
│              10:10 👤   │
│                         │
│   10:12 👤              │
│         Skor screening  │
│         Anda ringan...  │
│                         │
│  ┌───────────────────┐  │
│  │ Type a message... │  │
│  └───────────────────┘  │
├─────────────────────────┤
│  🏠  😊  💊  📝  💬  ⋯  │
└─────────────────────────┘
```

### 6.8 Professional Dashboard

```
┌─────────────────────────┐
│  Dashboard  [Logout]    │
├─────────────────────────┤
│                         │
│  📊 Overview            │
│  ┌────┐ ┌────┐ ┌────┐  │
│  │  5 │ │  2 │ │  1 │  │
│  │Pat.│ │Cris│ │Pend│  │
│  └────┘ └────┘ └────┘  │
│                         │
│  🚨 Crisis Alerts       │
│  ┌───────────────────┐  │
│  │ Patient A - High  │  │
│  │ [Review Now]      │  │
│  └───────────────────┘  │
│                         │
│  📋 Pending Reviews     │
│  ┌───────────────────┐  │
│  │ Patient B - PHQ-9 │  │
│  │ [Review]          │  │
│  └───────────────────┘  │
│                         │
│  👥 My Patients         │
│  ┌───────────────────┐  │
│  │ Patient A  ● Onln │  │
│  │ Patient B         │  │
│  │ Patient C  ● Onln │  │
│  └───────────────────┘  │
│                         │
│  [CSV Export]           │
│                         │
├─────────────────────────┤
│  📊  👥  📋  💬  ⋯     │
│ Dash Pat  Rev Chat More │
└─────────────────────────┘
```

### 6.9 Consent Management

```
┌─────────────────────────┐
│  ←  Consent Management  │
├─────────────────────────┤
│                         │
│  Share data with:       │
│                         │
│  Dr. Budi Sp.KJ.        │
│  ┌───────────────────┐  │
│  │ ✅ Screenings     │  │
│  │ ✅ Mood & Diary   │  │
│  │ ✅ Medications    │  │
│  │ ❌ Timeline       │  │
│  └───────────────────┘  │
│                         │
│  Dr. Hafid Sp.KJ.       │
│  ┌───────────────────┐  │
│  │ ✅ Screenings     │  │
│  │ ❌ Mood & Diary   │  │
│  │ ❌ Medications    │  │
│  │ ❌ Timeline       │  │
│  └───────────────────┘  │
│                         │
└─────────────────────────┘
```

## 7. Navigation Flow

### 7.1 Patient Flow

```
Splash → Login → Patient Shell
                    ├── Home
                    │   ├── Mood Check-in
                    │   ├── Medication
                    │   ├── Screening (PHQ-9 + GAD-7)
                    │   ├── Chat
                    │   └── Crisis Alert
                    ├── Mood
                    ├── Medication
                    ├── Diary
                    ├── Chat
                    └── More
                        ├── Consent Management
                        ├── Goals
                        ├── Health Record
                        └── Logout
```

### 7.2 Professional Flow

```
Splash → Login → Professional Dashboard
                    ├── Patient List
                    │   ├── Patient Detail
                    │   │   ├── Screening History
                    │   │   ├── Mood History
                    │   │   ├── Diary History
                    │   │   ├── Medication History
                    │   │   ├── Timeline
                    │   │   └── Chat
                    │   └── Review Screening
                    ├── Notes
                    ├── Follow-ups
                    └── Logout
```

## 8. Interaction Patterns

### 8.1 Pull to Refresh

All list screens support pull-to-refresh.

### 8.2 Swipe Actions

- Medication logs: swipe to delete
- Diary entries: swipe to delete

### 8.3 Confirmation Dialogs

| Action | Dialog |
|---|---|
| Submit screening | "Are you sure? Review your answers before submitting." |
| Take medication | "Confirm: Take [Medication Name] now?" |
| Delete entry | "Delete this entry? This cannot be undone." |
| Logout | "Are you sure you want to logout?" |

### 8.4 Error Handling

| Error Type | Display |
|---|---|
| Network error | SnackBar: "Network error. Please try again." |
| Auth error | Redirect to Login screen |
| Validation error | Inline field error |
| Server error | SnackBar: "Server error. Please try again later." |

## 9. Accessibility

| Feature | Implementation |
|---|---|
| Screen reader | Semantic labels on all interactive elements |
| Minimum touch target | 48x48 dp |
| Color contrast | WCAG AA (4.5:1 for text) |
| Text scaling | Supports system font size |
| Dark mode | Full dark theme support |

## 10. Responsive Breakpoints

| Breakpoint | Width | Layout |
|---|---|---|
| Mobile | < 600px | Single column, bottom nav |
| Tablet | 600-1200px | Two-column possible |
| Desktop | > 1200px | Side nav or expanded layout |

## 11. Animation Guidelines

| Element | Duration | Curve |
|---|---|---|
| Page transition | 300ms | `easeInOut` |
| Bottom nav indicator | 250ms | `easeInOut` |
| Card tap | 150ms | `easeOut` |
| FAB scale | 200ms | `easeOutBack` |
| Loading spinner | Continuous | `linear` |
| Splash fade | 1.8s | `easeInOut` |
