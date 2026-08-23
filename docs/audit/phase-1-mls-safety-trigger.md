# Phase 1 MLS safety patch trigger

This connector-authored commit triggers the branch-owned MLS safety workflow. The branch cannot satisfy Phase 1 until the workflow has applied both required source corrections:

- import `dart:async` for the serialized conversation gate;
- publish MLS membership commits to the server before merging local pending state, clearing the pending commit on server rejection.

After the bot-authored source patch lands, a separate connector-authored verification commit will trigger analyzer, tests, and Android release build from the corrected source head.
