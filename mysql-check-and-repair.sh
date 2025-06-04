#!/bin/bash

set -e

# ───── Format seconds to Xm Ys ─────
human_time() {
  local SECS=$1
  local MINS=$((SECS / 60))
  local REM=$((SECS % 60))
  if (( MINS > 0 )); then
    echo "${MINS}m ${REM}s"
  else
    echo "${REM}s"
  fi
}

# ───── Database selection ─────
echo "🔍 Retrieving list of available databases..."
DATABASES=$(mysql -Bse "SHOW DATABASES;" | grep -v -E "^(information_schema|mysql|performance_schema|sys)$")

echo "📚 Available databases:"
select DB in $DATABASES; do
  if [[ -n "$DB" ]]; then
    echo "✅ Selected database: $DB"
    break
  else
    echo "❌ Invalid selection. Try again."
  fi
done

# ───── Table list and size scan ─────
echo
echo "🔄 Gathering table information and size..."

TABLE_INFO=$(mysql -N -D "$DB" -e "
  SELECT table_name,
         engine,
         ROUND((data_length + index_length) / 1024 / 1024, 2) AS size_mb
  FROM information_schema.tables
  WHERE table_schema = '$DB';
")

TABLE_COUNT=$(echo "$TABLE_INFO" | wc -l)
MYISAM_TABLES=$(echo "$TABLE_INFO" | awk '$2 == "MyISAM" || $2 == "Aria" {print $1}' | wc -l)
INNODB_TABLES=$(echo "$TABLE_INFO" | awk '$2 == "InnoDB" {print $1}' | wc -l)
ENGINES=$(echo "$TABLE_INFO" | awk '{print $2}' | sort | uniq)

MYISAM_SIZE=$(echo "$TABLE_INFO" | awk '$2 == "MyISAM" || $2 == "Aria" {sum += $3} END {print sum+0}')
INNODB_SIZE=$(echo "$TABLE_INFO" | awk '$2 == "InnoDB" {sum += $3} END {print sum+0}')

# ───── Estimate time more realistically ─────
EST_CHECK_MYISAM=0
EST_REPAIR_MYISAM=0
EST_CHECK_INNODB=0

while read TABLE ENGINE SIZE_MB; do
  if [[ "$ENGINE" == "MyISAM" || "$ENGINE" == "Aria" ]]; then
    CHECK_EST=$(echo "$SIZE_MB" | awk '{v=$1*0.05; printf "%d", (v<1)?1:v}')
    REPAIR_EST=$(echo "$SIZE_MB" | awk '{v=$1*0.1;  printf "%d", (v<1)?1:v}')
    EST_CHECK_MYISAM=$((EST_CHECK_MYISAM + CHECK_EST))
    EST_REPAIR_MYISAM=$((EST_REPAIR_MYISAM + REPAIR_EST))
  elif [[ "$ENGINE" == "InnoDB" ]]; then
    CHECK_EST=$(echo "$SIZE_MB" | awk '{v=$1*0.015+0.5; printf "%d", (v<1)?1:v}')
    EST_CHECK_INNODB=$((EST_CHECK_INNODB + CHECK_EST))
  fi
done <<< "$TABLE_INFO"

TOTAL_EST_TIME=$((EST_CHECK_MYISAM + EST_REPAIR_MYISAM + EST_CHECK_INNODB))

# ───── Display plan ─────
echo
echo "📋 Execution plan:"
echo "  • Database: $DB"
echo "  • Total tables: $TABLE_COUNT"
echo "  • Engines: $ENGINES"
echo "  • MyISAM/Aria tables: $MYISAM_TABLES (~${MYISAM_SIZE} MB)"
echo "  • InnoDB tables: $INNODB_TABLES (~${INNODB_SIZE} MB)"
echo
echo "⏱ Estimated time:"
echo "  • MyISAM CHECK: ~${EST_CHECK_MYISAM}s ($(human_time $EST_CHECK_MYISAM))"
echo "  • MyISAM REPAIR (if needed): ~${EST_REPAIR_MYISAM}s ($(human_time $EST_REPAIR_MYISAM))"
echo "  • InnoDB CHECK: ~${EST_CHECK_INNODB}s ($(human_time $EST_CHECK_INNODB))"
echo "  • 📊 Total estimate: ~${TOTAL_EST_TIME}s ($(human_time $TOTAL_EST_TIME))"
echo
read -p "🔐 Proceed with checking and repairing all tables? (y/N): " CONFIRM
echo

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "🚫 Operation cancelled."
  exit 0
fi

# ───── Begin processing ─────
TOTAL_START=$(date +%s)
echo "🚀 Processing tables..."
echo

while read TABLE ENGINE SIZE_MB; do
  echo "🔸 $TABLE ($ENGINE, ${SIZE_MB}MB)"
  START=$(date +%s)

  if [[ "$ENGINE" == "MyISAM" || "$ENGINE" == "Aria" ]]; then
    echo "🧪 CHECK..."
    mysql -D "$DB" -Bse "CHECK TABLE \`$TABLE\`;" > /tmp/check_result.txt
    cat /tmp/check_result.txt

    if grep -q -E "error|crashed|corrupt" /tmp/check_result.txt; then
      echo "❗ Damaged — launching REPAIR..."
      REPAIR_START=$(date +%s)
      mysql -D "$DB" -e "REPAIR TABLE \`$TABLE\`;"
      REPAIR_END=$(date +%s)
      REPAIR_TIME=$((REPAIR_END - REPAIR_START))
      EST_REP=$(echo "$SIZE_MB" | awk '{v=$1*0.1; printf "%d", (v<1)?1:v}')
      echo "⏱ REPAIR took ${REPAIR_TIME}s ($(human_time $REPAIR_TIME)) (estimated: ${EST_REP}s ≈ $(human_time $EST_REP))"
    else
      echo "✔ Table is OK"
    fi

    END=$(date +%s)
    ACTUAL_TIME=$((END - START))
    EST_CHECK=$(echo "$SIZE_MB" | awk '{v=$1*0.05; printf "%d", (v<1)?1:v}')
    echo "⏱ CHECK took ${ACTUAL_TIME}s ($(human_time $ACTUAL_TIME)) (estimated: ${EST_CHECK}s ≈ $(human_time $EST_CHECK))"

  elif [[ "$ENGINE" == "InnoDB" ]]; then
    echo "ℹ InnoDB — CHECK only"
    START=$(date +%s)
    mysql -D "$DB" -e "CHECK TABLE \`$TABLE\`;"
    END=$(date +%s)
    TIME_SPENT=$((END - START))
    EST=$(echo "$SIZE_MB" | awk '{v=$1*0.015+0.5; printf "%d", (v<1)?1:v}')
    echo "⏱ CHECK took ${TIME_SPENT}s ($(human_time $TIME_SPENT)) (estimated: ${EST}s ≈ $(human_time $EST))"
  else
    echo "⚠ Skipped unsupported engine: $ENGINE"
  fi

  echo "----------------------------"
done <<< "$TABLE_INFO"

TOTAL_END=$(date +%s)
TOTAL_TIME=$((TOTAL_END - TOTAL_START))
echo "✅ All tables processed. Total time: ${TOTAL_TIME}s ($(human_time $TOTAL_TIME))."
