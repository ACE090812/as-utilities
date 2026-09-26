# as-utilities — LS Energy Networks

Gas & electric meter engineer job for qbx_core + ox_lib + ox_target + ox_inventory + oxmysql.

## Install
1. Run `sql/install.sql`.
2. Paste `install/ox_inventory_items.lua` into `ox_inventory/data/items.lua`.
3. Paste `install/qbx_job.lua` into `qbx_core/shared/jobs.lua` and add the job to your job centre.
4. **Set the depot coords in `config.lua`** (clock-on, stores, van desk, spawn, return bay, job board). The shipped coords are placeholders.
5. `ensure as-utilities` after its dependencies.
6. In game as admin: `/utilmeter` and place ~100 meters (aim at a wall, `G` swaps gas/electric, `E` saves).

## How it works
- Take the job at the job centre → clock on at the depot and pick a trade (Electric / Gas / Dual Fuel at grade 3).
- Restock kit at stores, rent a van (deposit back minus damage at the return bay).
- Claim jobs on the depot job board (DUI panel on the wall). Meters show a status panel when you walk up on duty.
- Open a meter (ox_target) → camera moves to the meter panel, use the mouse. Right-click / Backspace / Esc to leave.

| Job | Task on the panel |
| --- | --- |
| Meter read (route of 3–6) | Key in the reading shown on the display |
| Blown fuse / sticking valve | Steps in the right order (wrong order = shock / gas) + pressure test for gas |
| Wiring fault | Match terminal colours |
| Dead display | Repeat the reset flash sequence |
| Reported fault | Real fault, or diagnostic → "No fault found" |
| Smart meter install | Steps → pairing code → reconnect |
| Tampering | Photograph evidence → make safe → reseal → police report |
| Gas leak | Detector sweep to the source → place 3 cones → repair + pressure test |

- Jobs generate continuously up to `Config.Generation.maxOpenJobs`.
- XP promotes automatically (`Config.Grades`). Crews: `/crewinvite [id]`, `/crewleave` — pay splits evenly.
- Copper theft: non-engineers with `meter_bypass_kit` can "Strip copper" when enough police are on duty. Sell `copper_wire` at the scrap buyer.
- Gas leaks: damage inside the zone, gunfire / fire causes an explosion, escalates if left. Alerts engineers, police and EMS.
- Dispatch: `Config.Dispatch = 'ps' | 'cd' | 'custom'`.

## Admin
`/utilmeter` place · `/utilmeterdel` delete nearest · `/utilleak` start a leak at the nearest gas meter.

## Notes
- The screens are DUIs drawn as world-space panels in front of the meter / on the depot wall (vanilla props have no screen texture). When you have custom meter models with a screen texture, you can swap `Screen:draw` for `AddReplaceTexture`.
- If props face the wall, set `Config.PropHeadingOffset = 180.0`.
