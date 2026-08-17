# Upload data
To upload data (specifically, large amounts of wav data) to the cloud storage, do:

## SSH Configuration
Create a SSH configuration on your local machine, put it in a file called `~/.ssh/config`

If a direct SSH connection is possible, add this to the config file:
```
Host NAME-OF-CONFIG
    HostName IP_ADDRESS-OF-CLOUD_STORAGE
    User YOUR-USERNAME
    IdentityFile LOCAL-PATH-TO-YOUR-SSH-KEY
    ProxyJump NAME-OF-REVERSE-PROXY-CONFIGURATION
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

If using a reverse proxy, do this:
```
Host NAME-OF-REVERSE-PROXY-CONFIGURATION
    HostName IP-ADDRESS-OF-PROXY
    AddKeysToAgent yes
    IdentityFile LOCAL-PATH-TO-YOUR-SSH-KEY
    User YOUR-USERNAME

Host NAME-OF-CONFIG
    HostName IP_ADDRESS-OF-CLOUD_STORAGE
    User YOUR-USERNAME
    IdentityFile LOCAL-PATH-TO-YOUR-SSH-KEY
    ProxyJump NAME-OF-REVERSE-PROXY-CONFIGURATION
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

## RClone configuration

Install rclone from https://rclone.org/

Create a rclone configuration for the remote cloud storage, put it  in the file `~/.config/rclone/rclone.conf` on your local machine:

```
[s3]
type = s3
provider = Other
access_key_id = GET-THIS-FROM-YOUR-ADMIN
secret_access_key = GET-THIS-FROM-YOUR-ADMIN
endpoint = https://URL-OF-THE-SERVICE:PORT
acl = public-read
```

## Transfer data
Start rclone `rclone rcd --rc-web-gui --log-file=/var/log/rclone.log`

You can then mount the s3 bucket in the config using the mount page in the GUI. After the bucket is mounted on your machine, you can use the file manager to transfer files, as if it were a local drive.

Rclone will check for failed transfers and retry. These checks and retries can be configured on the mount page in the GUI.
