## Integrated Apple release source readback

Apple [#446](https://github.com/djconnect-music-dj/djconnect-app/pull/446) merged through the protected source path to `d5bd366df6893df451b36f58966911d83511da06`. The merged tree `498a05882acbc073a19ebde52b1d927e9ea6cc70` matches the reviewed and owner-authorized head `8ee34b0ff075e6a28d0bb67bbd608fc997e5a807`.

[Pull request CI](https://github.com/djconnect-music-dj/djconnect-app/actions/runs/45796929254) passed with parallel macOS and iOS builds. The iOS product includes the Watch app. On main, the first [Apple CI attempt](https://github.com/djconnect-music-dj/djconnect-app/actions/runs/45799311687) failed in the release-notes presentation test. The second attempt passed the tests and both unsigned build workers. The [separate durable release job](https://github.com/djconnect-music-dj/djconnect-app/actions/runs/45803121768) did not qualify that retry under the original-attempt rule.

This Finalization updates records only and starts its own protected qualification with identical app-source bytes. Apple installation, launch and physical acceptance remain open. The approved distribution manifest points to an earlier candidate.
