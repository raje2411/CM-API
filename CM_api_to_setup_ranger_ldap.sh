#!/bin/bash

validate_credentials() {
    local response=$(curl -s -u ${username}:${password} -X GET "http://${cm_host}:${cm_port}/api/v31/clusters/${cluster_name}" 2>&1)
    if [[ $response =~ "Unauthorized" ]]; then
        echo "Invalid Cloudera Manager credentials. Please provide valid credentials."
        exit 1
    fi
}

# Cloudera Manager host URL
read -p "Cloudera Manager hostname: " cm_host

# Cloudera Manager port (default: 7180)
read -p "Cloudera Manager port(7180): " input_port
cm_port=${input_port:-7180}

# Cloudera Manager username (default: admin)
read -p "Cloudera Manager username(admin): " input_username
username=${input_username:-admin}

# Cloudera Manager password
read -s -p "Cloudera Manager password: " input_password
echo

# Use current user's username as password if not set
password=${input_password:-$USER}

validate_credentials

# Cluster name , DO NOT CHANGE this, this seems to squadron2 default
cluster_name="CDP-7.1.9-CM"


# Function to update the CM property
update_property() {
    local name="$1"
    local value="$2"
    local role_config_group="$3"
    local data='{
        "items": [
            {
                "name": "'"${name}"'",
                "value": "'"${value}"'"
            }
        ]
    }'

    # Send the API request
    api_url="http://${cm_host}:${cm_port}/api/v31/clusters/${cluster_name}/services/ranger/roleConfigGroups/${role_config_group}/config"

    #For Debug
    #echo $"curl -X PUT -u ${username}:${password} -i -H "Content-Type:application/json" -d "${data}" ${api_url}"

    curl -X PUT -u ${username}:${password} -i -H "Content-Type:application/json" -d "${data}" ${api_url}
}




#Setting up Ranger Admin with squadron new LDAP configs
ranger_admin_properties=(
    'ranger.ldap.ad.url=ldap://EXAMPLE.COM:389'
    'ranger.ldap.ad.bind.dn=sup_admin@EXAMPLE.COM'
    'ranger_ldap_ad_bind_password=password123!'
    'ranger.ldap.ad.domain=EXAMPLE.COM'
    'ranger.ldap.ad.base.dn=OU=Cloudera,DC=EXAMPLE,DC=COM'
    'ranger.ldap.ad.user.searchfilter=sAMAccountName'
)


for property in "${ranger_admin_properties[@]}"; do
    # Split the property into key and value
    IFS='=' read -r key value <<< "$property"
    update_property "$key" "$value" "ranger-RANGER_ADMIN-BASE"
done



#Setting up Ranger Usersync Config with squadron new LDAP configs

ranger_usersync_properties=(
    'ranger.usersync.ldap.url=ldap://EXAMPLE.COM:389'
    'ranger.usersync.ldap.binddn=sup_admin@EXAMPLE.COM'
    'ranger_usersync_ldap_ldapbindpassword=password123!'
    'ranger.usersync.ldap.user.searchbase=OU=Cloudera,DC=EXAMPLE,DC=COM'
    'ranger.usersync.ldap.user.objectclass=user'
    'ranger.usersync.ldap.user.nameattribute=sAMAccountName'
    'ranger.usersync.ldap.username.caseconversion=lower'
    'ranger.usersync.ldap.groupname.caseconversion=lower'
    'ranger.usersync.group.searchbase=OU=Cloudera,DC=EXAMPLE,DC=COM'
    'ranger.usersync.source.impl.class=org.apache.ranger.ldapusersync.process.LdapUserGroupBuilder'
)

for property in "${ranger_usersync_properties[@]}"; do
    # Split the property into key and value
    IFS='=' read -r key value <<< "$property"
    update_property "$key" "$value" "ranger-RANGER_USERSYNC-BASE"
done


# Function to restart Ranger service
restart_ranger_service() {
    local service_name="ranger"
    local api_url="http://${cm_host}:${cm_port}/api/v31/clusters/${cluster_name}/services/${service_name}/commands/restart"
    
    # Send the API request to restart the Ranger service
    response=$(curl -X POST -u "${username}:${password}" -H "Content-Type:application/json" "${api_url}")

    # Check if the request was accepted
    if echo "$response" | grep -q '"active" : true,'; then
        echo "Ranger service restart request accepted."
    else
        echo "Failed to restart Ranger service. Response: $response"
    fi
}


# CM API URL for restarting Ranger service
# Call the function to restart Ranger service
restart_ranger_service

