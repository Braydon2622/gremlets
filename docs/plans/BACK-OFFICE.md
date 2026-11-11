# The Back Office: your AI crew and live feeds as one tiny pixel office

Braydon's idea: everything his AI agents and accounts are doing, shown as one living pixel building on the Mac
(and mirrored to the iPad Terrarium and iPhone). Each source is a room with Gremlet workers; real events become
small animations he can read at a glance. It must feel like ONE place with one visual language, not a pile of
widgets: same building, same workers, same event cards, same alert rules.

## Rooms (start with these; each is optional and switched on in Settings)
- **Workshop: Claude Code.** Already tracked by ClaudeBuddy. Thinking = workers at desks, waiting = a worker holds
  up the lantern at the door, done = a flag on the roof.
- **Amazon Railroad: the Azoki Market store.** Every sale = a train car rolls in carrying that product's pixel
  icon; a return = a car rolls back out; the day's sales stack up as cargo on the platform with the total on a
  sign. A listing problem = a stopped train with a red signal.
- **Crypto Aquarium: the trading bots.** Each bot or open position = a fish. Size = position size, color = profit
  or loss today, a sleepy fish = bot paused, murky water = the bot reported an error. Strictly read-only: the
  Back Office NEVER places, changes or cancels a trade.
- **Discord Post Office.** Mentions and messages in Braydon's own servers arrive as letters carried by a pigeon;
  the mailbox flag goes up; hovering shows the sender and first line only. Use a bot Braydon creates and adds to
  his own servers (or channel webhooks). Never use a personal user token (against Discord's rules). Never posts.
- **Factory: n8n.** Each workflow run = a crate on a conveyor; success = a green stamp, failure = a puff of smoke
  and the lantern goes up.

Before building the railroad or aquarium, ask Braydon where his existing Amazon and trading bot projects live
on this Mac (he may already have railroad or aquarium pieces). Connect to those instead of rebuilding them.

## Architecture
- One event shape in GremletsCore:
  `OfficeEvent { source, kind, title, detail?, amount?, severity (info | good | warn | urgent), link?, at }`.
- The universal door: a tiny HTTP listener on 127.0.0.1 only (for example `POST http://127.0.0.1:7777/event`
  with that JSON and a local secret header). Any script, bot or n8n workflow can report events with one request.
  This is the main integration; most rooms should need nothing more than their existing scripts adding one POST.
- Pull adapters only where a push isn't possible (for example polling an API every few minutes), each in its own
  small file behind a common `OfficeSource` protocol.
- Settings window: switch rooms on or off, test each one with a fake event, and enter any keys. Keys go in the
  macOS Keychain, typed by Braydon himself; never in files or the repo.
- Event log kept 7 days on disk; message text (Discord) is kept no longer than 24 hours.

## How Braydon hears about things
- info: a small animation only. good: animation + a sparkle on the room. warn: the room's lantern lights.
  urgent: a Gremlet walks to the edge of the screen holding a sign, plus an optional macOS notification.
- Mirrors to the iPad Terrarium (see TERRARIUM.md) and the iPhone using the same encrypted `status` notes.
- A daily report card at 6pm: one pixel card with "Today in the Back Office" (sales, bot P&L, messages, Claude
  tasks finished), saved like the session recap cards.

## Build order
1. Event model, the 127.0.0.1 listener, the Settings window, and the building with only the Workshop room.
2. Amazon Railroad. 3. Crypto Aquarium. 4. Discord Post Office. 5. Factory.
6. Mirroring to iPad and iPhone. 7. The daily report card.
Each step: tests for the event handling, a demo mode with fake events (`--office-demo`) so it can be filmed
without real data, and a STATUS.md update.

## Rules for this work
- Read-only everywhere: never trade, buy, sell, post, reply or change settings on any account.
- Commit locally in small commits. Do NOT push to GitHub or open pull requests, and never batch automated
  commits to any online account.
- Ask Braydon before creating any account, bot or API key, or anything that costs money.
- Keep CPU low (under 3% with all rooms idle) and run all existing tests before calling a step done.
