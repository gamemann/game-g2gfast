extends DotPlatformIdentity

const G2GAvatars := preload("g2g_avatars.gd")

## Content, profiles, avatars and admission: dot-platform's [DotPlatformIdentity], over
## this game's avatar schema.
##
## [b]This game already had the avatar half and not the rest.[/b] `G2GAvatars` has
## described a schema and six stock parts since it was written, `G2GModule._avatar_for`
## has duck-typed its way to a platform module that nothing was loading, and
## `G2GRig.dress` has drawn whatever it was handed. What was missing is the thing that
## produces an avatar that is not a stock one, and that is now the shared chain.
##
## [b]The schema is the rig's, not a second one.[/b] `G2GRig.dress` conforms every
## document to it, so a manager validating against a different schema would accept
## avatars the rig then silently rewrote.


func _init() -> void:
	avatar_schema = G2GAvatars.schema()
	stock_avatar_fn = G2GAvatars.stock_avatar
	avatar_translate_fn = G2GAvatars.from_site
