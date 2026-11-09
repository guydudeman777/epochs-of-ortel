extends TestCase
## Bodies: what blows do, what wounds cost, how they heal or kill, and the duel that lands them.


func _world() -> SimKernel:
	return empty_kernel()


func _person(k: SimKernel, s: SettlementData, age: float = 30.0) -> CharacterData:
	return make_person(k, s, &"human", SimEnums.Sex.MALE, age, &"soldier")


func _site(k: SimKernel) -> SettlementData:
	return make_settlement(k, make_faction(k, &"hallowed"))


func _armed(k: SimKernel, c: CharacterData, shield: bool = false, weapon: StringName = &"arming_sword") -> void:
	var armour: Array[StringName] = [&"mail_hauberk", &"mail_coif", &"helmet", &"trousers", &"boots"]
	assert_true(Actions.equip(k.ctx, c.id, weapon, shield, armour).success, "equips")


func test_a_whole_body_has_every_capacity() -> void:
	var k: SimKernel = _world()
	var c: CharacterData = _person(k, _site(k))
	for capacity: StringName in [&"right_arm", &"left_arm", &"left_leg", &"right_leg", &"wind", &"mind"]:
		assert_eq(LimbService.capacity(k.ctx, c, capacity), 1.0, "%s whole" % capacity)
	assert_eq(LimbService.part_level(k.ctx, c, &"hand_r"), SimEnums.WoundLevel.UNHURT, "unhurt")
	assert_eq(LimbService.mobility(k.ctx, c), 1.0, "walks")


func test_every_part_hangs_from_a_real_parent() -> void:
	var defs: DefCatalog = catalog()
	assert_eq(defs.body_part_ids.size(), 16, "sixteen parts")
	for part_id: StringName in defs.body_part_ids:
		var parent: StringName = defs.body_parts[part_id].parent
		assert_true(parent == &"" or defs.body_parts.has(parent), "%s has a real parent" % part_id)
	var ends: Dictionary = DuelFight.LANDS
	for move: DuelFighter.Move in ends:
		var table: Dictionary = ends[move]
		for part_id: StringName in table:
			assert_true(defs.body_parts.has(part_id), "duel table names real part %s" % part_id)


func test_damage_has_levels() -> void:
	assert_eq(LimbService.level_of(0.0), SimEnums.WoundLevel.UNHURT, "none")
	assert_eq(LimbService.level_of(0.1), SimEnums.WoundLevel.BRUISED, "bruised")
	assert_eq(LimbService.level_of(0.3), SimEnums.WoundLevel.HURT, "hurt")
	assert_eq(LimbService.level_of(0.6), SimEnums.WoundLevel.BADLY_HURT, "badly")
	assert_eq(LimbService.level_of(0.9), SimEnums.WoundLevel.CRIPPLED, "crippled")
	assert_eq(LimbService.level_of(1.0), SimEnums.WoundLevel.RUINED, "ruined")


func test_a_hurt_part_costs_what_it_carries() -> void:
	var k: SimKernel = _world()
	var c: CharacterData = _person(k, _site(k))
	LimbService.apply_blow(k.ctx, c, &"forearm_r", &"cut", 17.0)
	assert_true(LimbService.capacity(k.ctx, c, &"right_arm") < 1.0, "the arm suffers")
	assert_eq(LimbService.capacity(k.ctx, c, &"left_arm"), 1.0, "the other arm does not")
	assert_eq(LimbService.mobility(k.ctx, c), 1.0, "nor do the legs")
	assert_true(LimbService.fighting_capacity(k.ctx, c) < 1.0, "fights worse")
	assert_consistent(k)


func test_a_hard_cut_takes_off_the_limb_and_what_hangs_from_it() -> void:
	var k: SimKernel = _world()
	var c: CharacterData = _person(k, _site(k))
	LimbService.apply_blow(k.ctx, c, &"hand_l", &"cut", 3.0)
	var blow: LimbBlow = LimbService.apply_blow(k.ctx, c, &"forearm_l", &"cut", 60.0)
	assert_true(blow.severed, "cut through")
	assert_true(LimbService.is_lost(k.ctx, c, &"forearm_l"), "forearm gone")
	assert_true(LimbService.is_lost(k.ctx, c, &"hand_l"), "hand went with it")
	assert_true(not LimbService.is_lost(k.ctx, c, &"arm_l"), "upper arm stays")
	assert_eq(LimbService.part_level(k.ctx, c, &"hand_l"), SimEnums.WoundLevel.LOST, "reported lost")
	assert_eq(LimbService.capacity(k.ctx, c, &"left_arm"), 0.0, "that arm does nothing now")
	for wound: WoundData in c.body.wounds:
		assert_true(wound.part_id != &"hand_l", "no wound stays on what is gone")
	assert_eq(k.ctx.stat(&"limbs_lost"), 1, "counted")
	assert_consistent(k)


func test_only_edges_cut_things_off() -> void:
	var k: SimKernel = _world()
	var c: CharacterData = _person(k, _site(k))
	var crushed: LimbBlow = LimbService.apply_blow(k.ctx, c, &"forearm_r", &"crush", 80.0)
	assert_true(not crushed.severed, "a mace does not sever")
	assert_true(not LimbService.is_lost(k.ctx, c, &"forearm_r"), "the arm is still on")
	assert_eq(crushed.level, SimEnums.WoundLevel.RUINED, "but it is ruined")
	assert_eq(LimbService.capacity(k.ctx, c, &"right_arm"), 0.0, "and useless")
	assert_consistent(k)


func test_armour_stops_blows_where_it_covers() -> void:
	var k: SimKernel = _world()
	var s: SettlementData = _site(k)
	var bare: CharacterData = _person(k, s)
	var mailed: CharacterData = _person(k, s)
	_armed(k, mailed)
	var on_bare: LimbBlow = LimbService.apply_blow(k.ctx, bare, &"torso", &"cut", 30.0)
	var on_mail: LimbBlow = LimbService.apply_blow(k.ctx, mailed, &"torso", &"cut", 30.0)
	var crush_mail: LimbBlow = LimbService.apply_blow(k.ctx, mailed, &"abdomen", &"crush", 30.0)
	assert_true(on_mail.severity < on_bare.severity * 0.4, "mail turns a cut")
	assert_true(crush_mail.severity > on_mail.severity, "mail does little against a crush")
	assert_true(LimbService.gets_through(k.ctx, mailed, &"hand_r", &"cut") == 1.0, "mail does not cover the hand")


func test_tough_races_take_less_from_a_blow() -> void:
	var k: SimKernel = _world()
	var s: SettlementData = _site(k)
	var human: CharacterData = _person(k, s)
	var orc: CharacterData = make_person(k, s, &"orc")
	assert_true(LimbService.apply_blow(k.ctx, orc, &"torso", &"cut", 20.0).severity < LimbService.apply_blow(k.ctx, human, &"torso", &"cut", 20.0).severity, "orcs are tougher")


func test_destroying_a_vital_part_kills() -> void:
	var k: SimKernel = _world()
	var s: SettlementData = _site(k)
	var c: CharacterData = _person(k, s)
	var blow: LimbBlow = LimbService.apply_blow(k.ctx, c, &"neck", &"cut", 200.0)
	assert_true(blow.killed, "killed")
	assert_true(k.ctx.character(c.id) == null, "gone from the living")
	assert_eq(k.ctx.world.archived_characters[c.id].death_cause, &"wounds", "of wounds")
	assert_consistent(k)


func test_an_open_artery_bleeds_out() -> void:
	var k: SimKernel = _world()
	var c: CharacterData = _person(k, _site(k))
	var wound: WoundData = WoundData.new()
	wound.part_id = &"thigh_l"
	wound.severity = 0.8
	wound.bleed = 0.5
	c.body.wounds.append(wound)
	k.ctx.wounded_ids[c.id] = true
	k.advance_day()
	assert_true(k.ctx.character(c.id) == null, "bled out by the end of the day")
	assert_eq(k.ctx.world.archived_characters[c.id].death_cause, &"bled_out", "cause")
	assert_consistent(k)


func test_small_wounds_heal_and_leave_nothing() -> void:
	var k: SimKernel = _world()
	var c: CharacterData = _person(k, _site(k))
	LimbService.apply_blow(k.ctx, c, &"forearm_r", &"crush", 6.0)
	assert_true(k.ctx.wounded_ids.has(c.id), "being tended")
	k.advance_days(40)
	assert_true(k.ctx.character(c.id) != null, "lives")
	assert_eq(c.body.wounds.size(), 0, "healed")
	assert_eq(c.body.blood, 1.0, "blood back")
	assert_eq(LimbService.capacity(k.ctx, c, &"right_arm"), 1.0, "arm back")
	assert_true(not k.ctx.wounded_ids.has(c.id), "no longer tended")


func test_bad_wounds_leave_a_lasting_mark() -> void:
	var k: SimKernel = _world()
	var c: CharacterData = _person(k, _site(k))
	LimbService.apply_blow(k.ctx, c, &"shin_l", &"crush", 36.0)
	var before: float = LimbService.mobility(k.ctx, c)
	for wound: WoundData in c.body.wounds:
		wound.bleed = 0.0
		wound.infection = 0.0
	# Far past anything that could still heal.
	for i: int in range(120):
		LimbService.tend_day(k.ctx, c, k.ctx.rng(&"test"))
	var after: float = LimbService.mobility(k.ctx, c)
	assert_true(after > before, "it heals some")
	assert_true(after < 1.0, "but he limps for good")
	assert_true(LimbService.frailty(c) > 1.0, "and it wears on him")


func test_infection_can_kill_and_taking_the_limb_ends_it() -> void:
	var k: SimKernel = _world()
	var s: SettlementData = _site(k)
	var lost: CharacterData = _person(k, s)
	LimbService.apply_blow(k.ctx, lost, &"shin_r", &"cut", 14.0)
	lost.body.wounds[0].infection = 0.99
	lost.body.wounds[0].bleed = 0.0
	var killed: bool = false
	for i: int in range(40):
		if not LimbService.tend_day(k.ctx, lost, k.ctx.rng(&"test")):
			killed = true
			break
	assert_true(killed, "left alone it kills")
	assert_eq(k.ctx.world.archived_characters[lost.id].death_cause, &"infection", "cause")
	var saved: CharacterData = _person(k, s)
	LimbService.apply_blow(k.ctx, saved, &"shin_r", &"cut", 14.0)
	saved.body.wounds[0].infection = 0.9
	assert_eq(LimbService.limb_to_save_from(k.ctx, saved, 0.35), &"shin_r", "that limb must go")
	assert_true(Actions.amputate(k.ctx, saved.id, saved.id, &"shin_r").success, "surgeon takes it")
	assert_true(LimbService.is_lost(k.ctx, saved, &"foot_r"), "foot went too")
	for wound: WoundData in saved.body.wounds:
		assert_eq(wound.infection, 0.0, "the bad flesh went with it")
	assert_consistent(k)


func test_only_your_own_limbs_or_those_you_hold_can_be_taken() -> void:
	var k: SimKernel = _world()
	var s: SettlementData = _site(k)
	var a: CharacterData = _person(k, s)
	var b: CharacterData = _person(k, s)
	assert_eq(Actions.amputate(k.ctx, a.id, b.id, &"hand_r").reason, &"not_yours", "not yours")
	assert_eq(Actions.amputate(k.ctx, a.id, a.id, &"torso").reason, &"cannot_take_off", "not that")
	assert_true(Actions.amputate(k.ctx, a.id, a.id, &"hand_r").success, "your own")
	assert_eq(Actions.amputate(k.ctx, a.id, a.id, &"hand_r").reason, &"already_gone", "not twice")


func test_maimed_people_cannot_do_what_they_did() -> void:
	var k: SimKernel = _world()
	var f: FactionData = make_faction(k, &"hallowed")
	var s: SettlementData = make_settlement(k, f)
	var leader: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 30.0, &"soldier", 500)
	var band: WarbandData = make_band(k, leader, SimEnums.WarbandRole.BANDIT, 200)
	var maimed: CharacterData = _person(k, s)
	var b: BusinessData = add_business(k, s, &"farm", SimEnums.OwnerKind.FACTION, f.id)
	var free_price: int = Actions.freedom_price(k.ctx, maimed)
	LimbService.sever(k.ctx, maimed, &"arm_r", 0.0)
	LimbService.sever(k.ctx, maimed, &"arm_l", 0.0)
	assert_eq(Actions.join_warband(k.ctx, maimed.id, band.id).reason, &"unfit", "no use in a warband")
	assert_eq(Actions.take_job(k.ctx, maimed.id, b.id).reason, &"unfit", "no use at work")
	assert_true(Actions.freedom_price(k.ctx, maimed) < free_price, "worth less in bondage")
	assert_consistent(k)


func test_a_maimed_leader_adds_less_to_a_battle() -> void:
	var k: SimKernel = _world()
	var s: SettlementData = _site(k)
	var leader: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 30.0, &"soldier", 500)
	var band: WarbandData = make_band(k, leader, SimEnums.WarbandRole.BANDIT, 200)
	band.troops[&"levy_spearman"] = 10
	var whole: float = BattleResolver.strength(k.ctx, BattleSide.from_band(band))
	LimbService.sever(k.ctx, leader, &"forearm_r", 0.0)
	assert_true(BattleResolver.strength(k.ctx, BattleSide.from_band(band)) < whole, "fights worse")


func test_wounds_survive_a_save_and_are_tended_after() -> void:
	var k: SimKernel = _world()
	var s: SettlementData = _site(k)
	var c: CharacterData = _person(k, s)
	LimbService.apply_blow(k.ctx, c, &"forearm_r", &"cut", 22.0)
	LimbService.sever(k.ctx, c, &"foot_l", 0.5)
	var path: String = "user://test_limbs_save.res"
	assert_eq(k.save_to(path), OK, "saved")
	var loaded: WorldState = SaveGame.load_from(path)
	var again: SimKernel = SimKernel.new(loaded, catalog(), new_hub())
	assert_eq(StateHash.compute(k.ctx.world), StateHash.compute(again.ctx.world), "same after load")
	var back: CharacterData = again.ctx.character(c.id)
	assert_eq(back.body.lost_parts, [&"foot_l"] as Array[StringName], "foot still gone")
	assert_true(again.ctx.wounded_ids.has(c.id), "index rebuilt from state")
	assert_consistent(again)
	DirAccess.remove_absolute(path)


func test_the_player_takes_blows_like_anyone() -> void:
	var k: SimKernel = _world()
	var s: SettlementData = _site(k)
	var player: CharacterData = _person(k, s)
	var other: CharacterData = _person(k, s)
	k.ctx.world.player_character_id = player.id
	_armed(k, other)
	var result: ActionResult = Actions.land_blow(k.ctx, other.id, player.id, &"forearm_l", false)
	assert_true(result.success and (result.detail as LimbBlow).severity > 0.0, "it lands")


func test_battles_wound_named_fighters() -> void:
	var k: SimKernel = small_kernel(11, 200)
	var c: CharacterData = k.ctx.character(k.ctx.character_ids()[0])
	var rng: RandomNumberGenerator = k.ctx.rng(&"test")
	for i: int in range(3):
		if k.ctx.character(c.id) != null:
			LimbService.battle_wounds(k.ctx, c, 2, rng)
	assert_true(k.ctx.stat(&"wounds_taken") > 0, "wounds are counted")
	assert_consistent(k)


func test_a_limp_body_has_no_bones_for_what_it_lost() -> void:
	var skeleton: Skeleton3D = Skeleton3D.new()
	for bone_name: String in ["spine", "arm", "hand", "leg"]:
		skeleton.add_bone(bone_name)
	skeleton.set_bone_parent(1, 0)
	skeleton.set_bone_parent(2, 1)
	skeleton.set_bone_parent(3, 0)
	var everything: Array[String] = ["spine", "arm", "hand", "leg", "missing"]
	assert_eq(Ragdoll.still_there(skeleton, everything), ["spine", "arm", "hand", "leg"] as Array[String], "all there")
	skeleton.set_bone_pose_scale(1, Vector3.ONE * LimbView.GONE)
	assert_eq(Ragdoll.still_there(skeleton, everything), ["spine", "leg"] as Array[String], "the arm took the hand with it")
	skeleton.free()


func test_segment_distance_measures_the_closest_points() -> void:
	var a: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3(1.0, 0.0, 0.0)])
	var crossing: PackedVector3Array = PackedVector3Array([Vector3(0.5, 0.3, -1.0), Vector3(0.5, 0.3, 1.0)])
	assert_true(absf(Ragdoll.segment_distance(a, crossing) - 0.3) < 0.001, "passing over at 0.3")
	var beyond: PackedVector3Array = PackedVector3Array([Vector3(2.0, 0.0, 0.0), Vector3(3.0, 0.0, 0.0)])
	assert_true(absf(Ragdoll.segment_distance(a, beyond) - 1.0) < 0.001, "end to end")


func test_ragdoll_neighbours_are_real_bones() -> void:
	var seen: Array[String] = []
	for spec: Dictionary in Ragdoll.BONES:
		seen.append(spec["bone"] as String)
	for pair: Array in Ragdoll.NEIGHBOURS:
		assert_true(seen.has(pair[0] as String) and seen.has(pair[1] as String), "pair %s is real" % str(pair))


func test_every_ragdoll_bone_runs_to_a_real_end() -> void:
	var seen: Array[String] = []
	for spec: Dictionary in Ragdoll.BONES:
		var bone_name: String = spec["bone"]
		assert_true(spec.has("end") or spec.has("length"), "%s has a length" % bone_name)
		seen.append(bone_name)
	for part_id: StringName in LimbView.BONES:
		var limb_bone: String = LimbView.BONES[part_id]
		assert_true(seen.has(limb_bone) or part_id == &"neck", "%s has a ragdoll bone" % part_id)


func test_every_troop_carries_real_gear() -> void:
	var defs: DefCatalog = catalog()
	for id: StringName in defs.troop_ids:
		var troop: TroopDef = defs.troops[id]
		assert_true(defs.weapons.has(troop.weapon_id), "%s has a real weapon" % id)
		for armour_id: StringName in troop.armour_ids:
			assert_true(defs.armours.has(armour_id), "%s wears real armour" % id)
		assert_true(BodyView.WEAPON_PARTS.has(troop.weapon_id), "%s's weapon has a model" % id)


func test_joining_a_band_arms_the_unarmed_with_what_it_carries() -> void:
	var k: SimKernel = _world()
	var s: SettlementData = _site(k)
	var leader: CharacterData = make_person(k, s, &"human", SimEnums.Sex.MALE, 30.0, &"soldier", 500)
	var band: WarbandData = make_band(k, leader, SimEnums.WarbandRole.BANDIT, 200)
	var levy: TroopDef = k.ctx.defs.troops[TroopOps.levy_for(k.ctx, s)]
	assert_true(levy.weapon_choices.has(leader.equipment.weapon_id), "a band with no troops hands out what levies carry")
	band.troops[&"man_at_arms"] = 3
	band.troops[&"levy_spearman"] = 3
	var joiner: CharacterData = _person(k, s)
	assert_true(Actions.join_warband(k.ctx, joiner.id, band.id).success, "joins")
	assert_true(k.ctx.defs.troops[&"man_at_arms"].weapon_choices.has(joiner.equipment.weapon_id), "gets what the best soldiers carry")
	assert_true(joiner.equipment.armour_ids.has(&"mail_hauberk"), "and their mail")


# --- Walking freely, and the player's hands ---------------------------------

func _free_input(look: Vector2, move: Vector2) -> DuelInput:
	var input: DuelInput = DuelInput.new()
	input.free = true
	input.look = look
	input.move = move
	return input


func test_a_free_fighter_faces_and_walks_where_they_look() -> void:
	var k: SimKernel = _world()
	var fight: DuelFight = _duel(k)
	var input: DuelInput = _free_input(Vector2(1.0, 0.0), Vector2(0.0, 1.0))
	var start: Vector2 = fight.a.position
	_run(fight, 1.0, input, DuelInput.new())
	assert_true(fight.a.facing.dot(Vector2(1.0, 0.0)) > 0.99, "turned the way they look, away from the opponent")
	assert_true(fight.a.position.x - start.x > 1.0, "walked that way")
	assert_true(fight.a.target == null, "with no one to turn to")


func test_a_free_blow_lands_on_who_is_in_front_and_not_who_is_behind() -> void:
	var k: SimKernel = _world()
	var fight: DuelFight = _duel(k)
	_at_arms_length(fight)
	var away: DuelInput = _free_input(Vector2(0.0, -1.0), Vector2.ZERO)
	_run(fight, 0.5, away, DuelInput.new())
	away.attack = DuelFighter.Move.OVERHEAD
	_run(fight, 0.8, away, DuelInput.new())
	assert_eq(_wounds_on(k, fight.b.character_id), 0, "turned away, it misses")
	var facing: DuelInput = _free_input(Vector2(0.0, 1.0), Vector2.ZERO)
	_run(fight, 0.5, facing, DuelInput.new())
	facing.attack = DuelFighter.Move.OVERHEAD
	_run(fight, 0.8, facing, DuelInput.new())
	assert_true(_wounds_on(k, fight.b.character_id) > 0, "facing them, it lands")


func test_running_is_faster_and_costs_breath() -> void:
	var k: SimKernel = _world()
	var fight: DuelFight = _duel(k)
	var input: DuelInput = _free_input(Vector2(1.0, 0.0), Vector2(0.0, 1.0))
	_run(fight, 0.5, input, DuelInput.new())
	var walking: float = fight.a.velocity.length()
	input.sprint = true
	_run(fight, 0.5, input, DuelInput.new())
	assert_true(fight.a.velocity.length() > walking * 1.4, "runs")
	assert_true(fight.a.stamina < 1.0, "out of breath")


func _key(key: Key, pressed: bool) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	return event


func _pad_button(button: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	return event


func _pad_axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event


func _controls_for(fight: DuelFight) -> FightControls:
	var controls: FightControls = FightControls.new()
	controls.begin(fight.a)
	return controls


func test_keys_walk_relative_to_the_camera_and_run_with_shift() -> void:
	var k: SimKernel = _world()
	var fight: DuelFight = _duel(k)
	var controls: FightControls = _controls_for(fight)
	controls.handle_event(_key(KEY_W, true))
	controls.handle_event(_key(KEY_D, true))
	var input: DuelInput = controls.read(fight, fight.a, 0.016)
	assert_true(input.free, "free unless locked")
	assert_true(input.move.x > 0.0 and input.move.y > 0.0, "forward and right")
	assert_true(absf(input.move.length() - 1.0) < 0.001, "no faster on a diagonal")
	controls.handle_event(_key(KEY_SHIFT, true))
	assert_true(controls.read(fight, fight.a, 0.016).sprint, "shift runs")


func test_the_mouse_turns_you_and_picks_the_way_of_a_blow() -> void:
	var k: SimKernel = _world()
	var fight: DuelFight = _duel(k)
	var controls: FightControls = _controls_for(fight)
	var yaw: float = controls.yaw
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(30.0, 0.0)
	controls.handle_event(motion)
	assert_true(controls.yaw < yaw, "right turns right")
	assert_eq(controls.aim_move, DuelFighter.Move.RIGHT, "and picks the right")
	assert_eq(controls.aim_guard, DuelFighter.Guard.RIGHT, "for the guard too")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	controls.handle_event(click)
	assert_eq(controls.read(fight, fight.a, 0.016).attack, DuelFighter.Move.RIGHT, "a click strikes that way")


func test_locking_on_is_a_choice_and_lets_go_of_the_fallen() -> void:
	var k: SimKernel = _world()
	var fight: DuelFight = _duel(k)
	var controls: FightControls = _controls_for(fight)
	assert_true(controls.read(fight, fight.a, 0.016).target == null, "nobody until asked")
	controls.handle_event(_key(KEY_Q, true))
	var input: DuelInput = controls.read(fight, fight.a, 0.016)
	assert_eq(input.target, fight.b, "locks on to who is ahead")
	assert_true(not input.free, "and turns to them")
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(30.0, 0.0)
	var yaw: float = controls.yaw
	controls.handle_event(motion)
	assert_eq(controls.yaw, yaw, "the mouse still picks a way but no longer turns you")
	controls.handle_event(_key(KEY_Q, false))
	controls.handle_event(_key(KEY_Q, true))
	assert_true(controls.read(fight, fight.a, 0.016).free, "asked again, it lets go")
	controls.handle_event(_key(KEY_Q, true))
	controls.read(fight, fight.a, 0.016)
	fight.b._set_state(DuelFighter.State.DEAD)
	assert_true(controls.read(fight, fight.a, 0.016).free, "the fallen cannot be locked on to")


func test_nobody_behind_you_gets_locked_on_to() -> void:
	var k: SimKernel = _world()
	var fight: DuelFight = _duel(k)
	var controls: FightControls = _controls_for(fight)
	controls.yaw = PI
	controls.handle_event(_key(KEY_Q, true))
	assert_true(controls.read(fight, fight.a, 0.016).target == null, "they are behind")


func test_an_xbox_pad_does_it_all() -> void:
	var k: SimKernel = _world()
	var fight: DuelFight = _duel(k)
	var controls: FightControls = _controls_for(fight)
	controls.handle_event(_pad_axis(JOY_AXIS_LEFT_Y, -1.0))
	assert_true(controls.read(fight, fight.a, 0.016).move.y > 0.9, "stick up walks forward")
	assert_true(controls.using_pad, "and prompts know it")
	controls.handle_event(_pad_axis(JOY_AXIS_LEFT_Y, -0.1))
	assert_eq(controls.read(fight, fight.a, 0.016).move, Vector2.ZERO, "a resting stick does nothing")
	var yaw: float = controls.yaw
	controls.handle_event(_pad_axis(JOY_AXIS_RIGHT_X, -1.0))
	controls.read(fight, fight.a, 0.1)
	assert_true(controls.yaw > yaw, "right stick turns")
	assert_eq(controls.aim_move, DuelFighter.Move.LEFT, "and picks the way")
	controls.handle_event(_pad_axis(JOY_AXIS_RIGHT_X, 0.0))
	controls.handle_event(_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0))
	assert_eq(controls.read(fight, fight.a, 0.016).attack, DuelFighter.Move.LEFT, "RT strikes that way")
	fight.a._set_state(DuelFighter.State.WINDUP, 0.5)
	controls.after_step(fight.a)
	assert_eq(controls.read(fight, fight.a, 0.016).attack, DuelFighter.Move.NONE, "once, for holding it")
	fight.a._set_state(DuelFighter.State.READY)
	controls.after_step(fight.a)
	controls.handle_event(_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0))
	controls.read(fight, fight.a, 0.016)
	controls.handle_event(_pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0))
	assert_eq(controls.read(fight, fight.a, 0.016).guard, DuelFighter.Guard.LEFT, "LT guards that way")
	controls.handle_event(_pad_axis(JOY_AXIS_TRIGGER_LEFT, 0.0))
	controls.handle_event(_pad_button(JOY_BUTTON_RIGHT_SHOULDER, true))
	assert_eq(controls.read(fight, fight.a, 0.016).attack, DuelFighter.Move.THRUST, "RB thrusts")
	controls.handle_event(_pad_button(JOY_BUTTON_RIGHT_STICK, true))
	controls.yaw = atan2(fight.a.facing.x, fight.a.facing.y)
	assert_eq(controls.read(fight, fight.a, 0.016).target, fight.b, "R3 locks on")
	assert_eq(controls.handle_event(_pad_button(JOY_BUTTON_X, true)), FightControls.FINISH, "X asks for the kill")
	assert_eq(controls.handle_event(_pad_button(JOY_BUTTON_A, true)), FightControls.SPARE, "A spares")
	assert_eq(controls.handle_event(_pad_button(JOY_BUTTON_START, true)), FightControls.RESTART, "Start restarts")


func test_giving_up_and_running_must_be_held() -> void:
	var k: SimKernel = _world()
	var fight: DuelFight = _duel(k)
	var controls: FightControls = _controls_for(fight)
	controls.handle_event(_pad_button(JOY_BUTTON_Y, true))
	assert_true(not controls.read(fight, fight.a, 0.1).give_up, "a tap does not give up")
	controls.handle_event(_pad_button(JOY_BUTTON_Y, false))
	controls.handle_event(_key(KEY_G, true))
	assert_true(not controls.read(fight, fight.a, 0.1).flee, "nor run")
	for i: int in range(6):
		controls.read(fight, fight.a, 0.1)
	assert_true(controls.input.flee, "held, it runs")
	controls.handle_event(_key(KEY_Y, true))
	for i: int in range(9):
		controls.read(fight, fight.a, 0.1)
	assert_true(controls.input.give_up, "held, it gives up")


func test_a_face_comes_back_when_someone_returns_from_the_crowd() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	var face: FaceData = FaceService.random_face(rng, catalog().races[&"human"], true, 0.5, &"caucasian")
	var worn: Array[String] = BodyView.PLAIN_CLOTHES.duplicate()
	var body: Node3D = BodyView.make(face, true, 0.2, worn, true)
	var head: Node3D = FaceView.attach(body, face, true, 0.2)
	var shown: Array[String] = _shown_parts(head)
	assert_true(shown.has("skin"), "a face to begin with")
	BodyView.show_detail(body, face, true, 0.2, worn, false)
	assert_eq(_shown_parts(head), shown, "going to full detail leaves the face alone")
	BodyView.show_detail(body, face, true, 0.2, worn, true)
	BodyView.show_detail(body, face, true, 0.2, worn, false)
	assert_eq(_shown_parts(head), shown, "and so does going to the crowd and coming back")
	body.free()


func _shown_parts(head: Node3D) -> Array[String]:
	var out: Array[String] = []
	for part: Node in head.find_children("*", "MeshInstance3D", true, false):
		if (part as MeshInstance3D).visible:
			out.append(String(part.name))
	out.sort()
	return out


# --- A battle ---------------------------------------------------------------

func _battle(k: SimKernel, per_side: int, near: StringName = &"man_at_arms", far: StringName = &"man_at_arms") -> LocalFight:
	var s: SettlementData = _site(k)
	var fight: LocalFight = LocalFight.new(k.ctx)
	fight.arena_radius = 17.0
	for side: int in range(2):
		for i: int in range(per_side):
			var c: CharacterData = _person(k, s)
			Actions.kit_out(k.ctx, c.id, near if side == 0 else far)
			fight.add_fighter(c.id, side, Vector2(float(i) * 1.9, -5.0 if side == 0 else 5.0), Vector2(0.0, 1.0 if side == 0 else -1.0))
	return fight


func _fight_it_out(fight: LocalFight, seconds: float) -> void:
	var agents: Array[DuelAgent] = []
	for f: DuelFighter in fight.fighters:
		agents.append(DuelAgent.new(fight, f))
	var inputs: Array[DuelInput] = []
	inputs.resize(fight.fighters.size())
	for tick: int in range(roundi(seconds / LocalFight.STEP)):
		if fight.over:
			return
		for i: int in range(agents.size()):
			inputs[i] = agents[i].decide(LocalFight.STEP)
		fight.step_all(inputs)


func test_a_battle_runs_until_one_side_is_gone() -> void:
	var k: SimKernel = _world()
	var fight: LocalFight = _battle(k, 5)
	_fight_it_out(fight, 300.0)
	assert_true(fight.over, "it ends")
	assert_eq(fight.standing_on(1 - fight.winning_side), 0, "nobody is left on the losing side")
	assert_true(fight.standing_on(fight.winning_side) > 0, "somebody holds the field")
	assert_consistent(k)


func test_a_much_bigger_side_wins() -> void:
	var wins: int = 0
	for i: int in range(5):
		var k: SimKernel = _world()
		var s: SettlementData = _site(k)
		var fight: LocalFight = LocalFight.new(k.ctx)
		fight.arena_radius = 17.0
		for n: int in range(8):
			var side: int = 0 if n < 6 else 1
			var c: CharacterData = _person(k, s)
			Actions.kit_out(k.ctx, c.id, &"man_at_arms")
			fight.add_fighter(c.id, side, Vector2(float(n % 6) * 1.9, -5.0 if side == 0 else 5.0), Vector2(0.0, 1.0 if side == 0 else -1.0))
		k.ctx.rng(&"blows").seed = 500 + i
		k.ctx.rng(&"duel_agent").seed = 900 + i
		_fight_it_out(fight, 300.0)
		if fight.winning_side == 0:
			wins += 1
	assert_true(wins >= 4, "six beat two, %d of 5" % wins)


func test_a_blow_from_behind_gets_past_a_raised_shield() -> void:
	var k: SimKernel = _world()
	var fight: LocalFight = _battle(k, 1)
	var attacker: DuelFighter = fight.fighters[0]
	var defender: DuelFighter = fight.fighters[1]
	attacker.position = Vector2(0.0, 0.0)
	attacker.facing = Vector2(0.0, 1.0)
	defender.position = Vector2(0.0, 1.0)
	defender.facing = Vector2(0.0, 1.0)
	var guard: DuelFighter = defender
	guard.guard = DuelFighter.Guard.UP
	guard._set_state(DuelFighter.State.GUARD)
	guard.state_time = 1.0
	attacker.move = DuelFighter.Move.OVERHEAD
	assert_true(not fight._is_covered(defender, attacker), "a shield does not guard the back")
	defender.facing = Vector2(0.0, -1.0)
	assert_true(fight._is_covered(defender, attacker), "but it does guard the front")


func test_a_blow_finds_whoever_is_in_its_way() -> void:
	var k: SimKernel = _world()
	var fight: LocalFight = _battle(k, 2)
	var attacker: DuelFighter = fight.fighters[0]
	attacker.position = Vector2(0.0, 0.0)
	attacker.facing = Vector2(0.0, 1.0)
	attacker.move = DuelFighter.Move.OVERHEAD
	fight.fighters[1].position = Vector2(0.5, 0.5)
	fight.fighters[2].position = Vector2(0.0, 1.0)
	fight.fighters[3].position = Vector2(0.0, 8.0)
	attacker.target = fight.fighters[3]
	assert_eq(fight._found_by(attacker), fight.fighters[2], "out of reach of the target, it finds an enemy, and never a friend")
	attacker.target = fight.fighters[2]
	fight.fighters[3].position = Vector2(0.2, 0.6)
	assert_eq(fight._found_by(attacker), fight.fighters[2], "the one aimed at comes first")


func test_people_who_run_leave_the_field_alive() -> void:
	var k: SimKernel = _world()
	var fight: LocalFight = _battle(k, 2)
	var runner: DuelFighter = fight.fighters[0]
	var inputs: Array[DuelInput] = []
	for f: DuelFighter in fight.fighters:
		var input: DuelInput = DuelInput.new()
		input.flee = f == runner
		inputs.append(input)
	for tick: int in range(60 * 30):
		fight.step_all(inputs)
	assert_eq(runner.state, DuelFighter.State.FLED, "got away")
	assert_true(k.ctx.character(runner.character_id) != null, "alive")
	assert_true(not fight.over, "the others fight on")


func test_a_losing_side_breaks() -> void:
	var fled: int = 0
	for i: int in range(6):
		var k: SimKernel = _world()
		var s: SettlementData = _site(k)
		var fight: LocalFight = LocalFight.new(k.ctx)
		fight.arena_radius = 17.0
		for n: int in range(12):
			var side: int = 0 if n < 9 else 1
			var c: CharacterData = _person(k, s)
			Actions.kit_out(k.ctx, c.id, &"man_at_arms" if side == 0 else &"rebel_militia")
			fight.add_fighter(c.id, side, Vector2(float(n % 9) * 1.9, -5.0 if side == 0 else 5.0), Vector2(0.0, 1.0 if side == 0 else -1.0))
		k.ctx.rng(&"duel_agent").seed = 300 + i
		_fight_it_out(fight, 300.0)
		for f: DuelFighter in fight.fighters:
			if f.side == 1 and f.state == DuelFighter.State.FLED:
				fled += 1
	assert_true(fled > 0, "someone runs from a battle they are losing badly")


# --- The duel ---------------------------------------------------------------

func _duel(k: SimKernel, shield_a: bool = false, shield_b: bool = false) -> DuelFight:
	var s: SettlementData = _site(k)
	var a: CharacterData = _person(k, s)
	var b: CharacterData = _person(k, s)
	_armed(k, a, shield_a)
	_armed(k, b, shield_b)
	return DuelFight.new(k.ctx, a.id, b.id)


func _at_arms_length(fight: DuelFight) -> void:
	fight.a.position = Vector2(0.0, -0.55)
	fight.b.position = Vector2(0.0, 0.55)


func _run(fight: DuelFight, seconds: float, input_a: DuelInput, input_b: DuelInput) -> void:
	for i: int in range(roundi(seconds / DuelFight.STEP)):
		fight.step(input_a, input_b)
		input_a.attack = DuelFighter.Move.NONE
		input_b.attack = DuelFighter.Move.NONE


func _wounds_on(k: SimKernel, id: int) -> int:
	var c: CharacterData = k.ctx.character(id)
	return c.body.wounds.size() if c != null else -1


func test_a_blow_out_of_reach_misses() -> void:
	var k: SimKernel = _world()
	var fight: DuelFight = _duel(k)
	var attack: DuelInput = DuelInput.new()
	attack.attack = DuelFighter.Move.OVERHEAD
	_run(fight, 1.2, attack, DuelInput.new())
	assert_eq(_wounds_on(k, fight.b.character_id), 0, "too far away")


func test_a_blow_in_reach_with_no_guard_wounds() -> void:
	var k: SimKernel = _world()
	var fight: DuelFight = _duel(k)
	_at_arms_length(fight)
	var attack: DuelInput = DuelInput.new()
	attack.attack = DuelFighter.Move.LOW
	_run(fight, 0.7, attack, DuelInput.new())
	assert_true(_wounds_on(k, fight.b.character_id) > 0, "it lands")
	assert_eq(fight.b.state, DuelFighter.State.STAGGER, "and staggers")
	var hit_leg: bool = false
	for wound: WoundData in k.ctx.character(fight.b.character_id).body.wounds:
		hit_leg = hit_leg or wound.part_id.begins_with("thigh") or wound.part_id.begins_with("shin") or wound.part_id.begins_with("foot")
	assert_true(hit_leg, "a low cut lands low")


func test_a_blade_only_stops_a_blow_it_meets() -> void:
	var k: SimKernel = _world()
	var fight: DuelFight = _duel(k)
	_at_arms_length(fight)
	var attack: DuelInput = DuelInput.new()
	var guard: DuelInput = DuelInput.new()
	guard.guard = DuelFighter.Guard.UP
	attack.attack = DuelFighter.Move.OVERHEAD
	_run(fight, 1.0, attack, guard)
	assert_eq(_wounds_on(k, fight.b.character_id), 0, "up stops overhead")
	var other: DuelFight = _duel(k)
	_at_arms_length(other)
	var side: DuelInput = DuelInput.new()
	var guard_up: DuelInput = DuelInput.new()
	guard_up.guard = DuelFighter.Guard.UP
	side.attack = DuelFighter.Move.LEFT
	_run(other, 1.0, side, guard_up)
	assert_true(_wounds_on(k, other.b.character_id) > 0, "up does not stop a side cut")


func test_a_shield_covers_all_but_a_low_cut() -> void:
	var k: SimKernel = _world()
	var fight: DuelFight = _duel(k, false, true)
	_at_arms_length(fight)
	var attack: DuelInput = DuelInput.new()
	var guard: DuelInput = DuelInput.new()
	guard.guard = DuelFighter.Guard.UP
	attack.attack = DuelFighter.Move.LEFT
	_run(fight, 1.0, attack, guard)
	assert_eq(_wounds_on(k, fight.b.character_id), 0, "shield stops a side cut")
	var low: DuelFight = _duel(k, false, true)
	_at_arms_length(low)
	var cut: DuelInput = DuelInput.new()
	var high: DuelInput = DuelInput.new()
	high.guard = DuelFighter.Guard.UP
	cut.attack = DuelFighter.Move.LOW
	_run(low, 1.0, cut, high)
	assert_true(_wounds_on(k, low.b.character_id) > 0, "a low cut goes under it")


func test_a_late_guard_parries_and_an_early_one_only_blocks() -> void:
	var k: SimKernel = _world()
	var fight: DuelFight = _duel(k)
	_at_arms_length(fight)
	var attack: DuelInput = DuelInput.new()
	attack.attack = DuelFighter.Move.OVERHEAD
	var idle: DuelInput = DuelInput.new()
	var guard: DuelInput = DuelInput.new()
	guard.guard = DuelFighter.Guard.UP
	_run(fight, 0.33, attack, idle)
	_run(fight, 0.3, attack, guard)
	assert_eq(fight.a.state, DuelFighter.State.STAGGER, "the attacker is thrown off")
	var early: DuelFight = _duel(k)
	_at_arms_length(early)
	var held: DuelInput = DuelInput.new()
	held.guard = DuelFighter.Guard.UP
	_run(early, 0.5, DuelInput.new(), held)
	var late_attack: DuelInput = DuelInput.new()
	late_attack.attack = DuelFighter.Move.OVERHEAD
	_run(early, 0.7, late_attack, held)
	assert_eq(early.a.state, DuelFighter.State.RECOVER, "the attacker just recovers")


func test_a_tired_guard_breaks() -> void:
	var k: SimKernel = _world()
	var fight: DuelFight = _duel(k)
	_at_arms_length(fight)
	fight.b.stamina = 0.05
	var held: DuelInput = DuelInput.new()
	held.guard = DuelFighter.Guard.UP
	_run(fight, 0.4, DuelInput.new(), held)
	fight.b.stamina = 0.05
	var attack: DuelInput = DuelInput.new()
	attack.attack = DuelFighter.Move.OVERHEAD
	_run(fight, 0.6, attack, held)
	assert_eq(fight.b.state, DuelFighter.State.STAGGER, "guard broken")
	assert_eq(_wounds_on(k, fight.b.character_id), 0, "though the blow itself was stopped")


func test_wounds_slow_a_fighter() -> void:
	var k: SimKernel = _world()
	var fight: DuelFight = _duel(k)
	var walk: DuelInput = DuelInput.new()
	walk.move = Vector2(0.0, 1.0)
	_run(fight, 0.2, walk, DuelInput.new())
	var whole: float = fight.a.velocity.length()
	LimbService.apply_blow(k.ctx, k.ctx.character(fight.a.character_id), &"thigh_l", &"crush", 30.0)
	_run(fight, 0.2, walk, DuelInput.new())
	assert_true(fight.a.velocity.length() < whole * 0.9, "a bad leg slows them")


func test_losing_the_sword_hand_ends_the_fight_alive() -> void:
	var k: SimKernel = _world()
	var fight: DuelFight = _duel(k)
	LimbService.sever(k.ctx, k.ctx.character(fight.b.character_id), &"hand_r", 0.0)
	_run(fight, 0.1, DuelInput.new(), DuelInput.new())
	assert_eq(fight.b.state, DuelFighter.State.YIELDED, "gives up")
	assert_true(fight.over, "over")
	assert_eq(fight.winner_id, fight.a.character_id, "other side wins")
	assert_true(k.ctx.character(fight.b.character_id) != null, "still alive")


func test_losing_a_leg_puts_a_fighter_down() -> void:
	var k: SimKernel = _world()
	var fight: DuelFight = _duel(k)
	var b: CharacterData = k.ctx.character(fight.b.character_id)
	LimbService.sever(k.ctx, b, &"thigh_l", 0.0)
	LimbService.sever(k.ctx, b, &"shin_r", 0.0)
	_run(fight, 0.1, DuelInput.new(), DuelInput.new())
	assert_eq(fight.b.state, DuelFighter.State.DOWN, "falls")


func test_losing_the_shield_arm_loses_the_shield() -> void:
	var k: SimKernel = _world()
	var fight: DuelFight = _duel(k, false, true)
	LimbService.sever(k.ctx, k.ctx.character(fight.b.character_id), &"forearm_l", 0.0)
	_run(fight, 0.1, DuelInput.new(), DuelInput.new())
	assert_true(not fight.b.has_shield, "no arm for it")
	assert_true(not fight.over, "still fighting")


func test_two_npcs_fight_it_out_and_the_world_stays_consistent() -> void:
	var finished: int = 0
	for world_seed: int in range(5):
		var k: SimKernel = small_kernel(100 + world_seed, 120)
		var ids: Array[int] = []
		for id: int in k.ctx.character_ids():
			if k.ctx.is_adult(k.ctx.character(id)) and ids.size() < 2:
				ids.append(id)
		for id: int in ids:
			_armed(k, k.ctx.character(id), id == ids[0])
		var fight: DuelFight = DuelFight.new(k.ctx, ids[0], ids[1])
		var first: DuelAgent = DuelAgent.new(fight, fight.a)
		var second: DuelAgent = DuelAgent.new(fight, fight.b)
		for i: int in range(roundi(240.0 / DuelFight.STEP)):
			fight.step(first.decide(DuelFight.STEP), second.decide(DuelFight.STEP))
			if fight.over:
				finished += 1
				break
		assert_consistent(k)
	assert_true(finished >= 4, "fights end, %d of 5 did" % finished)


func test_the_same_fight_comes_out_the_same() -> void:
	var results: Array[String] = []
	for i: int in range(2):
		var k: SimKernel = small_kernel(55, 120)
		var ids: Array[int] = k.ctx.character_ids().slice(0, 40).filter(func(id: int) -> bool: return k.ctx.is_adult(k.ctx.character(id)))
		for id: int in ids.slice(0, 2):
			_armed(k, k.ctx.character(id))
		var fight: DuelFight = DuelFight.new(k.ctx, ids[0], ids[1])
		var first: DuelAgent = DuelAgent.new(fight, fight.a)
		var second: DuelAgent = DuelAgent.new(fight, fight.b)
		for step_index: int in range(3600):
			fight.step(first.decide(DuelFight.STEP), second.decide(DuelFight.STEP))
		k.ctx.sync_rng_to_world()
		results.append(StateHash.compute(k.ctx.world))
	assert_eq(results[0], results[1], "same seed, same fight")


func test_a_finishing_stroke_kills_and_mercy_spares() -> void:
	var k: SimKernel = _world()
	var fight: DuelFight = _duel(k)
	LimbService.sever(k.ctx, k.ctx.character(fight.b.character_id), &"hand_r", 0.0)
	_run(fight, 0.1, DuelInput.new(), DuelInput.new())
	fight.spare()
	assert_true(k.ctx.character(fight.b.character_id) != null, "spared lives")
	fight.finish()
	assert_true(k.ctx.character(fight.b.character_id) == null, "finished does not")
	assert_consistent(k)


func test_a_duel_uses_only_its_own_random_streams() -> void:
	var k: SimKernel = _world()
	var fight: DuelFight = _duel(k)
	_at_arms_length(fight)
	var before: int = k.ctx.rng(&"life").state
	var attack: DuelInput = DuelInput.new()
	attack.attack = DuelFighter.Move.LEFT
	_run(fight, 1.0, attack, DuelInput.new())
	assert_eq(k.ctx.rng(&"life").state, before, "other streams untouched")
