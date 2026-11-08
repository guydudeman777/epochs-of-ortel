class_name QuestData
extends Resource
## Something someone in the world wants done, made from the world as it stands. NPCs take quests too.

enum State { OFFERED, TAKEN, DONE, FAILED, LAPSED }

@export var id: int = -1
## What kind of want this is, such as &"hunt_band", &"bring_goods", &"ransom_kin". The QuestSystem knows each kind.
@export var kind: StringName = &""
@export var state: State = State.OFFERED
@export var giver_id: int = -1
## Who took it, or -1.
@export var taker_id: int = -1
## Where it is offered.
@export var settlement_id: int = -1
## What it is about: a band, a person, a town, by id, as the kind needs.
@export var target_id: int = -1
## A good, troop or garment id, as the kind needs.
@export var target_thing: StringName = &""
@export var amount: int = 0
@export var reward_gold: int = 0
@export var offered_day: int = -1
## The day it lapses or fails if not done.
@export var due_day: int = -1
## One line for the quest log, written when the quest is made.
@export var summary: String = ""
