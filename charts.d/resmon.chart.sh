# no need for shebang - this file is loaded from charts.d.plugin

# netdata
# real-time performance and health monitoring, done right!
# (C) 2016 Costa Tsaousis <costa@tsaousis.gr>
# GPL v3+
#

# Description: Resmon netdata charts.d plugin
# Author: Kevin Altman

# the URL to download resmon status info
# usually http://localhost:8084/resmon
resmon_url=""

# _update_every is a special variable - it holds the number of seconds
# between the calls of the _update() function
resmon_update_every=

resmon_priority=60000

# convert resmon floating point values
# to integer using this multiplier
# this only affects precision - the values
# will be in the proper units
resmon_decimal_detail=1000000

# used by volume chart to convert bytes to KB
resmon_decimal_KB_detail=1000

resmon_check() {

        require_cmd xmlstarlet || return 1


        # check if url, username, passwords are set
        if [ -z "${resmon_url}" ]; then
                error "resmon url is unset or set to the empty string"
                return 1
        fi

        # check if we can get to resmon's status page
        resmon_get
        if [ $? -ne 0 ]
                then
                error "cannot get to status page on URL '${resmon_url}'. Please make sure resmon url is correct."
                return 1
        fi

        # this should return:
        #  - 0 to enable the chart
        #  - 1 to disable the chart

        return 0
}

resmon_get() {
        # collect resmon values
        mapfile -t lines < <(run curl -Ss "$resmon_url" |\
                run xmlstarlet sel \
                        -D -t -v "/ResmonResults/ResmonResult/metric[@name='system_in_maintenance_since']" \
                        -n -v "/ResmonResults/ResmonResult/metric[@name='cases_active']" \
                        -n -v "/ResmonResults/ResmonResult/metric[@name='recv_messages']" \
                        -n -v "/ResmonResults/ResmonResult/metric[@name='sent_messages']" \
                        -n -v "/ResmonResults/ResmonResult/metric[@name='cases_total']" \
                        -n -v "count(/ResmonResults/ResmonResult[@service='noit_maintenance']/metric[contains(@name, '\`in_maintenance_since') and .!=0])" \
                        -n -v "/ResmonResults/ResmonResult/metric[@name='mq_status']" -n -)

        resmon_system_maintenance="${lines[1]}"
        resmon_cases_active="${lines[2]}"
        resmon_recv_messages="${lines[3]}"
        resmon_sent_messages="${lines[4]}"
        resmon_cases_total="${lines[5]}"
        resmon_brokers_maintenance="${lines[6]}"
        resmon_mq_status="${lines[7]}"

        return 0
}

# _create is called once, to create the charts
resmon_create() {
        cat <<EOF
CHART resmon.system '' "resmon system" "state" System resmon.system area $((resmon_priority + 8)) $resmon_update_every
DIMENSION system_maintenance '' absolute
CHART resmon.cases '' "resmon cases" "Number of Cases" Cases resmon.cases line $((resmon_priority + 5)) $resmon_update_every
DIMENSION active '' absolute 1
DIMENSION total '' absolute 1
CHART resmon.mq '' "resmon mq" "mq status" mq resmon.mq line $((resmon_priority + 6)) $resmon_update_every
DIMENSION recv '' absolute 1
DIMENSION sent '' absolute 1
DIMENSION status '' absolute 1
CHART resmon.broker '' "Brokers in Maintenance" "state" Broker resmon.broker area $((resmon_priority + 8)) $resmon_update_every
DIMENSION broker '' absolute 1
EOF
        return 0
}

# _update is called continiously, to collect the values
resmon_update() {
        local reqs net
        # the first argument to this function is the microseconds since last update
        # pass this parameter to the BEGIN statement (see bellow).

        # do all the work to collect / calculate the values
        # for each dimension
        # remember: KEEP IT SIMPLE AND SHORT

        resmon_get || return 1

        # write the result of the work.
        cat <<VALUESEOF
BEGIN resmon.system $1
SET system_maintenance = $((resmon_system_maintenance))
END
BEGIN resmon.cases $1
SET active = $((resmon_cases_active))
SET total = $((resmon_cases_total))
END
BEGIN resmon.mq $1
SET recv = $((resmon_recv_messages))
SET sent = $((resmon_sent_messages))
SET status = $((resmon_mq_status))
END
BEGIN resmon.broker $1
SET broker = $((resmon_brokers_maintenance))
END
VALUESEOF

        return 0
}
