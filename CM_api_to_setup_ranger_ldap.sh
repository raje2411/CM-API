#!/bin/bash

# Function to validate Cloudera Manager credentials
validate_credentials() {
    local response=$(curl -s -u ${username}:${password} -X GET "http://${cm_host}:${cm_port}/api/v31/clusters/${cluster_name}" 2>&1)
    if [[ $response =~ "Unauthorized" ]]; then
        echo "Invalid Cloudera Manager credentials. Please provide valid credentials."
        exit 1
    fi
}

# Cloudera Manager hostname prompt
read -p "Cloudera Manager hostname: " cm_host

# Cloudera Manager port (default: 7180)
read -p "Cloudera Manager port(7180): " input_port
cm_port=${input_port:-7180}

# Cloudera Manager username prompt (default: admin)
read -p "Cloudera Manager username(admin): " input_username
username=${input_username:-admin}

# Cloudera Manager password prompt (default: current user's username)
read -s -p "Cloudera Manager password:($USER) " input_password
echo

# Use current user's username as password if not set
password=${input_password:-$USER}

# Mask sensitive information
masked_password="********"
masked_cm_host="masked_cm_host"
masked_ldap_url="ldap://masked_ldap_url:389"
masked_bind_dn="cn=admin,dc=example,dc=com"
masked_ldap_bind_password="ldap_bind_password"
masked_search_base="OU=masked_search_base,DC=example,DC=com"

# Validate Cloudera Manager credentials
validate_credentials

# Function to update CM property
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

    # Perform the API request and check for errors
    response=$(curl -s -w "%{http_code}" -X PUT -u ${username}:${password} -H "Content-Type: application/json" -d "${data}" ${api_url})

    # Extract the HTTP status code
    http_status="${response: -3}"

    # Check if the HTTP status code indicates an error
    if [[ $http_status != "200" ]]; then
        echo "Error updating property: $name. HTTP Status: $http_status"
        return 1
    else
        echo "Property updated successfully: $name"
    fi
}

# Setting up Ranger Admin properties
ranger_admin_properties=(
    'ranger.ldap.ad.url=ldap://example.com:389'
    'ranger.ldap.ad.bind.dn=cn=admin,dc=example,dc=com'
    'ranger_ldap_ad_bind_password=ldap_bind_password'
    'ranger.ldap.ad.domain=example.com'
    'ranger.ldap.ad.base.dn=OU=masked_search_base,DC=example,DC=com'
    'ranger.ldap.ad.user.searchfilter=sAMAccountName'
)

# Update Ranger Admin properties
for property in "${ranger_admin_properties[@]}"; do
    IFS='=' read -r key value <<< "$property"
    if ! update_property "$key" "$value" "ranger-RANGER_ADMIN-BASE"; then
        echo "Error updating property: $property"
        exit 1
    fi
done

# Setting up Ranger Usersync properties
ranger_usersync_properties=(
    'ranger.usersync.ldap.url=ldap://example.com:389'
    'ranger.usersync.ldap.binddn=cn=admin,dc=example,dc=com'
    'ranger_usersync_ldap_ldapbindpassword=ldap_bind_password'
    'ranger.usersync.ldap.user.searchbase=OU=masked_search_base,DC=example,DC=com'
    'ranger.usersync.ldap.user.objectclass=user'
    'ranger.usersync.ldap.user.nameattribute=sAMAccountName'
    'ranger.usersync.ldap.username.caseconversion=lower'
    'ranger.usersync.ldap.groupname.caseconversion=lower'
    'ranger.usersync.group.searchbase=OU=masked_group_search_base,DC=example,DC=com'
    'ranger.usersync.source.impl.class=org.apache.ranger.ldapusersync.process.LdapUserGroupBuilder'
)

# Update Ranger Usersync properties
for property in "${ranger_usersync_properties[@]}"; do
    IFS='=' read -r key value <<< "$property"
    if ! update_property "$key" "$value" "ranger-RANGER_USERSYNC-BASE"; then
        echo "Error updating property: $property"
        exit 1
    fi
done

# Function to restart Ranger service
restart_ranger_service() {
    local service_name="ranger"
    local api_url="http://${cm_host}:${cm_port}/api/v31/clusters/${cluster_name}/services/${service_name}/commands/restart"

    # Send the API request to restart the Ranger service
    response=$(curl -s -X POST -u "${username}:${password}" -H "Content-Type:application/json" "${api_url}")

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
