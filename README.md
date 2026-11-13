# Black Book

A World of Warcraft: Forever addon that remembers the players who kill you in open-world PvP, and the players who helped.

## Features

- Records the player who landed the killing blow each time you die in the open world.
- Records assists: every other player who damaged you just before you died.
- A movable window listing each player's name (in class colour), kills, assists, and how long ago you last ran into them. Click a column header to sort by it.
- A tooltip for each player, showing race and class, first and last encounters, the zone, and the last killing-blow spell.
- An optional chat message whenever players kill you.

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
| `/blackbook announce` | Turn the chat message on or off |
| `/blackbook last` | Show how your most recent death was read |
| `/blackbook reset` | Erase all entries |

You can also open the window from the addon button by the minimap. Right-click a player in the list to remove them.

## How it works

Addons can't read the combat log on Forever, so Black Book reads Blizzard's Death Recap after each death. The first entry is the killing blow, and any other players in the recap are counted as assists.

Because of this:

- Assists only cover the last few hits the Death Recap keeps, not the whole fight.
- Damage from pets, totems and guardians can't be credited to the player who owns them.

Data is saved separately for each character, in `WTF\Account\<ACCOUNT>\<Realm>\<Character>\SavedVariables\BlackBook.lua`.

## Requirements

World of Warcraft: Forever (interface 16001).
