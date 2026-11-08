extends Control
## The game's entry point. For now, a text monitor over the running simulation.
## It only reads world state and drives the clock. It holds no game state of its own.

const REFRESH_SECONDS: float = 0.25
const START_DAYS_PER_SECOND: float = 10.0
const SPEEDS: Array[float] = [1.0, 5.0, 10.0, 30.0, 90.0, 240.0]
const RECENT_EVENTS: int = 14

var _refresh_timer: float = 0.0
var _speed_index: int = 2

@onready var _header: Label = %Header
@onready var _player: Label = %Player
@onready var _realms: Label = %Realms
@onready var _events: Label = %Events


func _ready() -> void:
	var config: WorldGenConfig = WorldGenConfig.new()
	config.world_seed = randi()
	World.new_game(config)
	GameClock.days_per_second = START_DAYS_PER_SECOND
	GameClock.paused = false
	_refresh()


func _process(delta: float) -> void:
	_refresh_timer += delta
	if _refresh_timer >= REFRESH_SECONDS:
		_refresh_timer = 0.0
		_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	var key: InputEventKey = event as InputEventKey
	if key == null:
		return
	match key.keycode:
		KEY_SPACE:
			GameClock.paused = not GameClock.paused
		KEY_EQUAL, KEY_KP_ADD:
			_set_speed(_speed_index + 1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_set_speed(_speed_index - 1)
	_refresh()


func _set_speed(index: int) -> void:
	_speed_index = clampi(index, 0, SPEEDS.size() - 1)
	GameClock.days_per_second = SPEEDS[_speed_index]


func _refresh() -> void:
	var kernel: SimKernel = Simulation.kernel
	if kernel == null:
		return
	var ctx: SimContext = kernel.ctx
	_header.text = _header_text(ctx)
	_player.text = _player_text(ctx)
	_realms.text = _realms_text(ctx)
	_events.text = _events_text(ctx)


func _header_text(ctx: SimContext) -> String:
	var calendar: CalendarData = ctx.world.calendar
	var state: String = "PAUSED" if GameClock.paused else "%d days/sec" % roundi(GameClock.days_per_second)
	return "Epochs of Ortel    Year %d, Month %d, Day %d    %s    %d named characters    Seed %d" % [
		calendar.year(), calendar.month() + 1, calendar.day_of_month() + 1, state, ctx.world.characters.size(), ctx.world.world_seed]


func _player_text(ctx: SimContext) -> String:
	var c: CharacterData = ctx.character(ctx.world.player_character_id)
	if c == null:
		return "PLAYER: the line has ended. The world carries on without you."
	var site: SettlementData = ctx.settlement(c.settlement_id)
	var realm: FactionData = ctx.faction(c.faction_id)
	return "PLAYER: %s, %s %s, age %d    Status: %s    In %s, %s    Gold: %d    Debt: %d" % [
		c.given_name,
		GeneticsService.dominant_race(c),
		c.occupation,
		floori(ctx.age_years(c)),
		str(SimEnums.LegalStatus.keys()[c.legal.status]).to_lower(),
		site.display_name if site != null else "the wilds",
		realm.display_name if realm != null else "no realm",
		c.inventory.gold,
		c.debt]


func _realms_text(ctx: SimContext) -> String:
	var lines: PackedStringArray = PackedStringArray(["REALMS"])
	for id: int in ctx.faction_ids():
		var f: FactionData = ctx.world.factions[id]
		var people: int = 0
		var enslaved: int = 0
		for s_id: int in f.settlement_ids:
			var s: SettlementData = ctx.settlement(s_id)
			people += PopService.total(s)
			enslaved += PopService.total_with_status(s, SimEnums.LegalStatus.ENSLAVED)
		var ruler: CharacterData = ctx.character(f.ruler_id)
		var war: String = "  AT WAR" if not f.at_war_with.is_empty() else ""
		lines.append("%s    %d towns, %d people (%d enslaved)    Ruler: %s    Law: %s    %d techs    %d gold%s" % [
			f.display_name,
			f.settlement_ids.size(),
			people,
			enslaved,
			ruler.given_name if ruler != null else "none",
			str(SimEnums.BondageLaw.keys()[f.laws.bondage_law]).to_lower(),
			f.known_techs.size(),
			f.treasury,
			war])
	return "\n".join(lines)


func _events_text(ctx: SimContext) -> String:
	var lines: PackedStringArray = PackedStringArray(["RECENT EVENTS"])
	var entries: Array[ChronicleEntry] = ctx.world.chronicle
	for i: int in range(entries.size() - 1, maxi(entries.size() - 1 - RECENT_EVENTS, -1), -1):
		var entry: ChronicleEntry = entries[i]
		lines.append("Year %d: %s" % [floori(entry.day / float(CalendarData.DAYS_PER_YEAR)), entry.text])
	return "\n".join(lines)
