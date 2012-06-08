#!/bin/sh
#yavdb -s $1 -t jdb "jdb -classpath $2 -sourcepath $3 $4"

yavdb -s $1 -t jdb "jdb -sourcepath $2 -connect com.sun.jdi.SocketAttach:port=$3"
 
echo "<enter to quit>"
read dummy
