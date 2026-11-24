# Visible Horizon observation refresh

Owner selection24November: this is a native read-runtime repair, not a new Core wire or permission. Actual HA356 ready responses were observed with only6seconds remaining, while the native visible panel slept30seconds after every read. The original cursor correctly expired, but no subsequent actual read was attempted for roughly24seconds.

While the same panel remains visible, foreground and under the same owner/Session/source scope, dispatch at most one pure read at a time. The next delay is `min(8, max(1, originalRemaining - 1))` seconds; no renderer/timer/old DTO may renew the original cursor. A genuinely newer admitted Core revision may supply its own original deadline. Unknown/empty lifetime uses8seconds. A currently cancelling older read must finish before a successor dispatches.

Explicit denial/withdrawal or permanent authentication/protocol failure stops automatic reads in that original owner/material scope. A genuinely fresh owned context, explicit permitted user retry or newer authorized Core observation must qualify again. Ordinary transient connectivity failure may keep only still-valid original content. Expired content is never shown. Source/owner/epoch changes cancel and fence pending work. No provider/model/action operation is dispatched by this refresh loop.

The model owns the actual read task. Same-context callers coalesce; a changed context cancels and waits for the obsolete HTTP chain before starting its successor. Panel disappearance cancels that task without renewing or withdrawing the original still-bounded cursor. Existing held-response/replacement tests must continue to prove that a late obsolete reply cannot undo a newer owned result.
