# additional settings for startService.sh (container init script)
# Set the default password for ADMIN

sed -i "s/Welcome_1\" value=\"$APEX_PASSWORD\">/g" /opt/oracle/apex/setapexadmin.sql
