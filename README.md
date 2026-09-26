# Bunk Master

Multiplayer first-person college bunk simulator (Godot 4.4, Windows). You're a student at the Royal
Academy of Unnecessary Sciences. Sneak out of class, dodge teachers, guards and CCTV, do side quests with
friends, and escape the whole (very big) university before the final bell.

## Play (no install)
Download the latest release: `BunkMaster.zip` (Windows: extract it, keep the `.dll` next to `BunkMaster.exe`) or
`BunkMaster-mac.zip`. Everyone plays through online sessions (below); you can join a round already in progress,
and rejoin after a drop (your quests and score are kept).

## Mac
`export/BunkMaster-mac.zip` holds `Bunk Master.app` (universal: Intel + Apple Silicon, macOS 11+).
It's ad-hoc signed, not notarized, so the first launch needs one extra step:
unzip, move it to Applications, then **right-click > Open > Open**. If macOS says the app is "damaged",
run once in Terminal: `xattr -cr "/Applications/Bunk Master.app"`. Mac and Windows players can play together
(same version of the game on both).

## Online sessions (no accounts)
1. Host: **CREATE SESSION** -> pick a session name (and an optional password) -> you're in the lobby.
2. Friends (up to 7): **JOIN SESSION** -> type the same name (and password) -> they connect and appear in the lobby.
3. In the lobby everyone can change their name (it's what the others see all game) and classroom. Newcomers are
   **NOT READY**; each friend clicks **I'M READY**, and the host's **START CLASS** unlocks once everyone is ready.

How it works: the host announces the session on free public MQTT brokers (EMQX/HiveMQ/Mosquitto, several at once
for redundancy); joiners find it there and swap WebRTC connection details, then play is direct peer-to-peer
(STUN finds the route). Passwords are only sent as a hash. Works on most home networks; if a pair of networks is
too strict (no connection after ~35 s, common on mobile data), the other person should create the session or one
side should switch networks. Manual invite codes remain as a fallback (link under the session form).

## Controls
WASD move · Shift sprint · Ctrl/C crouch · Space jump · E interact / pick up / drop ball
· Left-click: shove (or hold to charge and release to shoot the basketball) · 1-3 use items · Q phone
· H raise hand (ask a question) · G throw paper ball (distraction) · T ping · R answer attendance for a friend
· M big map (F: switch floor)
· Tab scores · Esc menu · F10 leave

## Maps
**First Day** is the small starter map: the original two-storey school in its compound, escape to the chai
stall across the road. Learn the game here. Every other map has its **own, much bigger university building**
(many corridors, dozens of rooms, switchback stairwells, classrooms on upper floors) inside huge grounds
300-450 m across. Escaping means getting out of the building *and* past the university's outer walls. Green stars
on the big map (M, mouse wheel zoom, F to change floor) mark the ways out.
- **Grand Campus** - the *Old Quadrangle*: four 3-storey wings round a courtyard (court, fountain), joined on
  every floor so you can walk the whole ring without going downstairs. Outside:
  boulevards, hostels, a stadium, a hedge maze and a lake. Out through the guarded main gate, a fence hole
  (crouch), a storm drain (crouch) or the construction site's scaffolding over the south wall.
- **Whispering Pines** - *Pinewood Lodges*: two long 2-storey timber lodges joined by a Great Hall (an H) in a
  forest split by a river. Cross by the ranger's bridge, a rope bridge or stepping stones (jump), then the north
  checkpoint, the logging gate (crouch), the fence a tree fell on (jump) or the creek culvert (crouch).
- **Lagoon Island** - the *Marine Institute*: a 3-storey white U closed by a back block round a pool courtyard.
  The 150 m bridge (toll guards, a bridge patrol), the ferry at the east pier, or hop the rocks to a fishing boat.
- **Downtown Campus** - *Quibble Towers*: two 6-storey towers either side of a courtyard, classes up to the
  5th floor. The north or west checkpoint, a torn fence in the back alley (crouch), or the metro.
- **Random**: one of the five, picked when class starts.

Fall in the water and it washes you back to the bank. Every map has its own guards, patrols and cameras;
in the big buildings the proctor and vice principal patrol the upper corridors.

## First Day's school
The main building has two floors. Ground: Class A, Class B, Computer Room, Seminar Hall. First floor:
Class C, Lab, Music Room, Store Room, along a balcony watched by the proctor and a CCTV camera. Ramped stairs
at both ends of the building start from the back. The minimap (bottom right) turns with you and shows your
floor, friends, pings, nearby staff and your quest targets; the big map (M) shows the whole campus. The floor
you're on is also shown faintly at the top of the screen (it lights up when you change floors).

## School day
- **Timetable:** the round is split into periods (2-6, by round length). Each class moves to a new room and
  subject every period; the bell gives you 25 s to walk to your next class (corridors are fair game then). The
  top-left card shows the period, subject, room and floor; a blue **YOUR SEAT** pin (and a pin on the maps) shows
  where to sit. There's **one attendance per class per period**.
- **Surprise tests:** once a period each room has a test. Sit in your seat: the teacher walks over and hands you
  the paper (walk in late and you get a muttered remark with it), you look it over, then the clock starts. Each
  subject has three kinds of paper, picked at random: Thermodynamics (reactor needle · vent the boilers · which is
  hotter?), Maths (quick sums · finish the pattern · which is bigger?), Data Structures (sort · stacks and queues ·
  binary search), Chemistry (repeat the recipe · element symbols · acid or base?). Up to +100 points, a missed test
  is -50. You get 8 s to sit down once it starts (5 s if you walk in late); after that a teacher who sees you on
  your feet sends you to detention. A photo of the exam paper (staff room) gets you full marks on your next test.
- **Merit badges:** 100/100 in a test earns that subject's badge, shown top right with a count.
- **Raise your hand (H):** in your own class, pick a question: intelligent (the teacher likes you: less suspicion,
  calms down faster, Rs 5), quirky (the class laughs) or mischievous (the teacher rants at the board for a while,
  everyone's chance to sneak out, but 30% of the time they see through it: a strike).
- **Hall pass running out:** you get 40 s to walk back without being chased; arriving after it expired annoys your
  teacher (one strictness notch), but it's not detention. Walking into your classroom gives you a few seconds to
  reach your seat.
- **Class change:** the NPC students pack up, walk out and head to their next classroom too.
- **Pocket money:** coins lie around campus (Rs 5-15, walk over them; new ones turn up elsewhere). You also earn
  Rs 40 per side quest, up to Rs 20 per test and Rs 5 for answering attendance. Spend it at Pappu Uncle's canteen
  counter (E): Samosa Rs 10, Hall Pass Rs 40, Medical Note Rs 70, Detention Skip Rs 90 (used automatically when
  you're caught), and upgrades for the round (Signed passes: +15 s per hall pass, up to 3 levels; Soft shoes:
  staff hear you sprint from half as far). Trade with classmates from the phone.
- **Phone (Q):** held in your right hand; the mouse taps its screen and you can still walk. The home screen shows
  the time left and app tiles; tap one to open it (Esc or "Home" goes back). Today (money, tests, messages),
  Timetable (every period's subject, room and floor, attendance and test times), Wallet (money, upgrades,
  pockets), Trade (give money or items to a classmate next to you), Tracker (shows staff for 5 s, names on the
  nearest few only; 20 s to recharge), Navigate (the shortest way to your seat on a little map, how far and which
  stairs; SHOW ME THE WAY lights the route on the floor and your minimap for 10 s).
- **Pings (T):** point at something and ping it: people are named (and the marker follows them), objects are
  named ("Fire alarm", "Locker", "Principal's car"...), anywhere else is a location ("Location: Near Canteen").
  Everyone in the session sees them.
- **Coins** turn up where money gets dropped or stashed: by the lockers and in the washrooms (worth more), under
  desks and canteen chairs, sometimes out in the open. A picked-up coin comes back somewhere else 20 s later.
- **Other students:** walk into one and they stumble out of your way with a word or two; you keep going.
- **Music room:** play the piano or drums (E, then keys 1-8). Everyone hears it, and so do the staff.
- **Washrooms:** use the toilet for a no-questions washroom break (-25 suspicion, 20 s to wander back), or hide an
  item in the cistern and fish it out later. Getting caught confiscates the canteen key, medical notes and hall passes.
- **Detention:** 20 s, and 5 s longer each time you're caught. The lines paper opens by itself: just type the
  sentence exactly and press Enter (5 s off each), then type the next one. A wrong line flashes red, the paper
  shakes and the line is wiped: try again. Afterwards you walk back to class yourself (60 s grace); your teacher scolds you and gets
  stricter (notices more, less wiggle room at your seat). Sit nicely for 45 s to calm them down a notch.
- **Controls:** Settings → CONTROLS to rebind any key.

## How to bunk
- Stay near your seat while your teacher faces the class; move when they turn to the board.
- Outside your own classroom you're suspicious to all staff and CCTV. Suspicion fills while seen; at 100% they chase.
  Staff and cameras only see (and hear) students on their own floor: never through ceilings or across floors.
  CCTV, the librarian and the canteen uncle don't chase: they call someone who will.
- Sprinting is loud. Crouching hides you behind desks. Walking next to other students gives cover.
- Hide in lockers or washroom stalls (E) to break a chase, unless they saw you get in.
- Attendance once per period. Absent = +45 suspicion, unless a friend in class presses R when your name is called.
- When staff reach you they grab you for a moment: left-click to shove them over and run. Shoving costs
  score and adds 8 s to your next detention; 4 s cooldown.
- Caught = detention in the principal's office, however far you got (see School day).
- Basketball: pick up a ball on the court (E), aim at the hoop, hold left-click (~1 s for a mid-range shot), release.
- Ways out of First Day's school: main gate (guard's chai break, or show him a forged medical note), back
  classroom windows (crouch + jump), broken back wall (crates, or get a boost from a crouching friend: E), the
  service gate in the east wall (key behind the canteen counter). A medical note works on any gate guard.
- Items: Hall Pass (ask your teacher or buy one, 35 s of legal wandering), Samosa (bribe/distract staff or eat it),
  Medical Note (staff room cupboard), Canteen Key.
- Fire alarm (verandah pillars): staff evacuate to the plaza for 25 s. 150 s cooldown.
- Escaped? You can still use your phone (track staff, trade, ping) and throw paper balls back over the wall to
  pull staff away from friends still inside.
- Score: escape +500 plus time left, side quests +150 each, caught -100, spotted -25. Round lengths: 5, 8, 12
  or 20 minutes (the big maps take a while).

## Develop
Open `project.godot` in Godot 4.4+. Test multiplayer with Debug > Customize Run Instances.
Art: everything is coloured boxes merged by `scripts/voxel.gd` (fake-bevel shader `shaders/voxel.gdshader`),
colours in `scripts/palette.gd`. Audio is synthesized at startup by `autoload/sfx.gd` (no asset files).
Rules and NPC brains: `scenes/world/director.gd`. Framework + First Day's school: `scenes/world/campus_builder.gd`.
Maps: `scenes/world/maps/` (list in `maps.gd`; outdoor toolkit `grounds.gd`; building toolkit `academic_kit.gd`
builds wings of corridors, rooms and stairwells from room lists).

Build the exe: `godot --headless --path . --export-release "Windows Desktop" export/BunkMaster.exe`
(the preset uses the template in `export/templates/`; or install Godot's export templates and clear the custom path).

Dev flags (after `--`): `--host --autostart=1 --minutes=M --map=0..4 (-1 random)` (private local round) ·
`--session-host=NAME` / `--session-join=NAME` · `--name=X --room=0..3` ·
`--at=x,z` · `--walk=x,z;!interact;!use1;!proxy;!wait2;!stand;!coin;!counter;!buy:samosa;!give10;!giveslot0;!bump;...`
(test bot) · `--autoready` · `--no-staff` · `--trace` · `--cam=x,y,z,tx,ty,tz` · `--shot=file.png --shot_delay=S` ·
`--bigmap` · `--quit-at-end` · `--phone=-1..5` (home / an app) · `--navshow` · `--shop` · `--scan` · `--ask` · `--typebot [--typebot-wrong]` · `--jail=S` · `--exam=0..3 --variant=0..2` ·
bot actions `!ask:0..2` `!examphoto`

## Not included
- Host migration: if the host quits, the round ends for everyone.
- Steam invites: need a paid Steamworks app ID ($100) and the GodotSteam plugin. Online sessions work today.
