# Moving chats between Projects

Hermes Android 2.1.29 adds Move to project to the Chats row action menu. Use it to file an unassigned conversation or move a chat from one Project to another.

## From Chats

1. Open Chats and find the conversation. You can use All, Recent, Unassigned or Archived.
2. Open the row's three-dot menu and choose **Move to project**.
3. Choose the destination Project. Dismiss the picker to cancel without changing the chat.

The destination must be an active Project with a server folder. Add a folder in Projects before selecting a folderless Project. The move uses the chat's stored identity; it keeps the title, conversation history and pins.

After a move, the row shows the destination Project and disappears from Unassigned. Reopen Projects to refresh their chat counts. Moving a Quick Chat into a Project clears its device-local quick retention schedule after Hermes accepts the move.

## From a Project

Open the Project, then use the move control on its conversation row to choose another Project. This uses the same server-side working-folder move.

## Server requirements and errors

Projects need a Desktop Gateway connection with dashboard authentication and support for `session.workspace.move`. A REST-only connection cannot manage server Projects through this menu.

Hermes derives Project placement from the chat's working folder. A move changes that folder for future work in the conversation. This differs from the classic list's device-local Spaces, which do not change server Project placement.

If the move fails, the app keeps the old placement and offers a retry. Stock Hermes does not support moving a chat back to Unassigned with this operation; the app must not report that unsupported action as a successful move.
