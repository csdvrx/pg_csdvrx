> pg_csdvrx - Postgres Generic Clever Scanning Data Verify/Recovery Xpress

## LICENSE

Copyright (c) by CS DVRX, 2019 - data consutant in NYC, tweet me for help!

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3 of the License, or
(at your option) any later version.

## DEMO

![gif](https://raw.githubusercontent.com/csdvrx/pg_csdvrx/master/pg_csdvrx.gif)

## README

```{text}
This started after wasting hours trying to follow advice for pg_filedump:
https://habr.com/en/company/postgrespro/blog/319770/
https://habr.com/en/company/postgrespro/blog/323644/
https://pgday.ru/presentation/146/59649714ee40a.pdf

This started after wasting hours trying to use various advice for pg_filedump
With pg_csdvrx, you will quickly get everything that can be recovered
but restoring from TSV is hard, so it is best kept for cases without
any alternatives, such as after massive hardware RAID problems, as
when most of your data is in /lost+found files named by inode!

Therefore, before attemping this heroic recovery, try the nice way first:

0. Immediately backup somewhere else absolutely everything retrieved,

1. Copy the etc/ files like postgres.conf into the data directory,

2. Tweak as needed and lauch postgres in single user mode with:
/usr/lib/postgresql/11/bin/postgres --single -O -D . dbname

3. By tweaking, I mean adjust to the problem you have:
 - systems indexes : '-c ignore_system_indexes=true'
 - wal: /usr/lib/postgresql/11/bin/pg_resetwal -f .
 - some pages: try to zero, vacuum then reindex:
SET zero_damaged_pages = on; VACUUM FULL;

4. Below is for when it was not enough:
./pg_csdvrx.sh /var/lib/postgresql/11/main
```
