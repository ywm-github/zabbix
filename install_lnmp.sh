#!/bin/bash

yum_libs(){
echo '----------------------检测依赖包安装状态---------------------------'
libs='gcc pcre pcre-devel libxml2 libxml2-devel gd gd-devel libaio '
installd=0
for i in $libs;do
   ready_install=$(($ready_install+1))
   count=`rpm -qa $i|wc -l`
   if [ $count -eq 0 ] ;then
    echo "$i 未安装，开始安装$i"
    yum install -y $i >/dev/null 2>&1
   else
    echo "$i已安装"
   fi
    is_install=`rpm -qa $i |wc -l `
    installd=$(($is_install+$installd))
done
if [ $installd -lt $ready_install ];then
  echo "需要安装的依赖包数量:$ready_install"
  echo "已经安装的依赖包数量:$installd"
  echo "依赖包未全部安装,请检查网络状态后，重新运行脚本$0"
  exit 1  
else     
   echo "依赖包已全部安装"
fi

}

create_user(){
id www-data >/dev/null 2>&1
[ $? -eq 1 ]&& useradd -U www-data -s /bin/nologin
id mysql >/dev/null 2>&1
[ $? -eq 1 ]&& useradd -U mysql -s /bin/nologin
}

install_nginx()
{
echo '----------------------安装nginx-1.14.0-----------------------------'
cd $basepath/source
echo '开始解压安装包'
tar -xf nginx-1.14.0.tar.gz
cd nginx-1.14.0
echo 'configure nginx'
./configure \
--prefix=/usr/local/nginx \
--user=www-data \
--sbin-path=/usr/local/nginx/nginx \
--conf-path=/usr/local/nginx/nginx.conf \
--pid-path=/usr/local/nginx/nginx.pid  >/dev/null 2>&1
echo 'make nginx'
make >/dev/null 2>&1
echo 'make install nginx'
make install >/dev/null 2>&1
echo "开始写入nginx配置文件"
mkdir /usr/local/nginx/conf.d
sed -i 35,79d /usr/local/nginx/nginx.conf
sed -i 'N;18a\    include conf.d/*.conf;' /usr/local/nginx/nginx.conf
cat >/usr/local/nginx/conf.d/default.conf <<EOF
server {
        listen       80;
        server_name  localhost;

location / {
            root   html;
            index  index.php index.html index.htm;
        }

        #error_page  404              /404.html;

        # redirect server error pages to the static page /50x.html
        #
        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   html;
        }
location ~* \.php$ { 
    fastcgi_index   index.php;
    fastcgi_pass    127.0.0.1:9000;
    include         fastcgi_params;
    fastcgi_param   SCRIPT_FILENAME    \$document_root\$fastcgi_script_name;
    fastcgi_param   SCRIPT_NAME        \$fastcgi_script_name;
}
}            
EOF
[ ! -f "/usr/local/bin/nginx" ]&&ln -s /usr/local/nginx/nginx /usr/local/bin
nginx 
[ $? -eq 0 ]&& echo 'nginx 启动成功'
echo '设置nginx开机自启动'
[ `grep nginx /etc/rc.local |wc -l`  -eq 0 ]&& echo '/usr/local/bin/nginx' >>/etc/rc.local

}

install_php() {
echo '----------------------开始安装 php5.6.37---------------------------'
cd $basepath/source
tar xf php-5.6.37.tar.gz
cd php-5.6.37
echo 'configure php-fpm'
echo '清理缓存中...'
#   make clean all  >dev/null 2>&1
./configure  \
--prefix=/usr/local/php  \
--with-config-file-path=/usr/local/php \
--enable-fpm  \
--enable-mbstring \
--with-fpm-user=www-data \
--enable-bcmath  \
--enable-sockets  \
--with-png-dir  \
--with-freetype-dir \
--with-jpeg-dir \
--with-gd \
--enable-mysqlnd \
--with-mysqli=mysqlnd \
--with-gettext \
--with-pdo-mysql=mysqlnd  >/dev/null 2>&1

echo "php-fpm make "
cp -frp /usr/lib64/libldap* /usr/lib/
make  >/dev/null 2>&1 
echo "php-fpm make install"
make install >/dev/null 2>&1
echo '开始修改配置文件'
[ ! -f "/usr/local/php/php.ini" ]&&cp php.ini-development /usr/local/php/php.ini
cp /usr/local/php/etc/php-fpm.conf.default /usr/local/php/etc/php-fpm.conf
ln -s  /usr/local/php/sbin/php-fpm /usr/local/bin
sed -i s/';cgi.fix_pathinfo=1'/'cgi.fix_pathinfo=0'/g /usr/local/php/php.ini
sed -i s/'post_max_size = 8M'/'post_max_size = 16M'/g  /usr/local/php/php.ini
sed -i s/'max_input_time = 60'/'max_input_time = 300'/g /usr/local/php/php.ini
sed -i s/';always_populate_raw_post_data = -1'/'always_populate_raw_post_data = -1'/g /usr/local/php/php.ini
sed -i s/'max_execution_time = 30'/'max_execution_time = 300'/g  /usr/local/php/php.ini
sed -i s/';date.timezone ='/'date.timezone = Asia\/shanghai'/g /usr/local/php/php.ini	
echo "<?php phpinfo(); ?>" >> /usr/local/nginx/html/index.php
php-fpm
[ $? -eq 0 ]&& echo 'php-fpm启动成功'
echo '设置php-fpm开机自启'
[ `grep php-fpm /etc/rc.local |wc -l`  -eq 0 ]&& echo '/usr/local/bin/php-fpm' >>/etc/rc.local
}


install_mysql(){
cd $basepath/source
echo ''
echo '----------------------开始安装mysql--------------------------------'
echo '开始解压mysql安装包'
tar -xf mysql-5.7.23-linux-glibc2.12-x86_64.tar.gz
echo '开始拷贝mysql安装文件到/usr/local/mysql'
mv mysql-5.7.23-linux-glibc2.12-x86_64 /usr/local/mysql
echo '拷贝配置文件'
\cp  -f ../conf/my.cnf /etc/
cd /usr/local/mysql
echo '初始化mysql'
#初始化mysql
bin/mysqld --initialize-insecure --user=mysql --basedir=/usr/local/mysql/ --datadir=/usr/local/mysql/data/ 
cp bin/mysql /usr/local/bin  >/dev/null 2>&1
/usr/local/mysql/bin/mysqld --user=mysql & 
sleep 3
[  `ps -ef | grep mysql |wc -l` -ne 0  ] && echo 'mysql 启动成功' 
#修改root密码
echo '修改root密码为‘new_password’'
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'new_password';"
#设置开机自启动
echo '设置mysql开机启动'
[ `grep mysql /etc/rc.local |wc -l`  -eq 0 ]&& echo 'nohup /usr/local/mysql/bin/mysqld --user=mysql &' >>/etc/rc.local
}


install_zabbix(){
cd $basepath/source
tar -xf zabbix-3.4.12.tar.gz
if [ ! -d "/usr/local/nginx/html/zabbix" ];then
    echo '----------------------开始安装zabbix-------------------------------'
    mkdir /usr/local/nginx/html/zabbix
    cp -ra zabbix-3.4.12/frontends/php/* /usr/local/nginx/html/zabbix
    echo '新建数据库zabbix'
    mysql -uroot -pnew_password -e "create database zabbix;"  >/dev/null 2>&1
    echo '创建为数据库zabbix创建用户:zabbix  密码:Zabbix_mysql1 ,并授权远程登录'
    mysql -uroot -pnew_password -e "grant all privileges on zabbix.* to zabbix@'%' identified by 'Zabbix_mysql1' with grant option;flush privileges;"   >/dev/null 2>&1
    cd zabbix-3.4.12/database/mysql
    echo '开始导入zabbix数据库'
    mysql -uzabbix -pZabbix_mysql1 zabbix <schema.sql   >/dev/null 2>&1
    mysql -uzabbix -pZabbix_mysql1 zabbix <images.sql   >/dev/null 2>&1
    mysql -uzabbix -pZabbix_mysql1 zabbix <data.sql     >/dev/null 2>&1
    ipaddr=`ip a |grep inet|grep -v inet6|grep -v 127.0.0.1|awk '{print $2}'|awk -F / '{print "http://"$1"/zabbix"}'`
    echo "zabbix 部署完成,可用以下地址访问:"
    echo $ipaddr
    echo '默认账号:Admin 密码:zabbix'
else
    echo '-----zabbix安装目录:/usr/local/nginx/html/zabbix已存在,跳过安装-----'
fi

}

firewall(){
echo '----------------------开始配置防火墙------------------------------' 
ports='80 3306'   
for port in $ports;do
echo "开始添加$port"
firewall-cmd --add-port=$port/tcp --permanent
done
echo '重新加载防火墙配置'
firewall-cmd --reload
}


main(){
clear
basepath=$(cd `dirname $0`; pwd)
yum_libs    
create_user
install_lists="nginx php mysql zabbix "
for app in $install_lists;do
    if [ -d "/usr/local/${app}" ];then
        echo '-------------------------------------------------------------------'
        echo "$app 安装目录:/usr/local/$app 已存在，跳过安装"
    else
        install_$app
    fi
done
firewall
}

main
