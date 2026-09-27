extends RefCounted
## What the staff say, per character (NPC node name) and moment. The Director picks a
## random line with `pick()`; a character without their own lines for a moment falls
## back to the generic ones. Pappu Uncle, the canteen's mascot, has the most to say.

const GENERIC := {
	"spot": ["Hey! Stop right there!", "Where do you think you're going?!", "Come back here!", "You! Which class?!"],
	"catch": ["Gotcha! Principal's office. NOW.", "Caught you. Office. March.", "That's enough running for one day."],
	"lost": ["Hmph. Lost them.", "Where did they go?!", "Kids these days. Fast, though."],
}

const BY_NPC := {
	# Ms. Okafor: sharp, dry, secretly proud of good students.
	"Teacher0": {
		"spot": ["I SEE you, %s.", "Walking out of my lesson? Bold.", "Stop. Right. There."],
		"catch": ["I expected better. Office.", "Disappointing, %s. Principal's office.", "You'll thank me when you're older. Office."],
		"lost": ["They'll be back. They always come back.", "I'll remember that face."],
	},
	# Mr. Tanaka: eagle eyes, hates corridors.
	"Teacher1": {
		"spot": ["I can see you from HERE, %s.", "Back row. Standing. Why?", "Sit. DOWN."],
		"catch": ["My eyes never miss. Office.", "Twenty metres and I still saw you. Office."],
		"lost": ["Not worth the walk.", "I'll see you tomorrow. I see everything."],
	},
	# Dr. Alvarez: distracted, enthusiastic, slow to notice.
	"Teacher2": {
		"spot": ["Wait... is someone leaving? During the BEST part?", "Hold on! We haven't even got to the fun bit!", "Oi! Inertia says you should STAY PUT!"],
		"catch": ["Caught! Like a variable in a loop. Office.", "The principal will want to hear about this. And my lecture."],
		"lost": ["Where was I? Ah yes, the stack...", "Gone. Like my coffee."],
	},
	# Mrs. Iyer: hears everything, forgives once.
	"Teacher3": {
		"spot": ["I HEARD you get up, %s.", "Don't make me come over there!", "Aha! I knew it!"],
		"catch": ["Once I believed you. Not twice. Office.", "Mrs. Iyer ALWAYS knows. Principal's office.", "Gotcha, %s!"],
		"lost": ["I'll hear you soon enough.", "Run, run. I have ears everywhere."],
	},
	"Guard": {
		"spot": ["Oi! Gate's closed, champ!", "Nobody leaves on my shift!", "Stop! Security!"],
		"catch": ["Nice try. Back inside.", "Not today. Not on my watch."],
		"lost": ["My chai's getting cold anyway.", "Too fast. I'm too old for this."],
		"break": ["Chai break... ahh.", "Five minutes. Nobody tell the principal.", "Best part of the job, this."],
	},
	"VP": {
		"spot": ["YOU. My office. Now.", "The Vice Principal sees ALL.", "Walking the corridors during class? Hmm?"],
		"catch": ["I'll be writing to your parents.", "Detention. And a strongly worded letter."],
	},
	"Prefect": {
		"spot": ["I'm TELLING!", "Oh, you are SO in trouble.", "Wait till Mrs. Iyer hears about this!"],
	},
	"Peon": {
		"spot": ["Oi! I just mopped there!", "Out of my corridor!", "Who's making footprints?!"],
		"catch": ["Gotcha. Mind the wet floor on the way to the office."],
		"mop": ["Wet floor! WET FLOOR!", "I just mopped this. Walk!", "Careful, it's slippery..."],
	},
	"Proctor": {
		"spot": ["Exam hall rules apply EVERYWHERE!", "Halt! Identity card!"],
	},
}

# --- Pappu Uncle, the canteen legend -----------------------------------------------------------

const UNCLE := {
	"greet": [
		"What'll it be, champ?", "Samosas! Hot samosas! Only slightly from yesterday!", "Welcome to the finest canteen in the academy!",
		"Ah, my favourite customer. Don't tell the others.", "Bunking again? I saw nothing. Buy something.",
		"Chai, samosa, a hall pass... Uncle has everything.", "Forty years at this counter. Seen every trick.",
		"You look hungry. Or guilty. Samosa fixes both.", "Money first, questions never.",
		"The principal eats here too, you know. Hide behind the fridge if she comes.",
	],
	"buy": [
		"Good choice!", "Enjoy! Don't get caught with it.", "Come again!", "Pleasure doing business.",
		"That one's extra crispy. For you.", "Keep the change. Oh wait, there isn't any.",
	],
	"broke": [
		"No money, no samosa. That's the economics.", "Uncle doesn't do credit. Uncle did credit once. Never again.",
		"Coins are lying around by the lockers. Go look. Quietly.", "Empty pockets? Answer your attendance, earn a bit.",
	],
	"caught": [
		"Back from the principal's office? Samosa for the nerves?", "I heard about your little trip. Whole canteen heard.",
		"Detention again? You're my best customer AND my worst student.",
	],
	"heat": [
		"Lockdown! Even I can't leave. Buy something, keep me company.", "Guards everywhere today. Maybe just... sit in class?",
		"The whole staff is out on patrol. Something about a fire alarm...",
	],
	"idle": [
		"Psst. Samosa?", "In my day we bunked with dignity.", "Fresh batch in five minutes. Or fifty.",
		"You didn't see me, I didn't see you.", "The fire alarm is on the verandah pillars. Not that I'm telling you.",
		"Heard the exam paper sits in the staff room. Heard, I said. Heard.", "Nobody questions a student holding a library book. Just saying.",
		"The guard takes his chai break every half an hour. Like clockwork.",
	],
}


static func pick(rng: RandomNumberGenerator, npc_name: String, moment: String, who := "") -> String:
	var own: Dictionary = BY_NPC.get(npc_name, {})
	var list: Array = own.get(moment, GENERIC.get(moment, []))
	if list.is_empty():
		return ""
	var line: String = list[rng.randi() % list.size()]
	return line % who if "%s" in line else line


static func uncle(rng: RandomNumberGenerator, moment: String) -> String:
	var list: Array = UNCLE.get(moment, UNCLE.greet)
	return list[rng.randi() % list.size()]
