# Music Canvas native consumer v1

Owner: [Apple lane](https://github.com/djconnect-music-dj/djconnect-app/issues/87#issuecomment-6894927223).
Product and wire authority remain Core's `docs/product/MUSIC_CANVAS_V1.md` and
`docs/technical/MUSIC_CANVAS_V1_CONTRACT.md`. No second specification.

The existing active Session toolbar/menu opens one compact Music Canvas panel.
The existing popover dismissal queue prevents simultaneous popover/sheet actions
on iPhone; iPad and Mac use their existing toolbar presentation.

| Building block | Decision |
| --- | --- |
| Native layout/navigation | ADAPT SessionTimelineScreen, shared SwiftUI Form and native sheets |
| Paired identity/transport | REUSE DJConnectClient and existing HTTP/Hybrid authority |
| Capability | NEW additive music_canvas=true, version1; unsupported producers do not receive Canvas reads |
| Preferences | RENDER confirmed Core revision only; no defaults or local persistence |
| Operations | REUSE no-replay effect path; recover the original operation receipt, then read current state |
| Preview | REUSE bounded, redirect-rejecting Session artwork transport and decoded immutable pixels |
| Hardware | RENDER Core registry descriptors; no scanning, device tokens, model/provider calls or manufacturer services |
| Legacy | No Canvas implementation existed; VibeScape and VibeCast are unchanged |

Profile/Session/endpoint/foreground changes withdraw snapshots and late replies.
The foreground panel refreshes state; it never schedules image generation,
retries mutations, invents screens, or claims display from cloud submission.
Unknown statuses show a waiting/unavailable state. Multi-select, three spatial
compositions, three matte choices and four cadences follow the owner copy in all
five languages. Per-screen cadence defaults to the shared preference.

Unknown dimensions/orientation are requested once during setup, with Core as
durable owner. A known field is never overwritten by a guessed model profile.
Management UI follows the actual Core management permission. Forget differs
from deselect, explains shared-profile impact and defaults remote cleanup off;
unsupported cleanup is not offered. Failed cleanup permits an explicit
"forget anyway, artwork may remain" decision.

Software fixtures, real HA producer/consumer contracts, actual image-provider
output, iPhone/iPad/Mac accessibility and Samsung/SwitchBot visible acceptance
remain separate. Source build is not installation or physical acceptance.
No new Watch surface, playback authority, image provider or Cast route.
