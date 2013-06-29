#!/bin/bash

base_dir=$(dirname `readlink -f $0`)
app_dir=$base_dir/gitcache.org
www_dir=$base_dir/www
config_dir=$base_dir/config
human=asim
user=gitcache
group=gitcache
repo=/cache/repos/pub
www=/www/gitcache.org/html
app=/app/gitcache.org
sshd_port=61234

# software versions
git_version=1.8.1
git_dl_url=http://git-core.googlecode.com/files
nginx_version=1.2.6
nginx_dl_url=http://nginx.org/download

PATH=$PATH:/usr/sbin

remove_httpd() {
  if (rpm -q httpd)>/dev/null ;then
    /etc/init.d/httpd stop
    yum remove httpd -y
  fi
}

install_pkg() {
  if [ "$1" ];then
    local pkg=$1
    if ! (rpm -q $pkg)>/dev/null; then
      yum install $pkg -y
    fi
  fi
}

install_cron_deps() {
  for pkg in crontabs cronie; do
    install_pkg $pkg
  done
}

install_cron() {
  install_cron_deps
  
  local checksum=$(cat $config_dir/$user.crontab)

  if [ -f /var/spool/cron/$user ] &&[ `md5sum /var/spool/cron/$user|awk '{print $1}'` == "$checksum" ]; then
    return
  fi

  cp -f $config_dir/$user.crontab /var/spool/cron/$user
  chmod 600 /var/spool/cron/$user
  chown $user.$group /var/spool/cron/$user
}

install_inits() {
  rsync -avz $config_dir/init/ /etc/init/
}

install_ip6tables_deps() {
  for pkg in iptables-ipv6; do
    install_pkg $pkg
  done
}

install_ip6tables() {
  if (grep 'IPV6="yes"' /etc/sysconfig/network)>/dev/null; then
    install_ip6tables_deps

    local checksum=$(md5sum $config_dir/ip6tables |awk '{print $1}')

    if [  -f /etc/sysconfig/ip6tables ] && [ `md5sum /etc/sysconfig/ip6tables|awk '{print $1}'` == "$checksum" ]; then
      return
    fi

    cp -f $config_dir/ip6tables /etc/sysconfig/ip6tables
  fi
}

install_iptables_deps() {
  for pkg in iptables policycoreutils; do
    install_pkg $pkg
  done
}

install_iptables() {
  install_iptables_deps

  local checksum=$(md5sum $config_dir/iptables |awk '{print $1}')

  if [  -f /etc/sysconfig/iptables ] && [ `md5sum /etc/sysconfig/iptables|awk '{print $1}'` == "$checksum" ]; then
    return
  fi

  cp -f $config_dir/iptables /etc/sysconfig/iptables
}

install_repos_bin() {
  if [ ! -f $app_dir/bin/repos ]; then
    echo "creating binary $app/bin/repos"
    /usr/local/go/bin/go build -o $app/bin/repos $app_dir/bin/repos.go
  fi
}

install_git_backend() {
  if [ ! -f /usr/local/bin/git-http-backend ]; then
    echo "creating binary /usr/local/bin/git-http-backend"
    /usr/local/go/bin/go build -o /usr/local/bin/git-http-backend $app_dir/bin/git-http-backend.go
  fi
}

install_git_deps() {
  for pkg in perl-ExtUtils-MakeMaker gcc curl-devel expat-devel \
  gettext-devel openssl-devel zlib-devel; do
    install_pkg $pkg
  done
}

install_git() {
  install_git_deps

  if ! (which git)&>/dev/null; then
    local git_pkg=git-$git_version

    pushd /tmp >/dev/null
    curl -L $git_dl_url/$git_pkg.tar.gz | tar zx
    pushd $git_pkg >/dev/null
    make prefix=/usr/local all
    make prefix=/usr/local install
    popd >/dev/null
    rm -rf $git_pkg $git_pkg.tar.gz
    popd >/dev/null
  fi 
}

install_go() {
  if [ ! -f /usr/local/go/bin/go ]; then
    echo "installing go 1.0.3"
    pushd /usr/local >/dev/null
    curl -L https://go.googlecode.com/files/go1.0.3.linux-386.tar.gz | tar zx
    popd >/dev/null
  fi
}

install_nginx_deps() {
  for pkg in pcre pcre-devel openssl openssl-devel zlib zlib-devel; do
    install_pkg $pkg
  done
}

install_nginx() {
  install_nginx_deps
    
  local nginx_pkg=nginx-$nginx_version

  if [ ! -f /usr/local/$nginx_pkg/sbin/nginx ]; then
    echo "installing nginx $nginx_version"
    pushd /tmp >/dev/null
    curl -L $nginx_dl_url/$nginx_pkg.tar.gz | tar zx
    pushd $nginx_pkg >/dev/null

    # replace version stuff
    sed -i 's/"Server: nginx"/"Server: cache"/g' src/http/ngx_http_header_filter_module.c
    sed -i "s/\"$nginx_version\"/\"0.0\"/g" src/core/nginx.h
    sed -i 's/"nginx\/" NGINX_VERSION/"cache\/" NGINX_VERSION/g' src/core/nginx.h

    ./configure --prefix=/usr/local/$nginx_pkg --with-http_ssl_module \
    --with-http_stub_status_module
    make && make install
    popd >/dev/null
    rm -rf $nginx_pkg $nginx_pkg.tar.gz
    popd >/dev/null
  fi  

  if [ ! -L /usr/local/nginx ]; then
    echo "create link /usr/local/$nginx_pkg => /usr/local/nginx"
    ln -s /usr/local/$nginx_pkg /usr/local/nginx
  fi

  if [ ! -f /etc/init.d/nginx ]; then
    echo "adding nginx init.d"
    cp $config_dir/nginx.init /etc/init.d/nginx
    chmod +x /etc/init.d/nginx
  fi

  echo "syncing nginx configs"
  rsync -avz $config_dir/nginx_conf/ /usr/local/$nginx_pkg/conf/
}

install_ntp() {
  yum install ntp ntpdate -y
  if [ ! -f /var/run/ntpd.pid ]; then
    /usr/sbin/ntpdate 0.centos.pool.ntp.org
    /etc/init.d/ntpd start 
  fi
}

add_human() {
  if ! (grep "^$human:" /etc/passwd)>/dev/null; then
    echo "adding user $human"
    useradd -g users $human
  fi
}

add_user() {
  if ! (grep "^$group:" /etc/group)>/dev/null; then
    echo "adding group $group"
    groupadd $group
  fi

  if ! (grep "^$user:" /etc/passwd)>/dev/null; then
    echo "adding user $user"
    useradd -g $group $user
  fi
}

add_app() {
  if [ ! -d $app ]; then
    echo "creating dir $app"
    mkdir -m 755 -p "$app"
    if [ -d $app_dir ]; then
      echo "syncing $app"
      rsync -avz $app_dir/ $app/
    fi
  fi

  rsync -avz $app_dir/bin/ $app/bin/
  rsync -avz $app_dir/scripts/ $app/scripts/
  chown -R $user.$group $app
}

add_repo() {
  if [ ! -d $repo ]; then
    echo "creating repo $repo"
    mkdir -m 755 -p $repo
    chown -R $user.$group $repo
  fi
}

add_www() {
  if [ ! -d $www ]; then
    echo "creating www $www"
    mkdir -m 755 -p $www

  fi
    
  if [ -d $www_dir ]; then
    echo "syncing www $www"
    rsync -avz $www_dir/ $www/
  fi

  chown -R $user.$group $www
}

change_sshd_port() {
  if ! (grep "^Port $sshd_port" /etc/ssh/sshd_config)>/dev/null; then
    echo "changing sshd port to $sshd_port"
    sed -i "s/^#Port 22/Port $sshd_port/g" /etc/ssh/sshd_config
    /etc/init.d/sshd restart
  fi
}

check_root_login() {
  if ! (grep "^PermitRootLogin no" /etc/ssh/sshd_config)>/dev/null; then
     echo "Disable ssh root login!"
  fi
}

check_human_ssh() {
  if [ ! -f /home/$human/.ssh/authorized_keys ]; then
    echo "Add ssh key for $human!"
  fi
}

main() {
  remove_httpd

  add_user
  add_human
  add_app
  add_repo
  add_www
  change_sshd_port

  # installs
  install_iptables
  install_ip6tables
  install_git
  install_go
  install_nginx
  install_cron
  install_inits
  install_git_backend
  install_repos_bin
  check_root_login
  check_human_ssh
}

case "$1" in
  create)
  main
  ;;
  *)
  echo "$0 create"
  exit 1
  ;;
esac

exit $?
