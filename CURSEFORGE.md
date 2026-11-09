# Warlock QoL

**Less bag clutter, faster healthstones, quicker demon summons, made for Warlocks on World of Warcraft: Forever.**

Warlock QoL takes care of the small, repetitive chores of playing a Warlock so you can focus on the fun parts. It keeps your Soul Shards under control, puts your most-used Warlock spells one click away, and lets your group know who you're summoning.

Every button only does something when **you** click it. The addon never casts spells or plays the game for you.

---

## What it does

### Soul Shard counter
A small box on your screen shows how many Soul Shards you have and the most you want to carry, for example **12 / 20**.

- It turns **yellow** when you're getting close to your limit and **red** when you reach it, with a sound and an on-screen alert.
- **Double-click** the box to change your limit.
- **Drag** it anywhere you like.

### No more full bags of shards
When you go over your limit, the addon gets rid of the extra shards so they stop filling your bags. If the game doesn't let addons do this on their own, a **Delete extra** button appears instead. Each click removes one extra shard.

If you don't have a healthstone yet, the addon **keeps** the extra shard so you can turn it into one instead of wasting it.

### One-click Healthstone
When you don't have a healthstone, a green **Create Healthstone** button appears under the counter. Click it to make the best healthstone you know. It disappears once you have one.

### Demon Bar
Whenever your pet is gone (it died, or you just logged in), a button appears. Click it to open a row of every demon you can summon, then pick the one you want.

- **Right-click** the button to use **Fel Domination** first for a faster summon.
- **Infernal** and **Doomguard** show up only when you have the items needed to summon them.
- The bar hides itself while you have a pet out, are mounted, flying or dead.
- Leave the row open, and your demons are ready the moment your pet dies, even mid-fight.

### Summon Announce
When you start **Ritual of Summoning**, the addon posts a message in your party or raid chat, such as:

> Summoning Bob - please click the portal!

You can write your own message.

---

## Getting started

1. Install the addon and **fully restart the game**. `/reload` alone won't pick up a newly installed addon.
2. Log in to your Warlock. Everything appears on its own as you learn the matching spells:
   - The shard counter appears once you learn **Drain Soul**.
   - The Demon Bar appears once you can summon a demon.
3. Other classes see nothing, so it's safe to leave the addon turned on for all your characters.

Your settings are saved separately for each character.

---

## Handy commands

You don't need any commands to use the addon, but these are available if you want them:

| Type this | To do this |
|---|---|
| `/sscap 10` | Set your shard limit to 10 (use any number) |
| `/sscap lock` / `/sscap unlock` | Stop or allow moving the shard counter |
| `/sscap hide` / `/sscap show` | Hide or show the shard counter |
| `/sscap sound` | Turn the "limit reached" sound on or off |
| `/wqol summon msg Summoning {target}, click the portal!` | Change your summon message (`{target}` becomes the player's name) |
| `/wqol pets off` / `/wqol pets on` | Turn the Demon Bar off or on |
| `/wqol` | See everything the addon can do |

---

## Good to know

- **In combat**, the game doesn't let addons make buttons appear, disappear or move. Buttons you can already see still work, and anything else catches up as soon as the fight ends.
- **Shards are never deleted during combat.**
- Forever is still new, so some features may behave differently after a game update. If something seems off, type `/wqol probe` and include what it says when you report the problem.

---

*Free and open source under the MIT License.*
