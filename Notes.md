# Oracle APEX

db and ords images: https://container-registry.oracle.com/   

## /opt/oracle/ords/startService.sh

```
#!/bin/bash
# Copyright (c) 2021, Oracle and/or its affiliates. All rights reserved.
#
#    NAME
#        startService.sh
#
#    DESCRIPTION
#        Script to configured and israt APEX and ORDS on a container
#    NOTES

#
#    CHANGE LOG
#        MODIFIED    VERSION    (MM/DD/YY)
#        admuro      1.0.0       08/24/21 - Script Creation
ORDS_HOME=/opt/oracle/ords
APEX_HOME=/opt/oracle/apex/$APEX_VER
APEXI=/opt/oracle/apex/images/$APEX_VER
INSTALL_LOGS=/tmp/install_container.log
JAVA_HOME=/usr/java/jdk1.8.0_221-amd64/
CONN_STRING_FILE_DIR=/opt/oracle/variables
CONN_STRING_FILE_NAME=conn_string.txt
CONN_STRING_FILE="$CONN_STRING_FILE_DIR"/"$CONN_STRING_FILE_NAME"
WS_NAME='TEST_WS'
export http_proxy= 
export https_proxy= 
export no_proxy= 
export HTTP_PROXY= 
export HTTPS_PROXY= 
export NO_PROXY=
printf "%s%s\n" "INFO : " "This container will start a service running ORDS $ORDS_VER and APEX $APEX_VER."
### Validate variable
function conn_string() {
	if  [ -e $CONN_STRING_FILE ]; then
		source $CONN_STRING_FILE
		if [ -n "$CONN_STRING" ];then
			printf "%s%s\n" "INFO : " "CONN_STRING has been found in the container variables file."
		else
			printf "\a%s%s\n" "ERROR: " "CONN_STRING has not found in the container variables file."
			printf "%s%s\n"   "       " "   user/password@hostname:port/service_name        "
			exit 1
		fi
	else
		printf "\a%s%s\n" "ERROR: " "CONN_STRING_FILE has not added, create a file with CONN_STRING variable and added as docker volume:"
		printf "%s%s\n"   "       " "   mkdir volume ; echo 'CONN_STRING="user/password@hostname:port/service_name"' > volume/$CONN_STRING_FILE_NAME"
		printf "%s%s\n"   "       " "   docker run  --rm --name NAME -v \`pwd\`/volume/:$CONN_STRING_FILE_DIR' -p 8181:8181 container-registry.oracle.com/database/ords:latest "
		exit 1
	fi
	
	export DB_USER=$(echo $CONN_STRING| awk -F"@" '{print $1}'|awk -F"/" '{print $1}')
	export DB_PASS=$(echo $CONN_STRING| awk -F"@" '{print $1}'|awk -F"/" '{print $2}')
	export DB_HOST=$(echo $CONN_STRING| awk -F"@" '{print $2}'|awk -F":" '{print $1}')
	export DB_PORT=$(echo $CONN_STRING| awk -F"@" '{print $2}'|awk -F":" '{print $2}'|awk -F"/" '{print $1}')
	export DB_NAME=$(echo $CONN_STRING| awk -F"@" '{print $2}'|awk -F":" '{print $2}'|awk -F"/" '{print $2}')
}
# Test DB connection
function testDB() {
	conn_string
	sql /nolog << _SQL_SCRIPT &>> $INSTALL_LOGS
	whenever sqlerror exit failure
	whenever oserror exit failure
	conn $CONN_STRING as sysdba
	select 'success' from dual;
	exit
_SQL_SCRIPT
	RESULT=$?
	if [ ${RESULT} -eq 0 ] ; then
		printf "%s%s\n" "INFO : " "Database connection established."
		rm $CONN_STRING_FILE
	else
		printf "\a%s%s\n" "ERROR: " "Cannot connect to database please validate CONN_STRING has below shape:"
		printf "%s%s\n"   "       " "   user/password@hostname:port/service_name                            "
		exit 1
	fi
}

function apex_remove() {
	### Remove old installations
	cd $APEX_HOME
	sql /nolog << _SQL_SCRIPT &>> $INSTALL_LOGS
	conn $CONN_STRING as sysdba
	alter session set container=$DB_NAME;
	alter session set "_oracle_script"=true;
	@apxremov.sql
_SQL_SCRIPT
	RESULT=$?
	if [ ${RESULT} -eq 0 ] ; then
		printf "%s%s\n" "INFO : " "Database connection established."
	else
		printf "\a%s%s\n" "ERROR: " "Cannot connect to database."
		exit 1
	fi
}

function apex() {
	# Validate if apex is instaled and the version
	sql -s /nolog << _SQL_SCRIPT > /tmp/apex_version 2> /dev/null
	conn $CONN_STRING as sysdba
	SET LINESIZE 20000 TRIM ON TRIMSPOOL ON
	SET PAGESIZE 0
	SELECT VERSION FROM DBA_REGISTRY WHERE COMP_ID='APEX';
_SQL_SCRIPT
	# Get RPM installed version
	YEAR=$(echo $APEX_VER | cut -d"." -f1)
	QTR=$(echo $APEX_VER | cut -d"." -f2)
	PATCH=$(echo $APEX_VER| cut -d"." -f3)
	# Get DB installed version
	APEX_DBVER=$(cat /tmp/apex_version  |sed '5q;d'|sed 's/ //g')
	DB_YEAR=$(echo $APEX_DBVER | cut -d"." -f1)
	DB_QTR=$(echo $APEX_DBVER | cut -d"." -f2)
	DB_PATCH=$(echo $APEX_DBVER| cut -d"." -f3)
	
	grep "SQL Error" /tmp/apex_version > /dev/null
	_sql_error=$?
	if [ ${_sql_error} -eq 0 ] ; then
		printf "\a%s%s\n" "ERROR: " "Please validate the database status."
		grep "SQL Error" /tmp/apex_version 
		exit 1
	fi
	if [ -n "$APEX_DBVER" ]; then
		# Validate if an upgrade needed
		if [ "$APEX_DBVER" = "$APEX_VER" ]; then
			printf "%s%s\n" "INFO : " "APEX $APEX_VER is already installed in your database."
			export INS_STATUS="INSTALLED"
		elif [ $DB_YEAR -gt $YEAR ]; then
			printf "\a%s%s\n" "ERROR: " "A newer APEX version ($APEX_DBVER) is already installed in your database. The APEX version in this container is $APEX_VER. Stopping the container." 
			exit 1
		elif [ $DB_YEAR -eq $YEAR ] && [ $DB_QTR -gt $QTR ]; then
			printf "\a%s%s\n" "ERROR: " "A newer APEX version ($APEX_DBVER) is already installed in your database. The APEX version in this container is $APEX_VER. Stopping the container."
			exit 1
		elif [ $DB_YEAR -eq $YEAR ] && [ $DB_QTR -eq $QTR ] && [ $DB_PATCH -gt $PATCH ]; then
			printf "\a%s%s\n" "ERROR: " "A newer APEX version ($APEX_DBVER) is already installed in your database. The APEX version in this container is $APEX_VER. Stopping the container."
			exit 1
		else
			printf "%s%s\n" "INFO : " " Your have installed APEX ($APEX_DBVER) on you database but will be upgraded to $APEX_VER"
			export INS_STATUS="UPGRADE"
			apex_install
			apex_config
		fi
	else
		printf "%s%s\n" "INFO : " "Apex is not installed on your database."
		export INS_STATUS="FRESH"
		apex_install
		apex_config
	fi
}

function apex_install() {
	if [ -f $APEX_HOME/apexins.sql ]; then
		printf "%s%s\n" "INFO : " "Installing APEX on your DB please be patient."
		printf "%s%s\n" "INFO : " "You can check the logs by running the command below in a new terminal window:"
		printf "%s%s\n" "       " "	docker exec -it $HOSTNAME tail -f $INSTALL_LOGS"
		cd $APEX_HOME
		sql /nolog << _SQL_SCRIPT  &>> $INSTALL_LOGS
		conn $CONN_STRING as sysdba
		select user from dual;
		@apexins SYSAUX SYSAUX TEMP /i/
		@apex_rest_config_core.sql /opt/oracle/apex/$APEX_VER/ oracle oracle
_SQL_SCRIPT
		RESULT=$?
		if [ ${RESULT} -eq 0 ] ; then
			printf "%s%s\n" "INFO : " "APEX has been installed."
		else
			printf "\a%s%s\n" "ERROR: " "APEX installation failed"
			exit 1
		fi
	else
		printf "\a%s%s\n" "ERROR: " "APEX installation script missing."
	fi
}

function apex_password() {
	if [[ ${INS_STATUS} == "FRESH" ]] ; then
		# Set ADMIN passsword to Welcome_1
		cd $APEX_HOME
		cp /opt/oracle/apex/setapexadmin.sql .
		sql /nolog << _SQL_SCRIPT &>> $INSTALL_LOGS
		conn $CONN_STRING as sysdba
		alter session set container=$DB_NAME;
		@setapexadmin.sql
_SQL_SCRIPT
		sql /nolog << _SQL_SCRIPT >> $INSTALL_LOGS
		conn $CONN_STRING as sysdba
		alter session set container=$DB_NAME;
		DECLARE 
		l_user_id NUMBER;
		BEGIN
			APEX_UTIL.set_workspace(p_workspace => 'INTERNAL');
			l_user_id := APEX_UTIL.GET_USER_ID('ADMIN');
			APEX_UTIL.EDIT_USER(p_user_id => l_user_id, p_user_name  => 'ADMIN', p_change_password_on_first_use => 'Y');
		END;
_SQL_SCRIPT
		RESULT=$?
		if [ ${RESULT} -eq 0 ] ; then
			printf "%s%s\n" "INFO : " "APEX ADMIN password has configured as 'Welcome_1'."
			printf "%s%s\n" "INFO : " "Use below login credentials to first time login to APEX service:"
			printf "%s%s\n" "       " "	Workspace: internal"
			printf "%s%s\n" "       " "	User:      ADMIN"
			printf "%s%s\n" "       " "	Password:  Welcome_1"
		else
			printf "\a%s%s\n" "ERROR : " "APEX Configuration failed."
		exit 1
		fi
	else 
		printf "%s%s\n" "INFO : " "APEX was updated but your previous ADMIN password was not affected."
	fi	
}

function apex_config() {
	printf "%s%s\n" "INFO : " "Configuring APEX."
	sql /nolog << _SQL_SCRIPT  &>> $INSTALL_LOGS
	conn $CONN_STRING as sysdba
	alter session set container=$DB_NAME;
	alter profile default limit password_life_time UNLIMITED;
	ALTER USER APEX_PUBLIC_USER ACCOUNT UNLOCK;
	ALTER USER APEX_PUBLIC_USER IDENTIFIED BY oracle;
	exit
_SQL_SCRIPT
	RESULT=$?
	if [ ${RESULT} -eq 0 ] ; then
		printf "%s%s\n" "INFO : " "APEX_PUBLIC_USER has been configured as oracle."
	else
		printf "\a%s%s\n" "ERROR : " "APEX Configuration failed."
		exit 1
	fi
	apex_password
}

function ords_rpnd_file() {
	echo "db.hostname=$DB_HOST
	db.port=$DB_PORT
	db.servicename=$DB_NAME
	db.password=oracle
	user.public.password=oracle
	user.apex.listener.password=oracle 
	user.apex.restpublic.password=oracle
	plsql.gateway.add=true
	db.username=APEX_PUBLIC_USER
	rest.services.apex.add=true
	rest.services.ords.add=true
	schema.tablespace.default=SYSAUX
	schema.tablespace.temp=TEMP
	standalone.http.port=8181
	standalone.use.https=false
	standalone.mode=true
	feature.sdw=true
	standalone.static.path=$ORDS_HOME/docs
	standalone.static.images=/opt/oracle/apex/$APEX_VER/images
	standalone.static.context.path=/i
	rest.services.apex.add=true
	rest.services.ords.add=true
	restEnabledSql.active=true
	sys.user=SYS as sysdba
	sys.password=$DB_PASS
	user.tablespace.default=SYSAUX
	user.tablespace.temp=TEMP
	database.api.enabled=true" > /tmp/ords.rsp	
}

function install_ords() {
	printf "%s%s\n" "INFO : " "Preparing ORDS."
	ords_rpnd_file
	$JAVA_HOME/bin/java -jar $ORDS_HOME/ords.war configdir $ORDS_HOME/config 2&> $INSTALL_LOGS
	mkdir -p $ORDS_HOME/config/ords $ORDS_HOME/docs
	printf "%s%s\n" "INFO : " "Installing ORDS on you database and starting ORDS services."
	$JAVA_HOME/bin/java -jar $ORDS_HOME/ords.war install simple --parameterFile /tmp/ords.rsp -silent
}

function run_ords() {
	DB_HOST=$(grep db.hostname /$ORDS_HOME/config/ords/defaults.xml|cut -d">" -f2|cut -d"<" -f1)
	DB_PORT=$(grep db.port /$ORDS_HOME/config/ords/defaults.xml|cut -d">" -f2|cut -d"<" -f1)
	DB_NAME=$(grep db.servicename /$ORDS_HOME/config/ords/defaults.xml|cut -d">" -f2|cut -d"<" -f1)
	printf "%s%s\n" "INFO : " "Attempting to start ORDS with a volume configuration."
	printf "%s%s\n" "INFO : " "ORDS will connect to: ${DB_HOST}:${DB_PORT}/${DB_NAME}."
	$JAVA_HOME/bin/java -jar $ORDS_HOME/ords.war configdir $ORDS_HOME/config 2&> $INSTALL_LOGS
	$JAVA_HOME/bin/java -jar $ORDS_HOME/ords.war standalone
}

function run_script() {
	if [ -e $ORDS_HOME/config/ords/defaults.xml ]; then
		if [ -e $CONN_STRING_FILE ]; then
			testDB
			apex
			if [ "${INS_STATUS}" == "INSTALLED" ]; then 
				run_ords
			elif [ "${INS_STATUS}" == "UPGRADE" ]; then
				install_ords
			elif [ "${INS_STATUS}" == "FRESH" ]; then
				install_ords
			fi
		else
			printf "\a%s%s\n" "WARN : " "Container variables file was not found. Could not obtain the current APEX version in your database."
			run_ords
		fi
	else
		# No config file then validate conn_string file and apex 
		testDB
		apex
		install_ords
	fi
}
run_script
```
