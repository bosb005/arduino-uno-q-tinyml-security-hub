# Photo & Video Checklist for Hackster Submission

Use this file as a direct capture list for `HACKSTER_ARTICLE.md`.

## Required photos (story + instructions + proof)

- [ ] **P1 Hero shot**: UNO Q + INMP441 assembled, clean desk, strong lighting
- [ ] **P2 Wiring close-up**: Pin labels visible (VDD/GND/SD/WS/SCK/LR)
- [ ] **P3 Schematic or wiring diagram screenshot**: clear and readable
- [ ] **P4 Build/deploy terminal proof**: `./deploy.sh all` completion
- [ ] **P5 Dashboard idle**: `http://<board-ip>:7000` visible in browser
- [ ] **P6 Dashboard presence**
- [ ] **P7 Dashboard anomaly**
- [ ] **P8 Dashboard manual_trigger**
- [ ] **P9 Dashboard history panel**: multiple events with timestamps/confidence
- [ ] **P10 Serial monitor**: class output / debug evidence
- [ ] **P11 Health endpoint JSON**: `/health` showing service alive

## Required video

- [ ] **V1 Demo video (30-60 s)**: idle -> presence -> anomaly -> manual_trigger
- [ ] **V2 Optional architecture voiceover clip (20-40 s)**: explain MCU vs Linux split

Video notes:
- Prefer split capture (camera on hardware + screen recording for dashboard).
- Keep triggers visible/audible and fast.
- Upload to YouTube (unlisted OK) and embed in Hackster article.

## Shot quality tips

- Use diffuse light to avoid glare on board labels.
- Keep background uncluttered.
- Keep browser URL bar visible for local endpoint proof.
- Take at least two variants of each key screenshot.

## Submission readiness checklist

- [ ] Article updated (`HACKSTER_ARTICLE.md`)
- [ ] BOM complete (`BOM.md`)
- [ ] Demo flow validated (`DEMO_SCRIPT.md`)
- [ ] All media captured and uploaded
- [ ] Public GitHub repo link added in article
- [ ] Schematic/wiring evidence included
- [ ] Final Hackster submission completed
