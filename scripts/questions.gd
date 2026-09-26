extends RefCounted
## Raise your hand (H) in class and ask something. Three kinds, each with the
## teacher's answer:
##   0 Intelligent   the teacher is impressed: suspicion drops, an angry teacher calms down faster
##   1 Quirky        the class laughs, the teacher plays along (a little less suspicion)
##   2 Mischievous   the teacher turns to the board to rant for a while (everyone's chance
##                   to sneak out!), but you might get a strike for it
## Entries are [question, teacher's reply]. SUBJECT adds a few per subject.

const KINDS := ["INTELLIGENT", "QUIRKY", "MISCHIEVOUS"]
const KIND_COLORS := [Color("7fe0a0"), Color("7fd0ea"), Color("ff9a6a")]

const GENERAL := [
	[
		["Could you explain that last step again, more slowly?", "Of course. Finally, someone who listens."],
		["How would this be used in the real world?", "Excellent question. Industry uses it every single day."],
		["Is there a proof for that, or do we just trust it?", "Never trust, always prove. Good instinct!"],
		["What's a good book to read more about this?", "See me after class, I'll lend you mine."],
		["Will this be in the final exam, and in what form?", "Yes. Long answer. Now you know. Study."],
		["Why does it work that way and not the other way?", "Ahh, now THAT is the right question to ask."],
		["Can I try solving the next one on the board?", "Bold! Maybe next time. I like the spirit."],
	],
	[
		["If I study in my dreams, does it count as attendance?", "Only if you snore in the correct syntax."],
		["Can we have class outside? The trees look lonely.", "The trees have better attendance than you."],
		["Is it true you were once a student too?", "Many, many centuries ago. Yes."],
		["What's your favourite samosa filling? Asking for science.", "Potato. Classic. Now back to work."],
		["Do pigeons have to attend lectures?", "Only the ones on the window sill. They're doing better than you."],
		["If a bell rings and nobody hears it, is class over?", "No. Nice try, philosopher."],
		["Can I name my future pet after this chapter?", "Only if the pet also does its homework."],
	],
	[
		["Is the principal's car parked in the fire lane AGAIN?", "WHAT? That man... one moment, class."],
		["Did you know the staff room has a secret snack drawer?", "There is NO drawer. Stop spreading rumours!"],
		["Is it true the canteen samosas are from last week?", "Pappu uncle's samosas are FRESH. Mostly. I think."],
		["Why do teachers get chai and we don't?", "Because WE survived YOU. Face the board!"],
		["Your collar is inside out. Just saying.", "It is... it is NOT. Eyes on the board!"],
		["Can we vote on skipping the test? Democracy!", "This is a classroom, not parliament. Sit down."],
		["Is it true you failed this subject once?", "Who told you that?! Board. Now. Everyone."],
	],
]

## Per subject (same order as the Director's SUBJECTS): [intelligent, quirky, mischievous] lists.
const SUBJECT := [
	[  # Thermodynamics
		[["Is a perfect heat engine really impossible?", "Yes. Carnot says no free lunch. Well asked!"], ["Why can't entropy ever go down?", "In an isolated system, never. You get it!"]],
		[["Is my room's mess just entropy doing its job?", "Scientifically... yes. Clean it anyway."], ["If I sit still, am I in thermal equilibrium?", "You are in academic equilibrium. Not good."]],
		[["Why is the AC in the staff room but not here?", "The staff room is... a heat sink. Stop it."], ["Can we test heat transfer on your chai?", "Hands OFF my chai!"]],
	],
	[  # Engineering Maths
		[["Why does e keep showing up everywhere?", "Because nature loves growth. Beautiful question."], ["Can every matrix be inverted?", "Only if its determinant isn't zero. Sharp!"]],
		[["If pi never ends, does maths class never end?", "Now you understand my life."], ["Can I integrate my way out of homework?", "The limit of your excuses is infinity."]],
		[["Did you use a calculator for the answer key?", "I use my BRAIN. Mostly. Face the board."], ["Isn't this all just done by computers now?", "Computers didn't pass THIS course. Board!"]],
	],
	[  # Data Structures
		[["When should I pick a hash map over a tree?", "When you need fast lookups and no order. Good!"], ["Why is quicksort slow on sorted input?", "Bad pivots. Someone read ahead!"]],
		[["Is a queue at the canteen a FIFO?", "Only if nobody cuts in. So no."], ["Is my to-do list a stack? I only do the top thing.", "That explains your submissions."]],
		[["Can you reverse a linked list without looking it up?", "Of course I... let me just check my notes."], ["Is the attendance register O(n) or O(n²)?", "It's O(detention) for you!"]],
	],
	[  # Chemistry
		[["Why are noble gases so unreactive?", "Full outer shells: perfectly content. Great question."], ["Is water really a universal solvent?", "Almost. Oil begs to differ. Well thought!"]],
		[["Is chai a solution, a mixture, or a lifestyle?", "All three. You pass... this question."], ["Would a samosa float in mercury?", "Yes. Please don't test it."]],
		[["What happens if we mix everything in the lab?", "A visit from the fire brigade. SIT DOWN."], ["Is it true the lab has a secret explosion list?", "There is no list! ...Who told you?!"]],
	],
]


## The six questions offered this time: two of each kind, some about today's subject.
static func pick(subject: int, rng: RandomNumberGenerator) -> Array:
	var out := []
	for kind in 3:
		var pool: Array = (GENERAL[kind] as Array).duplicate()
		if subject >= 0 and subject < SUBJECT.size():
			pool.append_array(SUBJECT[subject][kind])
		for k in 2:
			var i := rng.randi() % pool.size()
			out.append({"kind": kind, "q": pool[i][0], "a": pool[i][1]})
			pool.remove_at(i)
	return out


## Finds the teacher's reply for a question text (the server only trusts its own list).
static func reply_for(kind: int, question: String, subject: int) -> String:
	var pool: Array = (GENERAL[clampi(kind, 0, 2)] as Array).duplicate()
	if subject >= 0 and subject < SUBJECT.size():
		pool.append_array(SUBJECT[subject][clampi(kind, 0, 2)])
	for qa in pool:
		if qa[0] == question:
			return qa[1]
	return ""
