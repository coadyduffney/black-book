# Black Book

A World of Warcraft: Forever addon that remembers the players who kill you in open-world PvP, and the players who helped.

## Features

- Records the player who landed the killing blow each time you die in the open world.
- Records assists: every other player who damaged you just before you died.
- A movable window listing each player's name (in class colour), kills, assists, and how long ago you last ran into them. Click a column header to sort by it.
- A tooltip for each player, showing level, race and class, first and last encounters, the zone, and the last killing-blow spell.
- An optional chat message whenever players kill you.
- A warning on screen, with a sound, when a player in your Black Book comes into range.

Deaths inside battlegrounds, arenas, dungeons and raids are ignored.

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
| `/blackbook announce` | Turn the chat message on or off |
| `/blackbook alerts` | Turn the nearby-player warning on or off |
| `/blackbook sound` | Turn the warning sound on or off |
| `/blackbook test` | Show a sample warning |
| `/blackbook minimap` | Show or hide the minimap button |
| `/blackbook last` | Show how your most recent death was read |
| `/blackbook reset` | Erase all entries |

You can also open the window with Black Book's own minimap button, which you can drag around the minimap's edge, or from the addon button by the minimap. Right-click a player in the list to remove them.

## How it works

Addons can't read the combat log on Forever, so Black Book reads Blizzard's Death Recap after each death. The first entry is the killing blow, and any other players in the recap are counted as assists.

Because of this:

- Assists only cover the last few hits the Death Recap keeps, not the whole fight.
- Damage from pets, totems and guardians can't be credited to the player who owns them.

Nearby players are detected when their nameplate appears, or when you target or mouse over them. Enemy nameplates need to be turned on for the warning to reach the full nameplate range. Each player triggers the warning at most once a minute.

Data is saved separately for each character, in `WTF\Account\<ACCOUNT>\<Realm>\<Character>\SavedVariables\BlackBook.lua`.

## Requirements

World of Warcraft: Forever (interface 16001).
