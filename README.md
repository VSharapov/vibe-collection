
- dvd-helper : Got a bunch of `.VOB` and other files from a DVD? Don't care about the menu/chapter stuff? Don't wanna spend 25 minutes figuring out the arcane `ffmpeg` invocations? `dvd-helper.sh --delete-parts --name=extras.mkv VTS_02_*.VOB`
- incoming-port-listener : Want to know if your ISP is blocking incoming connections on common ports like 80 or 25? Need to verify port forwarding actually works? `sudo ./incoming-port-tester --ports 80-443 --tcp-only --target YOUR_EXTERNAL_IP`
- fdd-bench : See how fast your flash drive is. Avoid caching & buffers. Watch the speed graph reach a plateau (thermal throttle is pretty common).
- cursor-search : `cursor search-fzf -i nvme` will bring up an fzf of all your cursor-agent transcript files that match "nvme" (with `-i`/`--ignore-case` passed to `rg`). Needs some kind of `resume` subcommand. PRs welcome.
- gcp-tts : If you're logged into gcp and can `gcloud` this will handhold you through tts and long-running tts (which needs a bucket with permissions) and everything in between. It can set up a new project to encapsulate all this if you have cloudbilling enabled on your current/default project.
- deterministic-ed25519 : Generate a keypair from passphrase - `./seedkey.sh generate "hunter2" ~/.ssh/id_ed25519`

