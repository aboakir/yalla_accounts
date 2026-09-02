# Yalla Accounts Mobile V2 — Design Foundation

P01 introduces an isolated design foundation. Existing screens do not consume it until their
own approved phase, which prevents an accidental whole-application visual change.

## Core tokens

- Brand green: `#59C414`
- Brand dark: `#2F6F38`
- Canvas: `#F7F9F8`
- Surface: `#FFFFFF`
- Text: `#172019`
- Muted text: `#6D756F`
- Border: `#DDE4DF`
- Danger: `#D93232`
- Warning: `#E69500`
- Information: `#2878D4`

## Geometry

- Spacing scale: 4, 8, 12, 16, 20, 24, 32.
- Card radius: 20.
- Field/button radius: 16.
- Minimum touch target: 48.
- Standard horizontal page padding: 16 on phone, 24 on tablet, 32 on desktop.

## Breakpoints

- Phone: width below 600.
- Tablet: width from 600 through 1023.
- Desktop: width 1024 or more.

## Rules

1. Arabic RTL is the default interaction direction.
2. One main action per screen.
3. Cards communicate one decision or one record; no desktop table squeezed into a phone.
4. Money, date, time, phone, and mixed-direction text use one formatter later in the plan.
5. Loading, empty, error/retry, offline, and syncing states are mandatory for every feature.
6. Red is reserved for a financial or destructive warning, not decoration.
