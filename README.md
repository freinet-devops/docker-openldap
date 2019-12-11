# OpenLDAP Docker Container

* Small Alpine based Image
* Can be used with slapd.d ( Default )or slapd.conf
* Config and databases not mounted directly, but made accessible in /mnt and copied/imported if not already there

## Usage

docker run -d
  --name openldap
  -v $PWD/databases:/var/lib/openldap
  -v $PWD/config:/etc/openldap
  -v $PWD/import_dir:/mnt
  freinet/openldap run -d -0

### Run supported management commands in the container

The following commands are available via the entrypoint script:

####   add_data
Add data using slapadd from a file available in the container

This command has a special usage pattern. As it adds the data using slapadd, it requires the server be NOT running. To achieve the following steps are necessary:
Prerequisite: The container running the ldap-Server must have its databases in a volume

1. Stop the Container running openldap:

        bash# docker stop openldap

2. Run a temporary container with image on the same volumes and with the same config

        bash# docker run --rm -v ./config/example:/mnt -v ldapdata:/var/lib/openldap freinet/openldap add_data -b <db_name> -l data.ldif

to create the same config ad hoc from a mount on server start.

or

        bash# docker run --rm -v config-volume/example:/mnt -v ldapdata:/var/lib/openldap freinet/openldap add_data -b <db_name> -l data.ldif

to use the same persisted config in a volume.

This can be simplified if using docker-compose, because the mounts will already be available

    docker-compose run --rm ldap slapadd_data -b db_name -l data.ldif

3. restart the server container

        bash# docker start openldap

#### change_rootpassword
When using OLC, a function change_rootpassword can be used to change the password of the databases root user:
As this uses ldap_modify, the container does not need to be stopped.

Assuming a container named 'ldap':

    docker exec ldap /entrypoint.sh change_rootpassword -b cn=config -p $CLEARTEXT_PW
    docker exec ldap /entrypoint.sh change_rootpassword -b cn=config -h $HASHED_PW
    docker exec ldap /entrypoint.sh change_rootpassword -n 2 -b hdb -p CLEARTEXT_PW
    docker exec ldap /entrypoint.sh change_rootpassword -n 2 -b hdb -h $HASHED_PW

would all work. They generate the ldif snipped needed and run it using ldapmodify.

With the second option the password needs to first be hashed using

     slappasswd -s $cleartext_pw

Do NOT pass the password in base64 encoding! ldapmodify->changetype:modify expects it non-encoded in the LDIF.
This is a quirk of openldap, since other commands actually expect the password to also be base64-encoded in the LDIF.
The image tries to work around these quirks, by always requiring you to pass in passwords hashed but not yet base64-encoded, that is, they should look something like this:

{SSHA}zO9mBL1sBKDpsbXhZeXwTt2rVN24QoXS


#### add_database
When using OLC, a function add_database can be used to add a new database to the container and create its subfolder in $DB_DATADIR
e.g.

    docker exec ldap /entrypoint.sh add_database -b dc=directory,dc=new,dc=site -e hdb -D cn=admin,dc=directory,dc=new,dc=site -p cleartext_pw

or

    docker exec ldap /entrypoint.sh add_database -b dc=directory,dc=new,dc=site -e hdb -D cn=admin,dc=directory,dc=new,dc=site -h hashed_pw

As with change_rootpassword, do NOT pass the password in base64 encoding!

Curiously, the used tool ldapadd (which is actually ldapmodify with an LDIF with changetype:add ) DOES expect the password to be encoded in base64 in the LDIF, but the task in the entrypoint script takes care of that to reduce surprises).

This will create the path for the database in /var/lib/openldap/dc=directory,dc=new,dc=site/ , and a new node in cn=config for the database, with olcRootDN and olcRootPW set accordingly. The database backend will also initialize the files.


#### modify_config
There is also a task modify_config, which takes a path available in the container, and recursively executes all the config files found there with ldapmodify on the cn=config database, that is, it uses the OLC mechanism.
The bash function called is actually the same that runs during initial creation any files found in /mnt/slapd.d-ldapmodify.d/ on the first container start, when no config was found in /etc/openldap/slapd.d .

### Run unsupported commands in the container

#### Base docker exec usage

As an example, consider an ldapsearch fpr the complete cn=config database using the local UNIX socket with the EXTERNAL authentication mechanisms

    docker exec -it openldap bash -c 'ldapsearch -Y EXTERNAL -H ldapi://%2Fvar%2Frun%2Fopenldap%2Fslapd.socket -b cn=config'

The correct path to the socket must be passed, and the command must be invoked in a subshell.

The management and startup functions in the entrypoint script use an exported environment variable $SOCKET_URL for the url-encoded path to the socket. It also exports other variables and sources function definitions from some files. You can if you want, run these setup tasks by calling /entrypoint.sh with docker exec, and then run one of 2 commands from the main function:

#### ./entrypoint.sh bash
This will just start after it does the initializing work (setting env-variables and sourcing function definitions)
Example:

    shell_on_host# docker exec -it openldap /entrypoint.sh bash
    bash-5.0# print_env
       ...
       SOCKET_URL=ldapi://%2Fvar%2Frun%2Fopenldap%2Fslapd.socket

#### ./entrypoint.sh eval
This will evaluate the command passed AFTER eval, necessary if you want to use Environment Variables you know are set in the container:

    shell_on_host# docker exec -it openldap /entrypoint.sh eval 'ldapsearch -H $SOCKET_URL -Y EXTERNAL -b cn=config'

This will work, because $SOCKET_URL is set in the container, because the container init code has run.

## Mounts
Persistence:
Mount named Volumes or bind-mounts to /etc/openldap and /var/lib/openldap
This will make the config/databases persistent.

Import:
Mount files to be used in imports ( database/config/schema ) to /mnt

Note that there are some usage patterns of this image that don't require you to persist the config, but where it is instead preferable to regenerate the same config on each container start from mounted files or environment variables.
This is especially the case when you want to change the root password from an environment variable.

## Configuration

The default is to use slapd.d. (Also called cn=config, OLC, online configuration...)
To instead use a flat slapd.conf, run the container with
  -e OLC=0
(actually, anything but 1, "true" or "yes")

Configuration using slapd.d can either be persisted (mount a volume to /etc/openldap/slapd.d )
or recreated at each container rebuilt start (Mount it to /mnt, see below ). The config in /etc/openldap/slap.d (in the container layer) will then be recreated from what is at /mnt
whenever the container is recreated (but not if its merely stopped and restarted.) This would mean that changes made using the OLC will not persist across container recreation.

Note, however that slapd.conf is meant to be deprecated in a future release of openldap (But tools exist to transform an slapd.conf flat config into an slapd.d-config)

When run with slapd.d, the container will always use an slapd.d configuration. If all else fails, it will be created from the slapd.conf that comes with the alpine package.

### slapd.d Creation

The following applies if OLC=1 is used (default)

If /etc/openldap/slapd.d exists and is not empty, the server will try to start from this config.
This only happens if a persistent volume or bind mount is mounted to /etc/openldap/slapd.d . This must be done if changes made using the OLC  must be persisted across container recreation.

If you persist the config using a volume, you cannot modify the root Password just by setting an environment variable anymore, but you can modify it using the OLC, the easiest way would be to use the entrypoint script's 'change_rootpassword' task.

The following ways to create a slapd.d are tried in order, STOPPING AT THE FIRST ONE SUCCEEDING.

1. Copy from /mnt/slapd.d
   A pre-existing slapd.d, maybe from another server can be mounted to /mnt/slapd.d, and will just be copied to /etc/openldap/slapd.d (if it does not yet exist).

2. Add with slapadd
   If /mnt/slapd.d-slapadd.ldif or /mnt/slapd.d-slapadd.j2.ldif is mounted, it will be used to add the config database using slapadd before server start.

   If /mnt/slapd.d-slapadd.j2.ldif exists, a python script using jinja2 will replace occurences of
   jinja2-variables starting with LDIF_REPLACE int the ldif with the values of environment variables mounted into the container {{ LDIF_REPLACE_ROOT_PW }}

   If both /mnt/slapd.d-slapadd.j2.ldif are mounted, slapd.d-slapadd.j2.ldif is used.

   Note that if you are using this to change the password of any database's root user (such as for the cn=config database like this:)

       dn: olcDatabase={0}config,cn=config
       olcRootPW:: {{ LDIF_REPLACE_ROOT_PW }}

   , the password passed in the environment variable needs to be both hashed AND base64-encoded, running

      slappasswd -s $PASSWORD | base64

  Openldap has some quirks there, for instance, when you modify using a similar LDIF-file and ldapmodify, the passwords needs to be HASHED, but MUST NOT be base64-encoded.
  This image tries to work around these quirks, by normally requiring you pass passwords hashed but not base64-encoded in management tasks, but the LDIF_REPLACE mechanism
  is agnostic of what you are passing into it and just replaces, so in this case the image expects the correct form.

3. Generate from base config using variables
   If variables
      - LDAP_OLC_ACCESS
      - LDAP_OLC_ROOT_DN
      - LDAP_OLC_ROOT_PW
        or
      - LDAP_OLC_ROOT_HASHED_PW
   are set, a base config is created from them.

   3.1 [WORK IN PROGRESS]
     work is in progress but not yet dome to also allow adding modules and schemas to the config using environment variables when generating slapd.d this way

4. Generate from flat config
   If no other source was found, slapd.d will be generated from a flat config file.

   This can be an existing config in /etc/openldap/slapd.conf that was used with a previous container on the same mounted directories, or can be imported, see the section slapd.d.

   Note that in the process of conversion, the directories in $DB_DATADIR for the configured databases will be created, because conversion of the config fails otherwise.


### slapd.d Modification

Ldif-files meant to modify cn=config that are found in /mnt/slapd.d-ldapmodify.d or subfolders will automatically be run right after after slapd.d was created with the any of the methods 1-4 above, that is, only if /etc/openldap/slapd.d did not contain a persistent config.

This is meant to build a complex config up from a base config in steps.

It is also useful if cn=config database is exported for a cloned testserver as an slapd.d-slapadd.ldif file, the config of which needs some modifications compared to the original.

If slapd.d is to changed afterwards, to make sure the config is rebuildable when not persisted, the ldif files should also be put into /mnt/slapd.d-ldapmodify.d.
When this is done, if slapd.d is deleted (on recreating the container or deleting a volume mounted to /etc/openldap/slad.d ), the config can be rebuilt by just starting the server.

The server will do this by again running the initial config creation method (see Methods 1 -4 above), then reapplying all the ldif files in /mnt/slapd.d-ldapmodify.d in order.

### slapd.d Update tasks
Some slapd.d Update tasks, described below in section "Simplified Management commands" can also modify the config, but they will not write out scripts to a potential /mnt/slapd.d-ldapmodify.d, so that means configuration
generated from these tasks cannot be restored the way described above.

When the a persistent volume is mounted into /etc/openldap/slapd.d, all changes will off course persist.

### slapd.conf Creation

Instead of slapd.d (cn=config, OLC, online configuration) a flat slapd.conf can be used by setting
-e OLC=0 (or any value besides 1, "true", "yes")

The disadvantage of NOT using slapd.d is that config changes cannot be apllied without restarting the server.
Also, slapd.conf will probably be deprecated by the openldap project in a future release.

( A created or mounted slapd.conf may also be used as a way to transform it into an OLC-config, when OLC=1 is set, OLC must be created and no other source for OLC exists)

If a flat config is needed, either to create an OLC config from it, or because OLC=0 and thus slapd.conf is to be used, just like with slapd.d, if /etc/openldap/slapd.conf already exists (because it was mounted), the server will use it.

If not, the following ways to create a slapd.conf are used in both scenarios. They are tried in order, stopping at the first one succeeding.

1. Copy from /mnt/slapd.conf
   Just like with slapd.d,  an existing slapd.conf, can be mounted to /mnt/slapd.d, and will be copied to /etc/ openldap/slapd.conf.

2. Install distribution default
   If no other source was found, slapd.conf as well as the schemas will be copied from /build/conf/dist, installing the distribution default from alpines openldap package.

### Schema Installation

If using slapd, schemas can be imported by having them in the initial /mnt/slapd.d-slapadd.ldif
or /mnt/slapd.d-slapadd.j2.ldif files or in a file in /mnt/slapd.d-ldapmodify.d, meaning the config will be modified by adding them.

If slapd.conf is used, or if slapd.d is created (converted) from a mounted or in-use flat config /mnt/slapd.conf or /etc/openldap/slapd.conf, the entrypoint script tries to copy the  *.schema files referenced in slapd.conf with include before conversion.

slapd.conf will be parsed to find the schemas that are needed.

Schema files that are required by slapd.conf (whether slapd.conf is used directly or converted to slapd.d) are first looked for in /mnt/schema. Put any special schema files here.

If a required schema file is not found there, it will be looked for in the distribution defaults in /build/conf/dist/schema.

### Example compose-yml
A docker-compose.yml example is included, together with a config/example folder to be mounted to /mnt to generate a /etc/openldap/slapd.d


Some common tasks were added as functions to the entrypoint script. Some use ldapmodify under the hood, these are meant to be run in the running ldap-server, using docker exec.

Others use slapadd, and are only safe to call when slapd is not running. As slapd has PID1 in containers normally started from these, these are meant to be called after stopping the container, then using 

    docker run --rm

on the same mounts/volumes as the original container.

The task names contain the tool used, so that it is clear if the server must be running or not.

## Running the complete example

First start the server to import the config and make it create the empty database:

    docker-compose up

This will mount the config in config/example, replace the root DNs password for the cn=config and dc=directory,dc=test databases with 'changeme'. It will also create a database in the bind mount in ./data
(from example.env file)

    docker-compose stop openldap

Will stop the server to then allow running slapadd

    docker-compose run --rm openldap slapadd_data -b dc=directory,dc=test -l example-data.ldif

Runs slapadd in a temporary docker container, using the mounts of the service (and thus executing the same config and adding to the database in the same bind mount). Will then terminate the container

    docker-compose start openldap

Restart the service.

Queries as both cn=admin,cn=config or cn=admin,dc=directory,dc=test should now be possible:

    ldapsearch -D "cn=admin,cn=config" -w changeme -v -H ldap:// -b "cn=config" +
    ldapsearch -D "cn=admin,dc=directory,dc=test" -w changeme -v -H ldap:// -b "dc=directory,dc=test" uid=testuser
