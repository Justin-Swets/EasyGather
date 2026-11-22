# EasyGather

A small, lightweight Mining and Herbalism helper. It shows you what a node needs and what it's worth, remembers where you found it, and tracks what your gathering is earning.

## Features

**Skill and price on node tooltips**
- Hover any ore vein or herb in the world to see the required skill and the current AH price for one item.
- The skill is colored by your own skill level: red (can't gather yet), orange, yellow, green, grey (no more skill-ups).

**Saved nodes on your maps**
- Every node you gather is saved: where it was, how many times you've gathered it, and when.
- **Minimap:** a tiny red dot marks each saved node. It's small enough to sit inside the game's own node icon, so you can still see whether the node is up. Hover the dot for skill, price and history.
- **World map:** item icons mark your saved nodes. Use the **My gathered nodes** checkbox on the map to show or hide them.
- Nodes you tried to gather without enough skill are saved too and marked with a red X on the world map.

**Scarce drops**
- Tracks how often each node type gives something rare besides its main item: gems, Elemental Earth, Black Vitriol, Swiftthistle, Wildvine and so on. Common stones aren't counted.
- Shown as a percentage in node tooltips, e.g. `Scarce drops: 12% (3 of 25)`, with your most common finds listed.

**Gold per hour bar**
- A slim bar at the top of the screen showing **Gold/hr**, **Gathered** (ore and herbs at AH price), **Scarce** rate, **Vendor** (grey and white mob drops at vendor price), **Coin** looted, and session **Time**.
- Hover the Scarce section for your top 5 node types by scarce rate.
- Only counts time you're logged in. The session carries over `/reload` and logouts until you reset it.
- If you use **AHledger**, the bar attaches right below AHledger's bar and moves with it.

**AH prices**
- Uses **Auctionator** prices when Auctionator is installed.
- Otherwise click **Scan Ore/Herbs** at the top of the Auction House (or type `/eg scan`) to scan prices for every ore and herb.

## Commands

| Command | What it does |
|---|---|
| `/eg` | List all commands |
| `/eg scan` | Scan AH prices for ore and herbs (Auction House must be open) |
| `/eg list` | List the nodes saved in your current zone |
| `/eg minimap` | Show or hide minimap pins |
| `/eg map` | Show or hide world map pins |
| `/eg gph` | Show or hide the gold per hour bar |
| `/eg reset` | Start a new gold per hour session |
| `/eg button` | Show or hide the minimap button |
| `/eg clear` / `/eg clear all` | Delete saved nodes for this zone / everywhere |

**Minimap button:** left-click toggles pins, right-click shows or hides the gold per hour bar, shift-right-click lists this zone's nodes. Drag it to move it.

## Good to know

- The game blocks addons from reading the names of its own minimap node icons. So EasyGather can't add skill or price to the game's minimap tooltip. It shows them on the world node tooltip and on its own pins instead.
- A node needs to be gathered (or attempted) once before it gets a pin.
- Optional: **Auctionator** (prices), **AHledger** (bar placement).
