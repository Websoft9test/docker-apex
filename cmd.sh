# additional settings for startService.sh (container init script)

# Set the default password for ADMIN
sed -i "s/Welcome_1\" value=\"$APEX_PASSWORD\">/g" /opt/oracle/apex/setapexadmin.sql

echo "CONN_STRING=sys/$DB_ORACLE_PASSWORD@oracledb:$DB_ORACLE_PORT/xepdb1" > /opt/oracle/variables/conn_string.txt
