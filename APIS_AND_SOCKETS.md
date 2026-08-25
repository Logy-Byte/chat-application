# Chat Application Architecture and APIs

## Required APIs

A modern chat application typically requires two types of communication: **REST APIs** for standard CRUD operations (creating users, fetching history) and **WebSocket APIs** for real-time events (sending messages, typing indicators).

### 1. User Authentication & Profile (REST)
*   **POST** `/api/auth/register` - Create a new user account.
*   **POST** `/api/auth/login` - Authenticate a user and return a token (e.g., JWT).
*   **POST** `/api/auth/logout` - Invalidate the current session.
*   **GET** `/api/users/me` - Fetch the current user's profile information.
*   **PUT** `/api/users/me` - Update profile picture, status, or username.

### 2. Contacts / Friends (REST)
*   **GET** `/api/contacts` - Fetch the user's friend list.
*   **POST** `/api/contacts/request` - Send a friend request.
*   **PUT** `/api/contacts/request/:id` - Accept or reject a friend request.

### 3. Chat / Room Management (REST)
*   **GET** `/api/chats` - Get a list of all active chats/conversations for the user.
*   **POST** `/api/chats` - Create a new 1-on-1 chat or group chat.
*   **GET** `/api/chats/:chatId` - Get details about a specific chat (participants, etc.).
*   **PUT** `/api/chats/:chatId` - Update group name or icon.
*   **DELETE** `/api/chats/:chatId/leave` - Leave a group chat.

### 4. Messaging (REST - for history)
*   **GET** `/api/chats/:chatId/messages` - Fetch paginated message history for a chat.

### 5. Real-Time Events (WebSocket)
These are events emitted or listened to over a persistent socket connection:
*   `connection` - Establish the real-time link when the user opens the app.
*   `disconnect` - Handle when the user goes offline.
*   `send_message` (Client -> Server) - Send a new message to a chat.
*   `receive_message` (Server -> Client) - Receive a new message from another user.
*   `typing_start` / `typing_stop` - Indicate that a user is currently typing.
*   `message_read` - Update read receipts when a user sees a message.
*   `user_status` - Broadcast online/offline/away status updates.

---

## Free Options for Socket/Real-time Implementation

If you want to implement the real-time socket connections for free, you have two main paths: **Self-hosted** or **Managed Services (BaaS)** with generous free tiers.

### 1. Self-Hosted (100% Free, but requires deployment)
You write the socket server code yourself and host it on a free cloud provider.
*   **Socket.IO (Node.js)**: The industry standard for WebSockets. It provides fallbacks to HTTP long-polling if WebSockets fail, auto-reconnection, and easy room management.
*   **ws (Node.js)**: A lightweight, barebones WebSocket implementation if you want maximum performance without the overhead of Socket.IO.
*   **Hosting platforms**: You can host your Node.js Socket.IO server for free on platforms like **Render**, **Railway** (free trial/credits), or **Fly.io**.

### 2. Managed Services (Generous Free Tiers)
These services manage the infrastructure for you. You just use their SDKs on your frontend and backend.

*   **Firebase Realtime Database / Firestore**: 
    *   **Pros**: Extremely generous free tier. Handles offline persistence, authentication, and real-time syncing out of the box. You don't even need to write a backend socket server.
    *   **Cons**: Vendor lock-in; requires learning the Firebase way of doing things.
*   **Supabase**: 
    *   **Pros**: An open-source Firebase alternative based on PostgreSQL. It has built-in real-time subscriptions to database changes. Excellent free tier.
*   **Pusher Channels**: 
    *   **Pros**: Specifically built for real-time pub/sub messaging. Very easy to integrate into any stack.
    *   **Free Tier**: 200,000 messages per day and 100 concurrent connections.
*   **Ably**: 
    *   **Pros**: Highly reliable real-time messaging platform, similar to Pusher but often considered to have better edge infrastructure.
    *   **Free Tier**: 6 million messages per month and 200 concurrent connections.
