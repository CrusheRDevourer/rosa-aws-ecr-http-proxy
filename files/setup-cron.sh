#!/bin/sh
# Move the template only the first time
if [ -f /cron/token ]; then
    # Get USER_ID of running user
    USER_ID=$(id -u)
    mv /cron/token /cron/"$USER_ID"
fi
# Execute the cron job as the running user
exec /usr/sbin/busybox crond -f -L /dev/stdout -c /cron