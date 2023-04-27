#!/bin/bash

#Check if the system is Ubuntu or Debian
if [ "$(uname -s)" != "Linux" ] || ! command -v lsb_release >/dev/null 2>&1; then
echo "This script only supports Ubuntu and Debian systems."
exit 1
fi

if [ "$(lsb_release -si)" != "Ubuntu" ] && [ "$(lsb_release -si)" != "Debian" ]; then
echo "This script only supports Ubuntu and Debian systems."
exit 1
fi

function uninstall_apache2 {
    echo -e "\n停止Apache2服务。"
    systemctl stop apache2
    echo -e "\n禁止Apache2服务自动启动。"
    systemctl disable apache2
    echo -e "\n强制杀死apache2的进程，终止所有 Apache2 进程并关闭 Apache2 服务"
    pkill -9 apache2
    echo -e "\n卸载Apache2及其相关组件。"
    apt-get --purge remove apache2* libapache2* -y
    echo -e "\n删除Apache2.2-common软件包，并在卸载时自动清除相关配置文件。"
    apt-get --purge remove apache2.2-common
    echo -e "\n自动删除不再需要的依赖软件包，以释放磁盘空间。"
    apt-get autoremove -y
    echo -e "\n删除所有包含 'apache' 的文件和目录。"
    find /etc -name "*apache*" -exec rm -rf {} \;
    echo -e "\n删除Apache2的默认网站目录。"
    sudo rm -rf /var/www
    echo -e "\n删除Apache2的JK模块。"
    rm -rf /etc/libapache2-mod-jk
    echo -e "\n删除无用的apt源。"
    rm -f /etc/apt/sources.list.d/ct-preset.lis
}

echo -n "是否需要卸载 Apache2？(y/n，默认5秒后自动选择卸载): "
for i in $(seq 5 -1 1); do
  echo -n "$i "
  sleep 1
done
echo

read -t 5 -n 1 -r input
echo

if [[ $input =~ ^[Yy]$ ]] || [[ $input == $'\n' ]];
then
  echo "手动确认卸载 Apache2相关"
  uninstall_apache2
elif [[ $input == "" ]];
then
  # 倒计时结束后无人操作
  echo -e "\n倒计时结束，自动选择卸载 Apache2"
  uninstall_apache2
else
  echo -e "\n已取消卸载 Apache2"
fi
if [[ $input =~ ^[Nn]$ ]]
then
  echo -e "\n已取消卸载 Apache2"
fi




echo -e "\n将IPv6 DNS服务器添加到resolv.conf文件。"
ip -4 addr show | grep -oP '(?<=inet\s)\d+(.\d+){3}' | while read ip; do echo "nameserver 8.8.8.8"; done > /etc/resolv.conf

ip -6 addr show | grep -oP '(?<=inet6\s)[a-f0-9.:]+(?=/)' | while read ip; do echo "nameserver 2a01:4f8:c2c:123f::1"; done >> /etc/resolv.conf

echo -e "\n更新apt包列表。"
apt update
echo -e "\n安装curl..."
apt install curl -y
echo -e "\n安装bash..."
apt install bash -y


echo -e "\n从GitLab下载CFwarp脚本并执行，该脚本用于开启CloudFlare WARP隧道。"
wget -N https://gitlab.com/Misaka-blog/warp-script/-/raw/main/warp.sh && bash warp.sh

# 定义选项数组
options=("原版 x-ui" "MHSanaei 3x-ui" "vaxilu x-ui" "Misaka x-ui" "退出当前并继续")

while true; do
  # 选择安装版本
  echo "请选择要安装的x-ui面板版本："
  select option in "${options[@]}"; do
    case $option in
    "原版 x-ui")
      cmd=${install_cmds[0]}
      break
      ;;
    "MHSanaei 3x-ui")
      cmd=${install_cmds[1]}
      break
      ;;
    "vaxilu x-ui")
      cmd=${install_cmds[2]}
      break
      ;;
    "Misaka x-ui")
      cmd=${install_cmds[3]}
      break
      ;;
    "退出当前并继续")
      break
      ;;
    *)
      echo "无效的选择，请输入1-5的数字."
      ;;
    esac
  done

  if [ "$option" == "退出当前并继续" ]; then
    break
  else
    # 运行命令进行安装
    echo "即将运行以下安装命令："
    echo "$cmd"
    echo -e "\n请等待安装程序运行完成...\n"
    sleep 1
    eval "$cmd"

    # 询问是否重新运行安装程序
    read -p "安装完成，是否需要重新安装x-ui面板？(y/n):" reinstall
    if [ "$reinstall" != "y" ]; then
      break
    fi
  fi
done


echo "接下来继续..."




# 提示用户选择是否重装 Nginx
echo  "建议重装 Nginx"
read -t 5 -p "是否需要重装 Nginx？(y/n，默认5秒后自动选择重装): " -n 1 -r reinstall_nginx
echo ""
if [[ $reinstall_nginx =~ ^[Yy]$ ]]
then
   echo "开始卸载并重装 Nginx..."
   systemctl stop nginx
   pkill -9 nginx
   apt purge -y nginx
   apt install -y nginx
fi

echo -e "\n安装 acme 脚本，如有红色报错可忽略"
curl https://get.acme.sh | sh
ln -s  /root/.acme.sh/acme.sh /usr/local/bin/acme.sh
acme.sh --set-default-ca --server letsencrypt
echo -e "\n配置证书"

read -p "请输入您的域名： " DOMAIN

acme.sh --issue -d $DOMAIN -k ec-256 --webroot  /var/www/html

echo -e "\n acme...解析域名"
acme.sh --install-cert -d $DOMAIN  
		--ecc 
		--key-file  /etc/x-ui/server.key  
		--fullchain-file /etc/x-ui/server.crt 
		--reloadcmd     "systemctl force-reload nginx"

echo -e "\n备份nginx默认配置项"
sudo mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
echo -e "\n添加nginx默认配置"


read -p "输入分流路径/UUID: " SHUNT

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
       ssl_certificate       /etc/x-ui/server.crt;  #证书位置
       ssl_certificate_key   /etc/x-ui/server.key; #私钥位置
      
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
           sub_filter \"clr2.wfhtony.space\" \$server_name;
           proxy_set_header Host \"clr2.wfhtony.space\";
           proxy_set_header Referer \$http_referer;
           proxy_set_header X-Real-IP \$remote_addr;
           proxy_set_header User-Agent \$http_user_agent;
           proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
           proxy_set_header X-Forwarded-Proto https;
           proxy_set_header Accept-Encoding \"\";
           proxy_set_header Accept-Language \"zh-CN\";
       }


       location /$SHUNT {   #分流路径
           proxy_redirect off;
           proxy_pass http://127.0.0.1:10000; #Xray端口
           proxy_http_version 1.1;
           proxy_set_header Upgrade \$http_upgrade;
           proxy_set_header Connection \"upgrade\";
           proxy_set_header Host \$host;
           proxy_set_header X-Real-IP \$remote_addr;
           proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
       }
      
       location /$SHUNT-xui {   #xui路径
           proxy_redirect off;
           proxy_pass http://127.0.0.1:4499;  #xui监听端口
           proxy_http_version 1.1;
           proxy_set_header Host \$host;
       }
   }

   server {
       listen 80;
       location /.well-known/ {
              root /var/www/html;
           }
       location / {
               rewrite ^(.*)$ https://\$host\$1 permanent;
           }
   }
}



" >/etc/nginx/nginx.conf







echo -e "\n重启nginx加载新配置"
systemctl reload nginx
echo -e "\n重启nginx服务"
systemctl restart nginx.service


ipv4addr=$(curl -4 -s ip.sb)
ipv6addr=$(curl -6 -s ip.sb)

if [[ -z $ipv4addr ]] && [[ ! -z $ipv6addr ]];
then
    echo "当前环境为 IPv6 Only"
    echo "添加 IPv6 映射地址"
    echo "2606:4700:3033::6815:1b55 clr2.wfhtony.space" >> /etc/hosts
else
    echo "当前环境为 IPv4 或 IPv4/IPv6 双栈"
fi


echo -e "\n安装防火墙"
apt install ufw -y
echo -e "\n启动防火墙"
ufw enable -y

read -p "输入VPS端口: " PORT

echo -e "\n防火墙$PORT端口开放"
ufw allow $PORT/tcp
echo -e "\n防火墙80端口开放"
ufw allow 80
echo -e "\n防火墙443端口开放"
ufw allow 443

echo -e "\n搭建完成！！！可以愉快的玩耍了！！！"
