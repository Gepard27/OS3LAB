[Unit]
Description=Process Watcher Service
After=local-fs.target

[Service]
WorkingDirectory=/home/labs/lab3

Type=simple

ExecStart=/bin/bash /home/user/lab3/watcher.sh \
    --config    /home/user/lab3/watcher.conf \
    --watch-dir /home/user/lab3/watched \
    --fifo      /home/user/lab3/watcher.fifo \
    --log       /home/user/lab3/logs/watcher.log \
    --pid       /home/user/lab3/watcher.pid \
    --interval  5 \
    --log-level INFO

ExecReload=/bin/kill -HUP $MAINPID

Restart=on-failure
RestartSec=5

KillSignal=SIGTERM
TimeoutStopSec=15

StandardOutput=journal
StandardError=journal
SyslogIdentifier=watcher


[Install]
WantedBy=multi-user.target
