#!/bin/bash
destination="$1"
timeout="$2"
bandwidth="$3"

function jamal_is_dead()
{
        ping $destination -nqc 1 -W 1 2>/dev/null 1>/dev/null || jamal_is_dead_a_lot="yes"
}

jamal_is_dead

if [ ! $jamal_is_dead_a_lot ]; then

complex_shit=$(echo "($timeout/0.2)+10" | bc -l)

#for bandwidth in {5..10}
#do
        date && iperf -c $destination -u -fm -d -t$timeout -b $bandwidth"m" & ping $destination -q -s 128 -i 0.2 -c $complex_shit && date ; date && iperf -c $destination -u -fm -d -t$timeout -b $bandwidth"m" & ping $destination -q -s 256 -i 0.2 -c $complex_shit && date ; date && iperf -c $destination -u -fm -d -t$timeout -b $bandwidth"m" & ping $destination -q -s 512 -i 0.2 -c $complex_shit && date ; date && iperf -c $destination -u -fm -d -t$timeout -b $bandwidth"m" & ping $destination -q -s 1024 -i 0.2 -c $complex_shit && date
#done

fi

