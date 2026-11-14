# Black Book

A World of Warcraft: Forever addon that remembers the players who kill you in open-world PvP, the players who helped, and the players you kill.

## Features

- Records the player who landed the killing blow each time you die in the open world.
- Records assists: every other player who damaged you just before you died.
- Records the players you kill, including kills by your pet.
- Keeps your kill/death record against every player, for example 2 kills and 5 deaths.
- Tracks your kill streak (player kills in a row without dying) and your best streak, and prints the streak in chat after each kill.
- A movable window with two tabs:
  - **Deaths:** the players who killed you or assisted, with how often, your record against them, and when you last ran into them.
  - **Kills:** the players you've killed, with how often, your record against them, and when you last killed them. The footer shows your current and best streak.
- Click a column header to sort by it. Records are green when you're ahead and red when you're behind.
- A tooltip for each player, showing level, race and class, your record, first and last encounters, the zone, and the last killing-blow spell on you.
- Optional chat messages for your kills and deaths.
- A warning on screen, with a sound and your record against them, when a player who has killed you or assisted on your death comes into range.

Kills and deaths inside battlegrounds, arenas, dungeons and raids aren't recorded, but any death ends your kill streak.

## Installation

1. Download or clone this repository.
2. Copy the `BlackBook` folder into your Forever AddOns folder, for example:
   `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\BlackBook`
3. Restart the game and make sure Black Book is enabled in the AddOns list on the character select screen.

## Usage

| Command | What it does |
| --- | --- |
| `/blackbook` or `/bbook` | Show or hide the window |
| `/blackbook help` | List all commands in chat |
| `/blackbook announce` | Turn the chat messages for your kills and deaths on or off |
| `/blackbook streak` | Show your current and best kill streak |
| `/blackbook alerts` | Turn the nearby-player warning on or off |
| `/blackbook sound` | Turn the warning sound on or off |
| `/blackbook test` | Show a sample warning |
| `/blackbook minimap` | Show or hide the minimap button |
| `/blackbook last` | Show how your most recent death was read |
| `/blackbook reset` | Erase all entries and streaks |

You can also open the window with Black Book's own minimap button, which you can drag around the minimap's edge, or from the addon button by the minimap. Right-click a player in the list to remove them.

## How it works

Addons can't read the combat log on Forever, so Black Book reads Blizzard's Death Recap after each death. The first entry is the killing blow, and any other players in the recap are counted as assists.

Because of this:

- Assists only cover the last few hits the Death Recap keeps, not the whole fight.
- Damage from pets, totems and guardians can't be credited to the player who owns them.

Your own kills come from the game's `PARTY_KILL` event, which reports who landed each killing blow. Only killing blows by you or your pet count, not kills by your group.

Nearby players are detected when their nameplate appears, or when you target or mouse over them. Enemy nameplates need to be turned on for the warning to reach the full nameplate range. Each player triggers the warning at most once a minute.

Data is saved separately for each character, in `WTF\Account\<ACCOUNT>\<Realm>\<Character>\SavedVariables\BlackBook.lua`.

## Requirements

World of Warcraft: Forever (interface 16001).
