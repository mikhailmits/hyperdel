Hyperdel - deliver your thoughts anywhere.

Things to build in one day:
- delivery to telegram saved notes and channels from nvim
- learn knowledge about nvim and lua a bit
- architect the solution

Ideally we have some thoughts in our head, we open our favourite rex,
start writing in any folder, just in nvim, when finished just write some
command/press binding and done.

open questions:
- plugin compatibility with older nvim
- how to design the command
- should the text be eraised from editor after delivery?
-- I think we can configure it, we even may interact with rex api, if the terminal is rex to kill the tab
with cool animations or just erase text.
- how to deliver it to github as a real plugin

decisions:
- this plugin is independent from the rest of the repo.
- we'll use lua module version of tdlib 
- make the plugin manager install tdlib deps on installation
- build lua client for tdlib_json

This file may not be touched by AI agents.

notes from tdlib docs:
- we can use tdlib_json from any programming language that may execute C functions.

architecture concept:
tdlib <- tdlib lua client <- nvim utils <- plugin functions <- plugin setup 
