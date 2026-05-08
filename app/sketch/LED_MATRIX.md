# LED Matrix — Icons & Status Bar

The Arduino UNO Q has a **13 × 8** grayscale LED matrix.
The MCU firmware (`sketch.ino`) manages it entirely locally — no Bridge call needed.

## Pixel encoding

| Value | Char | Meaning                  |
|-------|------|--------------------------|
| 0     | `.`  | off                      |
| 1–2   | `·`  | dim                      |
| 3–5   | `o`  | medium                   |
| 6–7   | `#`  | full brightness          |

## Layout — 13 columns

```
cols  0 – 9   icon area   (10 cols)
col  10        dim separator
cols 11 – 12   status bar  (2 cols)
```

---

## Event icons (cols 0 – 9)

### IDLE — hollow ring (quiescent)
```
     0  1  2  3  4  5  6  7  8  9
     ─────────────────────────────
 0:  .  .  .  .  .  .  .  .  .  .
 1:  .  .  .  #  #  #  #  #  .  .
 2:  .  .  #  .  .  .  .  .  #  .
 3:  .  .  #  .  .  .  .  .  #  .
 4:  .  .  #  .  .  .  .  .  #  .
 5:  .  .  #  .  .  .  .  .  #  .
 6:  .  .  .  #  #  #  #  #  .  .
 7:  .  .  .  .  .  .  .  .  .  .
```

### PRESENCE — person silhouette
```
     0  1  2  3  4  5  6  7  8  9
     ─────────────────────────────
 0:  .  .  .  .  #  #  .  .  .  .   ← head
 1:  .  .  .  .  #  #  .  .  .  .   ← head
 2:  .  .  .  .  .  .  .  .  .  .   ← neck gap
 3:  .  .  .  #  #  #  #  .  .  .   ← shoulders
 4:  .  .  .  .  #  #  .  .  .  .   ← torso
 5:  .  .  .  .  #  #  .  .  .  .   ← torso
 6:  .  .  .  #  .  .  #  .  .  .   ← legs
 7:  .  .  .  #  .  .  #  .  .  .   ← legs
```

### ANOMALY — exclamation mark  `!`
```
     0  1  2  3  4  5  6  7  8  9
     ─────────────────────────────
 0:  .  .  .  .  #  #  .  .  .  .   ← stem
 1:  .  .  .  .  #  #  .  .  .  .   ← stem
 2:  .  .  .  .  #  #  .  .  .  .   ← stem
 3:  .  .  .  .  #  #  .  .  .  .   ← stem
 4:  .  .  .  .  o  o  .  .  .  .   ← fade (brightness 4)
 5:  .  .  .  .  .  .  .  .  .  .   ← gap
 6:  .  .  .  .  #  #  .  .  .  .   ← dot
 7:  .  .  .  .  #  #  .  .  .  .   ← dot
```

### TRIGGER — play/forward arrow  `▶`
```
     0  1  2  3  4  5  6  7  8  9
     ─────────────────────────────
 0:  .  .  #  .  .  .  .  .  .  .
 1:  .  .  #  #  .  .  .  .  .  .
 2:  .  .  #  #  #  .  .  .  .  .
 3:  .  .  #  #  #  #  .  .  .  .
 4:  .  .  #  #  #  #  #  .  .  .
 5:  .  .  #  #  #  .  .  .  .  .
 6:  .  .  #  #  .  .  .  .  .  .
 7:  .  .  #  .  .  .  .  .  .  .
```

---

## Status bar (cols 10 – 12, always overlaid)

```
  col:  10   11  12
        ──   ──────
row 0:  │    W   W   ┐
row 1:  │    W   W   ┘ 🌐 Web UI running   bright=5 always
row 2:  │    M   M   ┐
row 3:  │    M   M   ┘ 🎤 Mic mode         bright=5 live / off=mock
row 4:  │    B   B   ┐
row 5:  │    B   B   ┘ 🔌 Bridge / MCU     bright=5 when connected
row 6:  │    ♥   ♥   ┐
row 7:  │    ♥   ♥   ┘ ❤️  Heartbeat       pulses dim(2) ↔ medium(5) on each event
```

`│` col 10 is always dim (brightness 1) — acts as a visual separator.

### Status indicator key

| Rows | Symbol | Meaning                              |
|------|--------|--------------------------------------|
| 0–1  | W  🌐  | Web UI — bright when server running  |
| 2–3  | M  🎤  | Mic — bright = live MCU mic, off = mock mode |
| 4–5  | B  🔌  | Bridge — bright when MCU connected   |
| 6–7  | ♥  ❤️  | Heartbeat — alternates 2 ↔ 5 on every event |

---

## Full frame example — PRESENCE event

```
     0  1  2  3  4  5  6  7  8  9  │ 11 12
     ──────────────────────────────────────
 0:  .  .  .  .  #  #  .  .  .  .  │  W  W
 1:  .  .  .  .  #  #  .  .  .  .  │  W  W
 2:  .  .  .  .  .  .  .  .  .  .  │  M  M
 3:  .  .  .  #  #  #  #  .  .  .  │  M  M
 4:  .  .  .  .  #  #  .  .  .  .  │  B  B
 5:  .  .  .  .  #  #  .  .  .  .  │  B  B
 6:  .  .  .  #  .  .  #  .  .  .  │  ♥  ♥
 7:  .  .  .  #  .  .  #  .  .  .  │  ♥  ♥
```

---

## Adding or editing icons

Icons are `uint8_t[104]` arrays in `sketch.ino`, row-major, one byte per pixel (0–7).

```cpp
// 13 columns × 8 rows = 104 bytes
static const uint8_t ICON_MY_EVENT[104] = {
  // row 0  (cols 0-12, leave cols 10-12 as 0 — status bar overwrites them)
  0,0,0, 0,7,7, 0,0,0, 0, 0,0,0,
  // ...
};
```

`draw_with_status()` always composites the status bar over cols 10–12 before
calling `matrix.draw()`, so you never need to set those bytes manually.
