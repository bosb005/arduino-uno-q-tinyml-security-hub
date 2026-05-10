# Task: Final Submission & Presentation

## Context

Contest: https://www.hackster.io/contests/invent-the-future-with-arduino-uno-q-and-app-lab
Project: Edge AI Smart Security Hub
Submission deadline: check contest page

This task produces all materials needed to submit to Hackster.io and present the project.

## Your Task

### 1. `HACKSTER_ARTICLE.md` — Submission article draft
Write a full Hackster.io project article with these sections (use the contest Q&A from project.txt as source):

- **Title:** Edge AI Smart Security Hub
- **One-liner:** Privacy-first acoustic event detection at the edge using TinyML
- **Things used in this project** (BOM — see below)
- **Story / Introduction** (~200 words): problem statement, why edge AI
- **Hardware setup** (link to 01_hardware_setup)
- **Software overview** (brief description of each firmware + dashboard component)
- **How it works** (block diagram description: INMP441 → I2S → MCU → TinyML → Linux → Browser)
- **Results & demo** (what events were detected, accuracy observed)
- **Sustainability section** (from project.txt)
- **Future work** (MQTT, multi-node, retraining)
- **Code** (link GitHub repo sections)

### 2. `BOM.md` — Bill of Materials
| Component | Qty | Notes |
|-----------|-----|-------|
| Arduino UNO Q | 1 | Contest hardware |
| INMP441 MEMS microphone | 1 | I2S digital |
| Dupont jumper wires | ~6 | For direct I2S wiring |
| USB-A to USB-C cable | 1 | Power + programming |
| USB-A to USB-C cable | 1 | Power + programming |
| Wi-Fi router / AP | 1 | Home network |

Total estimated cost (excluding contest hardware): < $10

### 3. `DEMO_SCRIPT.md`
A step-by-step live demo script:
1. Power on board, wait 30 s for Linux to boot
2. Connect laptop/phone to home Wi-Fi, open `http://<board-ip>:5000`
3. Show idle state (green)
4. Walk past microphone → presence detected (yellow)
5. Clap loudly once → anomaly detected (red)
6. Triple-clap → manual trigger (blue)
7. Show event history table
8. Show Serial monitor for raw inference output (bonus)

### 4. `README.md` — Repository root README
A clean project README for GitHub:
- Project title + one-liner
- Photo/diagram placeholder
- Quick start (flash + run dashboard)
- Architecture overview
- License: MIT

### 5. `PHOTO_CHECKLIST.md`
Photos/videos needed for the submission:
- [ ] Board + microphone wired up (top view)
- [ ] Serial monitor showing inference output
- [ ] Dashboard in browser (all 4 states)
- [ ] Short demo video (30–60 s): idle → presence → anomaly → trigger

## Notes
- Hackster articles support Markdown
- Submit code as a public GitHub repository (link in article)
- Check contest rules for video requirements
- Keep the article honest about what works and what is a demo/prototype
