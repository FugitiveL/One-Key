#/bin/sh

echo -e "\n停止apache2服务"
service apache2 stop
echo -e "\n禁用apache2服务"
systemctl disable apache2
echo -e "\n删除apache2相关1..."
apt-get --purge remove apache2.2 apache2-doc apache2-utils -y
echo -e "\n删除apache2相关2..."
apt-get --purge remove apache2.2-common
echo -e "\n移除孤儿软件包"
apt-get autoremove
echo -e "\n删除残留的apache文件"
find /etc -name "*apache*" -exec rm -rf {} \;
echo -e "\n删除apache静态资源文件"
sudo rm -rf /var/www
echo -e "\n删除libapache2-mod-jk"
rm -rf /etc/libapache2-mod-jk
echo -e "\n删除ct-preset.list源"
rm -f /etc/apt/sources.list.d/ct-preset.list
echo -e "\n添加nameserver到resolv.conf"
echo -e "nameserver 2a01:4f8:c2c:123f::1" >/etc/resolv.conf

echo -e "\napt 更新..."
apt update

echo -e "\n安装curl..."
apt install curl -y
echo -e "\n安装bash"
apt install bash -y

echo -e "\n远端安装 CFwarp..."
wget -N --no-check-certificate https://gitlab.com/rwkgyg/CFwarp/raw/main/CFwarp.sh && bash CFwarp.sh
echo -e "\n远端安装 x-ui..."
wget -N https://gitlab.com/rwkgyg/x-ui-yg/raw/main/install.sh && bash install.sh

echo -e "\n安装nginx服务器"
apt install nginx -y

echo -e "\n acme...如有红色报错可忽略"
curl https://get.acme.sh | sh
acme.sh --set-default-ca --server letsencrypt
echo -e "\n acme...改解析域名"
echo -n "输入你的域名: "
read DOMAIN
acme.sh --issue -d $DOMAIN -k ec-256 --webroot /var/www/html
echo -e "\n acme...解析域名"
acme.sh --install-cert -d $DOMAIN --ecc --key-file /etc/x-ui-yg/server.key --fullchain-file /etc/x-uiiyg/server.crt --reloadcmd "systemctl force-reload nginx"

echo -e "\n备份nginx默认配置项"
sudo mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
echo -e "\n添加nginx默认配置"

echo -n "输入分流路径: "
read SHUNT

echo "user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
   worker_connections 1024;
}

http {
   sendfile on;
   tcp_nopush on;
   tcp_nodelay on;
   keepalive_timeout 65;
   types_hash_max_size 2048;

   include /etc/nginx/mime.types;
   default_type application/octet-stream;
   gzip on;

   server {
       listen 443 ssl;
       listen [::]:443 ssl;

       server_name $DOMAIN;  #你的域名
       ssl_certificate       /etc/x-ui-yg/server.crt;  #证书位置
       ssl_certificate_key   /etc/x-ui-yg/server.key; #私钥位置

       ssl_session_timeout 1d;
       ssl_session_cache shared:MozSSL:10m;
       ssl_session_tickets off;
       ssl_protocols    TLSv1.2 TLSv1.3;
       ssl_prefer_server_ciphers off;

       location / {
           proxy_pass https://clr2.wfhtony.space/; #伪装网址
           proxy_redirect off;
           proxy_ssl_server_name on;
           sub_filter_once off;
           sub_filter "clr2.wfhtony.space" $server_name;
           proxy_set_header Host "clr2.wfhtony.space";
           proxy_set_header Referer $http_referer;
           proxy_set_header X-Real-IP $remote_addr;
           proxy_set_header User-Agent $http_user_agent;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
           proxy_set_header X-Forwarded-Proto https;
           proxy_set_header Accept-Encoding "";
           proxy_set_header Accept-Language "zh-CN";
       }

       location /$SHUNT {   #分流路径
           proxy_redirect off;
           proxy_pass http://127.0.0.1:10000; #Xray端口
           proxy_http_version 1.1;
           proxy_set_header Upgrade $http_upgrade;
           proxy_set_header Connection "upgrade";
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
       }

       location /$SHUNT-xui {   #xui路径
           proxy_redirect off;
           proxy_pass http://127.0.0.1:4499;  #xui监听端口
           proxy_http_version 1.1;
           proxy_set_header Host $host;
       }
   }

   server {
       listen 80;
       location /.well-known/ {
            root /var/www/html;
        }
       location / {
            rewrite ^(.*)$ https://$host$1 permanent;
        }
   }
}
" >/etc/nginx/nginx.conf

echo -e "\n重启nginx加载新配置"
systemctl reload nginx
echo -e "\n重启nginx服务"
systemctl restart nginx.service

echo -e "\n添加hosts"
echo "2606:4700:3033::6815:1b55 clr2.wfhtony.space" >>/etc/hosts

echo -e "\n安装防火墙"
apt install ufw -y
echo -e "\n启动防火墙"
ufw enable -y
echo -e "\n防火墙22端口开放"
ufw allow 22/tcp
echo -e "\n防火墙80端口开放"
ufw allow 80
echo -e "\n防火墙443端口开放"
ufw allow 443

echo -e "\n搭建完成!!!"
