A home internet ISP will often block common ports like http/80 and smtp/25, dropping incoming connections.
The only way to be sure is to test it.
The user is assumed to be running this on the gateway, or to have forwarded a port range on the gateway.
The basic invocation is `./incoming-port-tester`, implying some sane defaults:

- Test ports : 1-16384
- Group consecutive identical results (e.g. "[PASS] TCP 444-887") : true
- `netcat` path : $(which nc)
- Timeout (seconds) : 3
- Timeout resets after each step (e.g. after connection is established)
- Print "TCP"/"UDP" even if only one was specified : false
- TCP only : false
- UDP only : false
- Print error codes instead of WORDs : false

Test outcomes that I can think of:
0 - PASS - The server started successfully, the client connected, and the both communication directions worked
1 - FAIL - The client could NOT establish a connection in time
2 - SEND - The client's message failed to reach the server in time
4 - SUDO - The server failed to start because of privilege reasons
8 - USED - The server failed to start because the port is in use
16 - RECV - The server's message didn't reach the client in time
64 - ERRO - Other error
??? - MULT - Multiple errors were encountered (e.g. 82 = 64 + 16 + 2)


