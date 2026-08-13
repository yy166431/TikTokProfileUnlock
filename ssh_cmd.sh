#!/bin/bash
expect << 'EXPECT_EOF'
spawn ssh mobile@192.168.9.103 -p 22 "killall -9 TikTok 2>/dev/null; echo TikTok已杀死"
expect "password:"
send "166431\r"
expect eof
EXPECT_EOF
