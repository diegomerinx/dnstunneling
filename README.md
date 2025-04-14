# dnstunneling
## Requirements
### Client
```console
sudo apt install -y iodine
```
### Server
```console
sudo apt install -y iodine iptables sysctl
```
### Access Point
```console
sudo apt install -y hostapd dnsmasq apache2 php php-cgi iptables openssl
```
## Usage
### Client
```console
cd Client
./client.sh
```
### Server
```console
cd Server
./server.sh
```
### Access Point
```console
cd AccessPoint
./accessPoint.sh
```
