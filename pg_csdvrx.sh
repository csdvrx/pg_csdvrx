#!/bin/bash
# 
# pg_csdvrx - Postgres Generic Clever Scanning Data Verify/Recovery Xpress
# 
# Copyright (c) by CS DVRX, 2019 - data consutant in NYC, tweet me for help!
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
# 
# This started after wasting hours trying to follow advice for pg_filedump:
# https://habr.com/en/company/postgrespro/blog/319770/
# https://habr.com/en/company/postgrespro/blog/323644/
# https://pgday.ru/presentation/146/59649714ee40a.pdf
#
# This started after wasting hours trying to use various advice for pg_filedump
# With pg_csdvrx, you will quickly get everything that can be recovered
# but restoring from TSV is hard, so it is best kept for cases without
# any alternatives, such as after massive hardware RAID problems, as
# when most of your data is in /lost+found files named by inode!
#
# Therefore, before attemping this heroic recovery, try the nice way first:
#
# 0. Immediately backup somewhere else absolutely everything retrieved,
#
# 1. Copy the etc/ files like postgres.conf into the data directory,
#
# 2. Tweak as needed and lauch postgres in single user mode with:
# /usr/lib/postgresql/11/bin/postgres --single -O -D . dbname
#
# 3. By tweaking, I mean adjust to the problem you have:
#  - systems indexes : '-c ignore_system_indexes=true'
#  - wal: /usr/lib/postgresql/11/bin/pg_resetwal -f .
#  - some pages: try to zero, vacuum then reindex:
# SET zero_damaged_pages = on; VACUUM FULL;
#
# 4. Below is for when it was not enough:
# ./pg_csdvrx.sh /var/lib/postgresql/11/main

MAGIC_PG_CLASS=1259
MAGIC_PG_ATTRIBUTE=1249
MAGIC_PG_TYPE=1247
PGPATH=$1

[[ $# -lt 1 ]] && printf "$0 usage:\n\tpgdata_path (namespace) (relfilenode)\n\nExample:\n\t$0 /var/lib/postgresql/11/mydatabase\n" && exit 255

# Step 1: find the namespace using pg_class magic and remove _* and pg_* system tables
NAMESPACE=$2
[[ $# -lt 2 ]] && printf "Step 1/4: Please chose the database namespace containing the tables you want:\n" && pg_filedump -D name,oid,oid,oid,oid,oid,oid,~  $PGPATH/base/16384/$MAGIC_PG_CLASS | grep "COPY: " | awk '{ print $3 "\t" $2 }' | grep -v $'\t_' | grep -v pg_ && exit 1

# Step 2: find the relfilenode, using the same pg_class magic
# WONTFIX: redundant for simple 1/1 matches, but checking prevents copy/paste mistakes
[[ $# -lt 3 ]] && printf "Step 2/4: Please confirm the relfilenode matching the table you want:\n" && pg_filedump -D name,oid,oid,oid,oid,oid,oid,~  $PGPATH/base/16384/$MAGIC_PG_CLASS | grep "COPY: " | grep $NAMESPACE | awk '{ print $2 "\t" $8 }' | grep -v $'\t_' | grep -v pg_ | sort | uniq && exit 2

# Step 3.A: find the oids (schema) in the relfilenode, using pg_attribute magic
RELFILENODE=$3
[[ $# -lt 4 ]] && printf "Step 3/4: Please make sure the schema matches:\n\t\n"
# Compared to Sasha tutorial, the pg_attribute.attnum smallint field is used to match
# the order on disk: index created will have changed the natural order, so sort here
# an extra advantage is removing the system columns with negative values:
# ctid xmin cmin xmax cmax tableoid
OIDS=`pg_filedump -D oid,name,oid,int,smallint,smallint,~  $PGPATH/base/16384/$MAGIC_PG_ATTRIBUTE | grep "COPY:" | grep $RELFILENODE | sort -k7 -n | awk '{ if ($7>0) print $3 , $4 }'`
TYPESNUM=`echo "$OIDS" | awk '{ for (i = 1; i <= NF; i++) if (++j % 2 ==0 ) print $i; }'  |grep -v ^.$`
NAMES=`echo "$OIDS" | awk '{ for (i = 1; i <= NF; i++) if (++j % 2 ==1 ) print $i; }'  |grep -v ^.$`

# Step 3.B: obtain the table name to protect the user from copy/paste mistakes
TABLENAME=$(pg_filedump -D name,oid,oid,oid,oid,oid,oid,~  $PGPATH/base/16384/$MAGIC_PG_CLASS |grep "COPY: "| awk '{ print $8,$2}' | grep ^$RELFILENODE | awk '{ print $2 }' | sort | uniq )

# Step 3.C: find the types using the pg_type magic
TYPES=`for t in $TYPESNUM; do pg_filedump -i -D name,~  $PGPATH/base/16384/$MAGIC_PG_TYPE | grep -A5 -E "OID: $t$"  |grep "COPY:" | awk '{ print $2 '} ; done`

# Step 4: Display it all, with recodes until aliases are added to pg_filedump
TYPESALIASED=`echo $TYPES | sed -e 's/int2/smallint/g' -e 's/int4/int/g' -e 's/int8/bigint/g' -e 's/timestamptz/timestamp/g'`

echo " $TABLENAME ("
# j=0; for i in $NAMES; do ((j++)); echo -n "$i " ; echo $TYPE | cut -d ' ' -f $j ; done | tr -s "\n" "," | sed -e 's/,$/\)/' -e 's/,/,\n\t\t/g'
# Show the field name to easily find which tuple pg_filedump complains about
j=0; for i in $NAMES; do ((j++)); echo -n "   $i " ; echo -n $TYPES | cut -d ' ' -f $j | tr -d "\n" ; echo ",  -- field #$j on disk" ; done
# WONTFIX: could interweave NAMES, TYPES using awk, but awk could also do everything else!
# Too much awk would would complicate the script. Most people don't grok awk.
echo " )"

printf "\nStep 4/4: If the table matches all the fields (in any order), recover the data with:\n\t"
echo -n "pg_filedump -o -D '"
echo -n $TYPESALIASED |sed -e 's/ /,/g'
# WONTFIX: give the exact arguments without ,~ to single out genuine incomplete lines
# otherwise pg_filedump complains on each line, before still giving the full data!
# "unable to decode a tuple, no more bytes left. Partial data: " (full data)!!

echo "' $PGPATH/base/16384/$RELFILENODE | grep COPY: |sed -e 's/^.COPY://g' > recovered-$TABLENAME.tsv"
printf "\nIf the decoding fail, pg_filedump can tell on which field number.\nYou can also replace 'COPY' by 'Partial.data:' to get at least some data.\n"

# FIXME? could also give instructions on how to use find to get from lost+found the
# 1024*1024*1024=1G files containing each 1024^3/8192= 131072 records
