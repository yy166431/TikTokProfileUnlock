#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import sys, paramiko

HOST = "192.168.9.102"
USER = "mobile"
PASS = "166431"

def run(cmd, timeout=30):
    cli = paramiko.SSHClient()
    cli.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    cli.connect(HOST, port=22, username=USER, password=PASS, timeout=timeout, banner_timeout=timeout)
    stdin, stdout, stderr = cli.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode("utf-8", "replace")
    err = stderr.read().decode("utf-8", "replace")
    cli.close()
    return out, err

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "id; uname -a"
    o, e = run(cmd)
    sys.stdout.write(o)
    if e.strip():
        sys.stderr.write("\n[STDERR]\n" + e)
