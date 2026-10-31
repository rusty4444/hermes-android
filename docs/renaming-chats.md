# Renaming chats

Hermes Android 2.1.28 adds Rename to the current Chats browser and the open-chat menu. The classic chat list also offers Rename on REST-only connections.

## From Chats

1. Open the Chats tab and find the conversation.
2. Tap the row's three-dot action menu, then **Rename**.
3. Edit the name and tap **Rename**, or submit with the keyboard's Done action.

You can rename chats in the Recent, Unassigned and Archived filters too. The app keeps the conversation's messages, Project placement and pin state.

## From an open chat

Open the top-right three-dot menu and choose **Rename**. After the save, the chat header and exports use the new title. Returning to Chats refreshes the list.

The menu is unavailable during a streaming response. An unsaved new-chat draft needs a server session before Rename can run; send its first message first.

## Saving and errors

Names can contain up to 120 characters. The dialog trims surrounding spaces and blocks blank names. Cancel closes it without saving. Keeping the same name sends no rename request.

The app saves the title on your Hermes server, for both Remote Gateway and REST connections. Refresh another client to see the change. Rename does not change device-local pins or the server's pinned flag.

A failed save leaves the old title visible and shows the error. Check your connection and retry. If Hermes rejects a duplicate name, choose another. An older API server that lacks `PATCH /api/sessions/{session_id}` needs an update; Rename does not create a replacement chat or store a device-only alias.
