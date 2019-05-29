# backup-scripts

## Usage

```
curl -fsSL https://raw.githubusercontent.com/carecon/backup-scripts/master/backup-hetzner.sh | sh -s -- \
  -i=files.txt -u=username -p=password -d=/my.server.com
```

Or install it as a daily cron job
```
curl https://raw.githubusercontent.com/carecon/backup-scripts/master/backup-hetzner.sh -o /usr/local/bin/backup-hetzner.sh
chmod +x /usr/local/bin/backup-hetzner.sh

tee /etc/cron.daily/backup.sh <<-'EOF'
#!/bin/bash

/usr/local/bin/backup-hetzner.sh \
  -i=/root/backup-files.txt -u=??? -p=??? -d=/remote/backup/folder
EOF
chmod +x /etc/cron.daily/backup.sh
```

## TODO
- Trim options
  - current default is: saving one daily (for a week), one weekly (for a month), one monthly (for a year), one yearly (forever)
  - allow trimming by size (like max 10gb and delete if more)
  - allow passing some kind of naming pattern?
- Add reporting feature (report somewhere that backup went through and how big the backup was and how much storage is used in total)
- Notify/report somehow if backup fails
