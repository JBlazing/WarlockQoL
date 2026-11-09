<p align="center"><img src="assets/soul-shard.svg" width="128" alt="Soul Shard"></p>

# Warlock QoL

Quality-of-life helpers for Warlocks on **World of Warcraft: Forever**.

- **Summon Announce**: tells your party or raid who you are summoning when you start Ritual of Summoning.
- **Soul Shards**: a shard counter with a cap, removal of shards above the cap, and a Create Healthstone button.
- **Demon Bar**: a button that opens a row of the demons you can summon, shown whenever you have no pet out.

Every button only does something when you click it. The addon never casts spells or makes combat decisions for you.

Version 2.4.0, interface 16001 (Forever). Settings are saved per character.

---

## Contents

- [Install](#install)
- [Who sees what](#who-sees-what)
- [Summon Announce](#summon-announce)
- [Soul Shards](#soul-shards)
  - [Shard counter](#shard-counter)
  - [Cap and shard removal](#cap-and-shard-removal)
  - [Create Healthstone button](#create-healthstone-button)
  - [Delete extra button](#delete-extra-button)
- [Demon Bar](#demon-bar)
- [Commands](#commands)
- [Combat rules](#combat-rules)
- [Troubleshooting](#troubleshooting)
- [Spell and item IDs used](#spell-and-item-ids-used)
- [Saved settings](#saved-settings)
- [Files](#files)
- [Known limitations](#known-limitations)

---

## Install

1. Copy the `WarlockQoL` folder into your Forever AddOns folder:
   - Live: `World of Warcraft\_forever_\Interface\AddOns\WarlockQoL\`
   - Beta: `World of Warcraft\_classic_beta_\Interface\AddOns\WarlockQoL\`
2. **Fully restart the game.** `/reload` doesn't detect a new addon folder or new files.
3. On the character screen, open **AddOns** and make sure **Warlock QoL** is ticked.
4. In the game, run `/wqol probe` once. It checks that the game functions the addon needs exist on your build.

Later updates that only change existing files need just `/reload`. If a file is added, moved or renamed, restart the game.

> This addon replaces the older **Warlock Soul Shard Cap** (`Warlock_SS_Cap`) addon. Remove that folder if it is still installed. Otherwise both will run.

---

## Who sees what

| Feature | Shown when |
|---|---|
| Everything | Your character is a **Warlock**. Other classes get nothing; no frames are created. |
| Summon Announce | Always active for Warlocks (unless turned off). |
| Soul Shards (counter, healthstone, delete) | You know **Drain Soul**. Until then nothing appears. Once you learn it, the counter appears right away, without `/reload`. |
| Demon Bar | You know **at least one summon spell**, have **no pet** out, and are **alive**, **not mounted** and **not on a flight path**. |

---

## Summon Announce

When you start casting **Ritual of Summoning**, the addon posts one chat message saying whom you are summoning.

- **In a raid**, it posts in raid chat.
- **In a party**, it posts in party chat.
- **In an instance-only group** (dungeon-finder style, with no normal group), it posts in instance chat.
- **Not in a group**, it only prints the message to you.

Default messages:
- With a target: `Summoning {target} - please click the portal!`, where `{target}` becomes your target's name.
- Without a target: `Summoning - please click the portal!`

The message goes out once per cast. Repeats within 3 seconds are ignored, because the game can report the start of a channelled cast twice.

| Command | What it does |
|---|---|
| `/wqol summon msg <text>` | Set the message. Use `{target}` for the name. With no text, shows the current message. |
| `/wqol summon notarget <text>` | Set the message used with no target. |
| `/wqol summon test` | Show the message and the chat channel it would use, without sending. |
| `/wqol summon debug` | Toggle printing the spell ID of every cast you start (to check the Ritual of Summoning ID). |
| `/wqol summon on` / `off` | Turn the feature on or off. Applies right away. |

---

## Soul Shards

### Shard counter

A small box with the Soul Shard icon showing `count / cap`.

- **White**: below the cap.
- **Yellow**: close to the cap (within the "near" offset, 2 by default).
- **Red**: at or above the cap. When you first reach the cap, you get an on-screen warning and a sound. It won't warn again until you drop below the cap and climb back up.

Mouse actions:
- **Drag** to move it, unless locked, and not in combat.
- **Double-click** to open a small **Max Soul Shards** box. Type a number and press **Enter** or click **Set**; **Escape** or **X** closes it. Only digits are accepted, up to 3, and the value must be at least 1.
- **Hover** for a tooltip with the count and hints.

**How shards are read.** At login the addon checks whether shards are a resource bar (as in modern WoW) or bag items (as in the original game).
- **Bag items:** it counts Soul Shard items in your bags.
- **Resource bar:** it shows the bar's own maximum, and nothing is ever deleted.

If it guesses wrong, set the mode with `/sscap mode item` or `/sscap mode power`, then `/reload`.

### Cap and shard removal

When you hold **more shards than your cap**, the addon removes the extras:

1. **No healthstone, and you know Create Healthstone:** the extra shard is **kept**, and the [Create Healthstone button](#create-healthstone-button) appears, so you can turn it into a healthstone instead.
2. **Otherwise:** the extra shards are **deleted** automatically, one at a time, until you are back at the cap.

Automatic deletion runs when:
- your bags change: looting, Drain Soul, trading, moving items
- you log in or zone
- combat ends (it never deletes in combat)
- you change the cap

Safeguards:
- It never deletes in combat. Work waits until combat ends.
- It never acts while your cursor is holding an item. It just tries again on the next bag change.
- Before deleting, it checks that what's on the cursor is a Soul Shard. If not, it puts it back and deletes nothing.
- If a delete doesn't lower your count, it pauses for 30 seconds and tells you.
- If shards stack on this client, it splits off only the extra ones.

**If the game blocks automatic deletion.** Forever, like other modern WoW clients, can block addon actions that don't come from a click or key press. If that happens:
- auto-delete turns itself off **for that game build** and the addon remembers it, so it doesn't trigger the block again.
- the [Delete extra button](#delete-extra-button) appears instead.
- after a game patch, the addon tries auto-delete again by itself.

On build 1.60.1.70862 the game **did** block automatic deletion, so on that build extras are removed with the Delete extra button or `/sscap delete`.

### Create Healthstone button

A green button under the counter that casts your **highest known rank** of Create Healthstone when you click it.

It shows when all of these are true:
- you have **no healthstone** in your bags,
- you **know** Create Healthstone,
- you have **at least one** Soul Shard (any count, not only above the cap),
- you are **alive**,
- the counter is not hidden.

The button is exactly as wide as the counter. Hover it for the spell tooltip.

### Delete extra button

A button under the counter labelled **Delete extra (N)**. **Each click deletes one** extra shard. It shows when all of these are true:
- you hold more shards than the cap,
- there is no healthstone to make (otherwise the Create Healthstone button shows instead),
- auto-delete is **off**, or the game **blocked** it,
- you are alive (also hidden as a ghost).

---

## Demon Bar

A square button with the **Fel Domination** icon.

- **Left-click** opens or closes a row with each demon you can summon. Click a demon to summon it.
- **Right-click** casts **Fel Domination**, if you know it, so the next summon is fast.
- **Drag** moves the bar, but only while you don't know Drain Soul (see Position below), and never in combat.

**Demons shown** (only the ones you know):

| Demon | Extra requirement |
|---|---|
| Imp | — |
| Voidwalker | — |
| Succubus | — |
| Felhunter | — |
| Felguard | Only if the spell exists on Forever and you know it |
| Infernal (Inferno) | An **Infernal Stone** in your bags |
| Doomguard (Ritual of Doom) | A **Demonic Figurine** in your bags |

The list updates when you learn a new summon and when reagents enter or leave your bags.

**When the bar is visible.** It shows when you have no pet and hides when:
- you have a pet out,
- you are dead,
- you are mounted,
- you are on a flight path,
- you know no summons, or the bar is turned off.

The pet, death and mount checks are run by the game, so they work in combat too (for example, the bar appears the moment your pet dies). The flight-path check is done by the addon at takeoff and landing.

**Opening and closing the row only works out of combat.** The addon remembers whether you left it open, so if you keep it open, the demon buttons are ready the moment your pet dies mid-fight.

**Position:**
- **Before you know Drain Soul:** the bar stands alone. Its default spot is slightly below the center of the screen. You can drag it, and the position is saved.
- **After you learn Drain Soul:** the bar sits under the shard counter and follows it. It can't be dragged; move the counter instead.
  - When the Create Healthstone or Delete extra button is showing, the bar sits below that button.
  - When neither is showing, the bar sits directly under the counter.

| Command | What it does |
|---|---|
| `/wqol pets on` / `off` | Turn the demon bar on or off. Applies right away. |
| `/wqol pets reset` | Move the bar back to its default spot (only matters before Drain Soul). |
| `/sscap pets` | Shortcut that toggles the demon bar on or off. |

---

## Commands

### General

| Command | What it does |
|---|---|
| `/wqol` | List all features and their commands. |
| `/wqol probe` | Check which game functions exist on this build, for every feature. Run this after each game patch. |
| `/wqol <feature> on` / `off` | Turn a feature on or off: `summon`, `shards`, `pets`. `shards` needs `/reload` to apply. |

### Soul Shards

`/sscap <command>` and `/wqol shards <command>` do the same thing.

| Command | What it does |
|---|---|
| `/sscap` | List these commands. |
| `/sscap <number>` | Set the cap (for example `/sscap 10`). Extras are removed right away (out of combat). |
| `/sscap auto` | Toggle automatic deletion. |
| `/sscap delete` | Delete one extra shard now (out of combat). |
| `/sscap near <number>` | How many shards before the cap the counter turns yellow. |
| `/sscap lock` / `unlock` | Lock or unlock the counter's position. |
| `/sscap show` / `hide` | Show or hide the counter (the healthstone and delete buttons hide with it). |
| `/sscap sound` | Toggle the at-cap warning sound. |
| `/sscap reset` | Move the counter back to its default position. |
| `/sscap status` | Explain why shards are or are not being removed (see [Troubleshooting](#troubleshooting)). |
| `/sscap mode auto` / `item` / `power` | Force how shards are read. Then `/reload`. |
| `/sscap item <id>` | Use a different Soul Shard item ID. Then `/reload`. |
| `/sscap probe` | The Soul Shard part of `/wqol probe`. |
| `/sscap pets` | Toggle the demon bar. |

Before you know Drain Soul, `/sscap` commands only reply "Soul Shards starts once you learn Drain Soul." (`/sscap probe` still works.)

---

## Combat rules

The game protects buttons that cast spells. Addons may only create, show, hide, move or change those **out of combat**. This addon follows that rule rather than working around it.

| Thing | In combat |
|---|---|
| Clicking Create Healthstone, a demon, or Fel Domination | Works |
| Demon bar appearing/hiding for pet, death and mount | Works (the game handles it) |
| Healthstone button appearing/hiding | Waits until combat ends |
| Opening/closing the demon row | Not allowed. A message tells you. Leave it open if you want it ready in combat. |
| Dragging the counter or the demon bar | Not allowed |
| `/sscap show`, `hide`, `reset` | Wait until combat ends |
| Deleting shards | Waits until combat ends |
| Demon bar moving up or down under the counter | Waits until combat ends |
| Delete extra button | Can hide immediately (it is a normal button) |
| Summon announce chat message | Sent, but the game may block addon chat in combat or during boss fights |

---

## Troubleshooting

**Nothing appears at all.**
- Check that the character is a Warlock and that **Warlock QoL** is ticked in the AddOns list.
- The shard counter needs **Drain Soul**. The demon bar needs at least one summon and no pet out.
- Run `/wqol probe`. The `Shards: Drain Soul known` and `Pets: shown demons` lines show what the addon sees.

**Shards above the cap are not being removed.** Run `/sscap status` and read it line by line:
- `mode power` means shards are being read as a resource bar, so nothing is deleted. If your shards are bag items, run `/sscap mode item`, then `/reload`.
- `count 0` while you hold shards means the Soul Shard item ID is different on this client. The bag scan at the end lists items with "shard" in the name, with their IDs. Use `/sscap item <id>`, then `/reload`.
- `blocked by client yes` means the game blocked automatic deletion on this build. Use the Delete extra button or `/sscap delete`.
- `extra shards kept for the Create Healthstone button` means it is waiting for you to make a healthstone.
- `backoff 30s` means a delete didn't work and it is pausing. Try `/sscap delete`.
- `in combat yes` means it will act when combat ends.

**A button appears but clicking it does nothing, or casts twice.** The game's "cast on key down" setting may behave differently on this client. Report which happens.

**A demon or the healthstone isn't detected.** Forever may use different spell or item IDs from the original game. Run `/wqol probe` and compare with the [ID list](#spell-and-item-ids-used).

**The summon message shows a literal `%t`.** The client hid your target's name from the addon, and the `%t` stand-in wasn't replaced on this build.

**Settings are lost between sessions.** The Forever beta was reported to lose saved data until build 1.60.1.70009. If it happens on a later build, the client may still be at fault.

**"Interface action failed because of an AddOn."** That counter only clears on a full game restart, not `/reload`. The addon avoids triggering it again (see [Cap and shard removal](#cap-and-shard-removal)), but one block can already have been counted.

---

## Spell and item IDs used

These are the original game's IDs. Forever may differ; `/wqol probe` shows what the addon finds.

| What | IDs |
|---|---|
| Ritual of Summoning | 698 |
| Drain Soul (ranks 1–4) | 1120, 8288, 8289, 11675 |
| Soul Shard (item) | 6265 (change with `/sscap item <id>`) |
| Create Healthstone (ranks) | 6201, 6202, 5699, 11729, 11730 |
| Healthstones (items, incl. Improved Healthstone variants) | 5512, 19004, 19005, 5511, 19006, 19007, 5509, 19008, 19009, 5510, 19010, 19011, 9421, 19012, 19013. English clients also match items named "Healthstone". |
| Summon Imp / Voidwalker / Succubus / Felhunter / Felguard | 688 / 697 / 712 / 691 / 30146 |
| Inferno (reagent Infernal Stone) | 1122 (item 5565) |
| Ritual of Doom (reagent Demonic Figurine) | 18540 (item 16583) |
| Fel Domination | 18708 |

---

## Saved settings

Settings are stored **per character** in:

```
World of Warcraft\_forever_\WTF\Account\<account>\<realm>\<character>\SavedVariables\WarlockQoL.lua
```

Structure (`WarlockQoLDB.modules`):

| Section | Keys |
|---|---|
| `summon` | `enabled`, `message`, `messageNoTarget`, `debug` |
| `shards` | `enabled`, `cap` (default 20), `nearOffset` (2), `autoDelete`, `sound`, `locked`, `hidden`, `point` (counter position), `shardItemID`, `forceMode`, `blockedOnBuild` (build that blocked auto-delete) |
| `pets` | `enabled`, `expanded` (row open), `point` (position while standalone), `migrated` |

Only edit this file while the game is **fully closed**. The game rewrites it when you log out.

---

## Files

```
WarlockQoL\
  WarlockQoL.toc             addon manifest (interface 16001, load order)
  Core.lua                   shared code: settings, single event frame, feature registry,
                             combat queue, secret-value guards, /wqol and /wqol probe
  Modules\
    SummonAnnounce.lua       Summon Announce
    Pets.lua                 Demon Bar
    Shards\
      UI.lua                 shard counter, cap editor, healthstone and delete buttons
      Trim.lua               shard removal, healthstone checks, /sscap status
      Shards.lua             Soul Shards feature: reading shards, alerts, /sscap
  README.md                  this file (the game ignores it)
```

To add a feature, create a file in `Modules\` that calls `ns.RegisterModule`, and add it to `WarlockQoL.toc`.

---

## Known limitations

- **Not fully tested on Forever.** Several behaviours depend on how Forever's client handles addons and should be checked on each build with `/wqol probe`.
- **Automatic shard deletion is blocked** on build 1.60.1.70862. Extras need a click (Delete extra) or `/sscap delete`.
- **Released ghosts:** the game's "dead" check may not count a ghost, so the demon bar or healthstone button could reappear after you release. (The Delete extra button does hide for ghosts.)
- **Flight paths** are detected at takeoff and landing, not continuously. Landing into combat delays the bar until combat ends.
- **Combat:** buttons can't appear, disappear, move or change during combat (see [Combat rules](#combat-rules)).
- **Hidden values:** the game can hide some values from addons, such as names, counts and states. When that happens, the addon skips the action or shows `?` instead of guessing.
- **The summon message** may be blocked by the game in combat or during boss fights.
- **No damage meter, combat log tools, or replacement of Blizzard frames.** Forever blocks combat log access for addons, and Blizzard ships its own damage meter and cooldown manager.

## License

MIT. See [LICENSE](LICENSE).
