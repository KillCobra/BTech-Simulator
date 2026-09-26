extends RefCounted
## Chunky, semi-3D inventory icons and merit badges, drawn as SVG and rasterised
## at runtime (no import step): a lit top face, a darker side for depth, a soft
## drop shadow and a highlight, like the voxel world they come from.

const ITEM_SVG := {
	"hall_pass": """<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 96 96'>
<defs><linearGradient id='c' x1='0' y1='0' x2='1' y2='1'><stop offset='0' stop-color='#bfe9ff'/><stop offset='1' stop-color='#5fb2e0'/></linearGradient></defs>
<ellipse cx='50' cy='86' rx='30' ry='5' fill='#000' opacity='0.25'/>
<path d='M38 6 L48 30 L58 6' fill='none' stroke='#e0524f' stroke-width='6' stroke-linejoin='round'/>
<rect x='22' y='30' width='56' height='50' rx='7' fill='#2f6f96'/>
<rect x='18' y='26' width='56' height='50' rx='7' fill='url(#c)'/>
<rect x='38' y='22' width='16' height='10' rx='3' fill='#8a8f9c'/>
<rect x='26' y='36' width='18' height='20' rx='3' fill='#fbf6e8'/>
<circle cx='35' cy='43' r='4' fill='#c68a5c'/>
<rect x='29' y='49' width='12' height='5' rx='2' fill='#e0524f'/>
<rect x='48' y='38' width='20' height='4' rx='2' fill='#24315e'/>
<rect x='48' y='46' width='16' height='4' rx='2' fill='#24315e' opacity='0.6'/>
<rect x='26' y='62' width='42' height='8' rx='3' fill='#ffd24a'/>
<path d='M22 30 L70 30' stroke='#fff' stroke-width='3' opacity='0.5'/>
</svg>""",
	"samosa": """<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 96 96'>
<defs><linearGradient id='t' x1='0' y1='0' x2='0' y2='1'><stop offset='0' stop-color='#ffd98a'/><stop offset='1' stop-color='#e0a050'/></linearGradient></defs>
<ellipse cx='48' cy='84' rx='36' ry='7' fill='#000' opacity='0.25'/>
<ellipse cx='48' cy='78' rx='38' ry='9' fill='#e8e2d4'/>
<path d='M48 14 L84 72 L62 80 Z' fill='#b87430'/>
<path d='M48 14 L62 80 L12 72 Z' fill='url(#t)'/>
<path d='M48 14 L12 72' stroke='#fff3cc' stroke-width='3' opacity='0.7'/>
<circle cx='40' cy='50' r='2.5' fill='#8a5020'/><circle cx='50' cy='60' r='2.5' fill='#8a5020'/><circle cx='35' cy='64' r='2' fill='#8a5020'/>
<path d='M70 30 q6 -8 0 -16 M78 36 q6 -8 0 -16' stroke='#ffffff' stroke-width='3' fill='none' opacity='0.6' stroke-linecap='round'/>
</svg>""",
	"medical_note": """<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 96 96'>
<ellipse cx='50' cy='86' rx='30' ry='5' fill='#000' opacity='0.25'/>
<path d='M26 12 L74 12 L78 80 L22 80 Z' fill='#c9c2b0'/>
<path d='M22 10 L70 10 L74 78 L18 78 Z' fill='#fdfaf1'/>
<path d='M58 10 L70 10 L70 22 Z' fill='#e2dccb'/>
<rect x='34' y='24' width='22' height='22' rx='3' fill='#e0524f'/>
<rect x='41' y='27' width='8' height='16' fill='#fff'/><rect x='37' y='31' width='16' height='8' fill='#fff'/>
<rect x='28' y='54' width='38' height='4' rx='2' fill='#9a9486'/>
<rect x='28' y='62' width='30' height='4' rx='2' fill='#9a9486'/>
<path d='M44 72 q6 -8 12 0 q6 8 12 -2' stroke='#24315e' stroke-width='3' fill='none' stroke-linecap='round'/>
</svg>""",
	"canteen_key": """<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 96 96'>
<defs><linearGradient id='g' x1='0' y1='0' x2='1' y2='1'><stop offset='0' stop-color='#fff0a0'/><stop offset='0.5' stop-color='#ffc93c'/><stop offset='1' stop-color='#c98a10'/></linearGradient></defs>
<ellipse cx='50' cy='86' rx='32' ry='5' fill='#000' opacity='0.25'/>
<circle cx='32' cy='36' r='20' fill='#a86e08'/>
<circle cx='30' cy='33' r='20' fill='url(#g)'/>
<circle cx='30' cy='33' r='8' fill='#2a2230'/>
<rect x='44' y='38' width='40' height='11' rx='4' fill='#a86e08' transform='rotate(35 44 38)'/>
<rect x='43' y='35' width='40' height='11' rx='4' fill='url(#g)' transform='rotate(35 43 35)'/>
<rect x='66' y='60' width='8' height='12' rx='2' fill='#c98a10' transform='rotate(35 66 60)'/>
<rect x='58' y='54' width='8' height='10' rx='2' fill='#c98a10' transform='rotate(35 58 54)'/>
<path d='M18 26 q8 -10 18 -6' stroke='#fff' stroke-width='3' fill='none' opacity='0.8' stroke-linecap='round'/>
</svg>""",
	"library_book": """<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 96 96'>
<ellipse cx='50' cy='86' rx='34' ry='6' fill='#000' opacity='0.25'/>
<path d='M18 26 L62 14 L82 30 L38 42 Z' fill='#6f9cf0'/>
<path d='M38 42 L82 30 L82 66 L38 78 Z' fill='#f4efe0'/>
<path d='M40 46 L80 35 M40 54 L80 43 M40 62 L80 51 M40 70 L80 59' stroke='#d8d0bc' stroke-width='2'/>
<path d='M18 26 L38 42 L38 78 L18 62 Z' fill='#2f58b0'/>
<path d='M18 26 L62 14 L62 18 L20 30 Z' fill='#a8c4ff' opacity='0.7'/>
<rect x='24' y='44' width='8' height='4' fill='#ffd24a' transform='skewY(38)'/>
<path d='M26 38 L30 41 L30 70 L26 67 Z' fill='#ffd24a'/>
</svg>""",
	"detention_ticket": """<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 96 96'>
<defs><linearGradient id='p' x1='0' y1='0' x2='1' y2='1'><stop offset='0' stop-color='#ffc6c6'/><stop offset='1' stop-color='#ff7a7a'/></linearGradient></defs>
<ellipse cx='50' cy='84' rx='36' ry='5' fill='#000' opacity='0.25'/>
<g transform='rotate(-12 48 48)'>
<path d='M12 30 h72 v10 a6 6 0 0 0 0 12 v10 h-72 v-10 a6 6 0 0 0 0 -12 z' fill='#b83a3a' transform='translate(3 4)'/>
<path d='M12 30 h72 v10 a6 6 0 0 0 0 12 v10 h-72 v-10 a6 6 0 0 0 0 -12 z' fill='url(#p)'/>
<path d='M64 30 v32' stroke='#b83a3a' stroke-width='2' stroke-dasharray='4 3'/>
<path d='M24 40 l6 6 l12 -12' stroke='#1f7a3a' stroke-width='5' fill='none' stroke-linecap='round' stroke-linejoin='round'/>
<rect x='24' y='50' width='30' height='4' rx='2' fill='#8a2a3a'/>
<circle cx='74' cy='46' r='6' fill='#ffd24a'/>
<path d='M12 30 h72' stroke='#fff' stroke-width='2' opacity='0.6'/>
</g>
</svg>""",
}

# Merit badges, one per subject: a rosette with ribbons and the subject's emblem.
const BADGE_COLORS := ["#e0524f", "#4f86e0", "#48b06a", "#9a62d6"]
const BADGE_EMBLEM := [
	# Thermodynamics: a flame.
	"<path d='M48 24 q14 14 8 26 q8 -4 6 -12 q10 12 2 24 q-6 8 -16 8 q-12 0 -16 -10 q-4 -10 4 -18 q0 8 6 10 q-6 -14 6 -28 z' fill='#ffd24a' stroke='#8a2a10' stroke-width='2'/>",
	# Engineering Maths: pi.
	"<path d='M34 36 h28 M42 36 v24 q0 4 -4 4 M54 36 v22 q0 6 6 6' stroke='#fff8e0' stroke-width='6' fill='none' stroke-linecap='round'/>",
	# Data Structures: a little tree of nodes.
	"<path d='M48 34 L36 50 M48 34 L60 50 M60 50 L54 64 M60 50 L66 64' stroke='#fff8e0' stroke-width='3'/><circle cx='48' cy='34' r='6' fill='#ffd24a'/><circle cx='36' cy='50' r='5' fill='#fff8e0'/><circle cx='60' cy='50' r='5' fill='#fff8e0'/><circle cx='54' cy='64' r='4' fill='#fff8e0'/><circle cx='66' cy='64' r='4' fill='#fff8e0'/>",
	# Chemistry: a flask.
	"<path d='M42 28 h12 M44 28 v12 l-12 20 q-3 6 4 6 h24 q7 0 4 -6 l-12 -20 v-12' fill='#fff8e0' stroke='#fff8e0' stroke-width='3' stroke-linejoin='round'/><path d='M36 58 l6 -9 h12 l6 9 q2 4 -2 4 h-20 q-4 0 -2 -4 z' fill='#7fe0a0'/>",
]

static var _cache := {}


static func item(name: String, px := 48) -> Texture2D:
	if not ITEM_SVG.has(name):
		return null
	return _texture("item:%s:%d" % [name, px], ITEM_SVG[name], px)


static func badge(subject: int, px := 44) -> Texture2D:
	var c: String = BADGE_COLORS[subject % BADGE_COLORS.size()]
	var svg := """<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 96 96'>
<defs><radialGradient id='m' cx='0.35' cy='0.3' r='0.8'><stop offset='0' stop-color='#fff6c8'/><stop offset='0.45' stop-color='#ffc93c'/><stop offset='1' stop-color='#b8820a'/></radialGradient></defs>
<path d='M30 56 L20 92 L32 86 L38 96 L46 62 Z' fill='%s'/>
<path d='M66 56 L76 92 L64 86 L58 96 L50 62 Z' fill='%s'/>
<circle cx='49' cy='48' r='32' fill='#000' opacity='0.25'/>
<circle cx='48' cy='46' r='32' fill='url(#m)'/>
<circle cx='48' cy='46' r='24' fill='%s' stroke='#fff3b0' stroke-width='3'/>
%s
<path d='M26 34 q10 -16 28 -18' stroke='#fff' stroke-width='4' fill='none' opacity='0.6' stroke-linecap='round'/>
</svg>""" % [c, c, c, BADGE_EMBLEM[subject % BADGE_EMBLEM.size()]]
	return _texture("badge:%d:%d" % [subject, px], svg, px)


static func _texture(key: String, svg: String, px: int) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var img := Image.new()
	if img.load_svg_from_string(svg, px / 96.0) != OK:
		return null
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
