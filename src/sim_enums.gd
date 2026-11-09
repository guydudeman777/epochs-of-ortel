class_name SimEnums
## Shared enumerations. Ordered enums (RaceStanding, BondageLaw) are compared with >=.

enum Sex { FEMALE, MALE }
enum LegalStatus { FREE, SERF, INDENTURED, ENSLAVED }
enum RaceStanding { ENSLAVABLE, SUBJUGATED, TOLERATED, CITIZEN, PRIVILEGED }
enum BondageLaw { BANNED, PENAL_ONLY, DEBT, CHATTEL }
enum BondageOrigin { NONE, CAPTIVE, RAID, DEBT, PENAL, BIRTH }
enum OwnerKind { NONE, CHARACTER, FACTION }
enum MixedHeritageRule { DOMINANT, LOWEST }
enum WarbandRole { PARTY, CARAVAN, ARMY, BANDIT, SLAVER, REBEL }
enum WarbandGoal { IDLE, TRAVEL, RAID, SIEGE }
enum SettlementKind { CITY, TOWN }

enum WoundLevel { UNHURT, BRUISED, HURT, BADLY_HURT, CRIPPLED, RUINED, LOST }
