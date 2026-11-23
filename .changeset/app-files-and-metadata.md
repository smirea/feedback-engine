---
'@stefan.inc/feedback-engine': minor
---

`setupFeedbackEngine({ files, metadata })`: `files` adds the app's own files, each made by its own `data` function when the capture is taken, to every export but the image: the Data export, Image + Data, ProcrastiMate (any size, uploaded in parts past 16 MB), and webhooks (one `file` part each). `metadata` adds `label: value` lines under the image's title, which are also the first `environment` entries after `App`. The Share menu now lists the destinations that have no button beside it first, then Image, Data (`feedback.json`, or a ZIP with the app's files) and Image + Data (always a ZIP), then New Webhook; pinned destinations no longer repeat in the menu. ZIPs deflate what shrinks. The environment no longer records the locale.
