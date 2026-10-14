class_name GameSettingsImpl
extends Node
## Global settings autoload. Holds user-facing settings persisted under user://.
## Persistence and the settings schema arrive with the save slice.

## Version of the persisted settings schema.
const SCHEMA_VERSION: int = 1
