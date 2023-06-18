# Undead Fortitude

https://github.com/JustinFreitas/UndeadFortitude

Undead Fortitude v2.0, by Justin Freitas

ReadMe and Usage Notes

When damage is applied to an NPC or PC with the Undead Fortitude trait, the target will roll a constitution save with a DC of 5 + the damage taken.  If success, the target will be left with one hit point instead of dying.  If the damage type is at least part radiant or the hit is a critical hit, Undead Fortitude has no effect and will not be triggered (target will go unconscious, as normal).  This saves lots of time and frustration in zombie encounters for my ToA game because I'm not having to repeatedly fix HP and remove the unconscious effect in these big hoard fights we are running.

There is a radial menu option in the 11 o'clock position when right clicking on a CT actor that allows for Undead Fortitude to be applied to an Unconscious actor.  If invoked, it will leave the actor with one wound remaining until max hp and also remove the Unconscious and Prone effects if they exist.  This will work even if the target doesn't have the Undead Fortitude trait.

A chat command /uf (or /undeadfortitude) was added to do the application to apply the Undead Fortitude result to the specified Combat Tracker actor (case sensitive).  The first match found will be used.  This will work even if the target doesn't have the Undead Fortitude trait.  For example: /uf Zombie

Changelist:
- v1.0 - Initial version.
- v1.1 - Add radial menu button and chat command to apply Undead Fortitude to an Unconscious Combat Tracker actor.
- v2.0 - Change the way the mechanism works by removing the queue and using the roll to pass data directly.  Add the ability to customize the behavior based off of the PC/NPC trait name.  For example, Undead Fortitude (MOD 10) will use 10 instead of 5 when processing Undead Fortitude DC calculations.  Something like Death Fortitude (DC 11) will trigger the behavior with a static DC of 11 and no radiant damage restriction because the word Undead isn't before Fortitude.  Another example is Undead Fortitude (Mod 8, no mods) which will trigger the behavior with a DC modifier of 8 instead of 5 and not have the radiant damage or critical hit restrictions.  Use the name of the fortitude trait specified on the creature in the saving throw text and the matching of that saving throw text.  That way, customized fortitude trait names will show instead of hardcoded Undead Fortitude.
