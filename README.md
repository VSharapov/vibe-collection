
- dvd-helper : Got a bunch of `.VOB` and other files from a DVD? Don't care about the menu/chapter stuff? Don't wanna spend 25 minutes figuring out the arcane `ffmpeg` invocations? `dvd-helper.sh --delete-parts --name=extras.mkv VTS_02_*.VOB`
- incoming-port-listener : Want to know if your ISP is blocking incoming connections on common ports like 80 or 25? Need to verify port forwarding actually works? `sudo ./incoming-port-tester --ports 80-443 --tcp-only --target YOUR_EXTERNAL_IP`
- fdd-bench : See how fast your flash drive is. Avoid caching & buffers. Watch the speed graph reach a plateau (thermal throttle is pretty common).
