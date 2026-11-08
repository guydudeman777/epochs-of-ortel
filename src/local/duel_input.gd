class_name DuelInput
extends RefCounted
## What one fighter wants this moment. The player's keys and the AI's choices both come down to this.

## x is to the fighter's right, y is ahead: towards the opponent, or the way they are looking when free. Length up to 1.
var move: Vector2 = Vector2.ZERO
## A DuelFighter.Move to start, or NONE.
var attack: DuelFighter.Move = DuelFighter.Move.NONE
## A DuelFighter.Guard to hold, or NONE.
var guard: DuelFighter.Guard = DuelFighter.Guard.NONE
var give_up: bool = false
## Whom to fight, or null for whoever is nearest.
var target: DuelFighter = null
## Makes for the edge of the field, and out of the fight.
var flee: bool = false
## Walks and faces freely, with no one to turn towards. Blows land on whoever is in front.
var free: bool = false
## The way to face when free.
var look: Vector2 = Vector2(0.0, 1.0)
## Runs forward, for as long as breath lasts.
var sprint: bool = false
