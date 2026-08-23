# Phase 5 runtime settings verification

The five advanced appearance controls previously detected as write-only now have production runtime consumers:

- `text_size_pick`
- `ModChatBubbleText`
- `ModChatBubbleTextLeft`
- `date_right_color`
- `date_left_color`

The Phase 5 CI must independently rerun the settings-consumer audit, feature tests, analyzer, and release build from this source head.
