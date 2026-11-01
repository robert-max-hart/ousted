# ----------------------------------------------------------------
# SfxHolder
#     The node that keeps the sound players alive under the scene tree's root (see Sfx). It also hears the window gain and lose focus and
#     tells Sfx, which mutes the game while the window is behind another if the player chose that (Settings.mute_unfocused).
# ----------------------------------------------------------------
class_name SfxHolder extends Node;

func _notification(what:int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
        Sfx.on_focus(false);
    elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
        Sfx.on_focus(true);
