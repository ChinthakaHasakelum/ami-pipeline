#!/bin/bash

# ----------------------------------------------------------------------------
# Main Script for the WSO2 Products setup
# ---------------------------------------------------------------------------
# Exit on fail
set -e

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

#Update the AMI
echo "getting repository updates"
sudo apt-get update

#Install pre-required packages
echo "installing packages"
sudo apt-get install -y dc libyaml-dev ntpdate openssh-server puppet mcollective snmp zip tree vim htop ccze xfsprogs nagios-nrpe-server nagios-plugins snmpd lsof sysstat curl unzip git python3 python3-pip dc

echo "creating wso2 logs directory"
sudo mkdir -p /var/log/wso2

echo "create facters directory"
sudo mkdir -p /etc/facter/facts.d


#make file system to mkfs /dev/xvdf
sudo mkfs.xfs /dev/xvdk

sudo mount /dev/xvdk /mnt

echo "update fstab"
sudo cp /etc/fstab /etc/fstab.orig

sudo cat > fstab <<EOF
LABEL=cloudimg-rootfs	/	 ext4	defaults,discard	0 0
/dev/xvdk      /mnt    auto    defaults,nofail,comment=cloudconfig 0 2
EOF

sudo mv fstab /etc/fstab

#Configure the JAVA_HOME
echo "Downloading java"
git clone https://github.com/ChinthakaHasakelum/sample.git

mv sample java8

sudo mv java8 /opt/

sudo cat > set_java_home.sh << EOF
    #!/bin/bash
    export J2SDKDIR=/opt/java8
    export J2REDIR=/opt/java8/jre
    export JAVA_HOME=/opt/java8
    #export DERBY_HOME=/opt/java/db
    export PATH=$JAVA_HOME/bin:$J2REDIR/bin:$PATH
EOF

sudo mv set_java_home.sh /etc/profile.d/set_java_home.sh

chmod 754 /etc/profile.d/set_java_home.sh


sudo update-alternatives --install "/usr/bin/java" "java" "/opt/java8/bin/java" 1
sudo update-alternatives --install "/usr/bin/javac" "javac" "/opt/java8/bin/javac" 1


sudo update-alternatives --set java /opt/java8/bin/java
sudo update-alternatives --set javac /opt/java8/bin/javac


# create the wso2user user
echo "adding wso2user user"
sudo groupadd wso2
sudo useradd -m -r  -d /home/wso2user -G wso2 -s /bin/bash wso2user

# create the kurumba user
echo "adding kurumba user"
sudo groupadd kurumba
sudo useradd -m -r  -d /home/kurumba -g wso2 -s /bin/bash kurumba

#Adding iptable rule for block traffic 169.254.169.254 for wso2user
#sudo iptables -A OUTPUT -m owner ! --uid-owner root -d 169.254.169.254 -j DROP

#Get the JFR scripts 
sudo mkdir /root/bin
sudo mkdir -p /mnt/scripts/utils /mnt/scripts/misc

sudo chown -R 'wso2user:wso2user' /mnt/scripts

echo "Adding cron for date sync"

sudo cat > ntp-sync << EOF
    */50 * * * * /usr/sbin/ntpdate pool.ntp.org
EOF
sudo mv ntp-sync /etc/cron.d/ntp-sync
#sudo mv /tmp/ntp-sync /etc/cron.d/

#configure the ssh
sudo echo "updateing ssh configs"
sudo cat > banner << EOF
###############################################################
#                 Authorized access only!                     # 
# Disconnect IMMEDIATELY if you are not an authorized user!!! #
#         All actions Will be monitored and recorded          #
###############################################################
EOF

sudo mv banner /etc/ssh/banner
#sudo mv /tmp/banner 

sudo cat >  motd << EOF
  ____                _            _   _             
 |  _ \ _ __ ___   __| |_   _  ___| |_(_) ___  _ __  
 | |_) | __/ _ \ / _ | | | |/ __| __| |/ _ \| _ \ 
 |  __/| | | (_) | (_| | |_| | (__| |_| | (_) | | | |
 |_|   |_|  \___/ \__,_|\__,_|\___|\__|_|\___/|_| |_|

EOF
sudo mv motd /etc/motd

##change this on send AMI build since packer run fails
echo "Change ssh Port to 1984"
##sudo sed -i 's/#Port 22/Port 1984/g' /etc/ssh/sshd_config   
##sudo echo -e "\nPort 1984" >> /etc/ssh/sshd_config

echo "Change PermitRootLogin to No"
sudo sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config

echo "Change PasswordAuthentication to No"
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config

echo "chnage ssh Banner to /etc/ssh/banner"
sudo sed -i 's/#Banner.*/Banner \/etc\/ssh\/banner/g' /etc/ssh/sshd_config

echo "SSH Status:"
echo `service ssh status`

sudo cat > set_history_format.sh << EOF
    #!/bin/bash
    export HISTTIMEFORMAT="%F %T "
EOF

sudo mv set_history_format.sh /etc/profile.d/set_history_format.sh

sudo cat > cloudwatch-base.conf << EOF
    [general]
    state_file = /var/awslogs/state/agent-state
    [/var/log/syslog]
    datetime_format = %Y-%m-%d %H:%M:%S
    file = /var/log/syslog
    buffer_duration = 5000
    log_stream_name = {hostname}
    initial_position = end_of_file
    log_group_name = /var/log/syslog
EOF

# Installing CloudWatch
echo "installing awslogs agent"
sudo curl https://s3.amazonaws.com/aws-cloudwatch/downloads/latest/awslogs-agent-setup.py -O
sudo python ./awslogs-agent-setup.py --region us-east-1 --non-interactive --configfile=cloudwatch-base.conf --python=/usr/bin/python2.7

#install aws cli from bundle
echo "installing aws cli"
curl --silent "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o "/tmp/awscli-bundle.zip"
unzip -qq /tmp/awscli-bundle.zip -d /tmp
sudo python3 /tmp/awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws

# Installing rename package
sudo apt-get install rename

# puppet
echo "Remove puppet from startup"
sudo service puppet stop
sudo update-rc.d puppet disable

#copy wso2 puppet configuration files
sudo rm -rf /var/lib/puppet/

sudo cat > 95_puppet.cfg << EOF
    # This will update the puppet.conf in next reboot
    puppet:
    conf:
        agent:
        server: "puppet"
        certname: "%i.%f"
        waitforcert: "60"
        report: "true"
        environment: "production"
    
    runcmd:
    - ['update-rc.d', 'puppet', 'enable']
EOF

sudo mv 95_puppet.cfg /etc/cloud/cloud.cfg.d/95_puppet.cfg

sudo cp /etc/security/limits.conf /etc/security/limits.conf.orig
sudo cat > limits.conf << EOF
    wso2user         soft     nofile          65535
    wso2user         hard     nofile          65535
    wso2user         soft     nproc           20000
    wso2user         hard     nproc           20000
EOF

sudo mv limits.conf  /etc/security/limits.conf 

sudo mv /etc/sysctl.conf /etc/sysctl.conf.orig
sudo cat > sysctl.conf << EOF
    fs.file-max = 2097152

    net.core.rmem_default = 524288
    net.core.wmem_default = 524288
    net.core.rmem_max = 67108864
    net.core.wmem_max = 67108864

    net.ipv4.tcp_fin_timeout = 30
    net.ipv4.tcp_rmem = 4096 87380 16777216
    net.ipv4.tcp_wmem = 4096 65536 16777216
    net.ipv4.ip_local_port_range = 1024 65535
EOF

sudo mv sysctl.conf /etc/sysctl.conf

sudo cat > set_alias.sh << EOF
    #!/bin/bash
    # do not delete / or prompt if deleting more than 3 files at a time #
    alias rm='rm -I --preserve-root'
    
    # confirmation #
    alias mv='mv -i'
    alias cp='cp -i'
    alias ln='ln -i'
    
    # Parenting changing perms on / #
    alias chown='chown --preserve-root'
    alias chmod='chmod --preserve-root'
    alias chgrp='chgrp --preserve-root'

    # Creating new session with su 
    alias su='systemd-run -t /bin/su '
    alias sudo='sudo '
EOF

sudo mv set_alias.sh /etc/profile.d/set_alias.sh

sudo chmod -R 754 /etc/profile.d/

#Make puppet lib dir
sudo mkdir /var/lib/puppet
sudo chown puppet:puppet /var/lib/puppet
sudo chmod 755 /var/lib/puppet