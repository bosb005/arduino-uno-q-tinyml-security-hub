# Wi-Fi setup and deployment

## Configure Wi-Fi

### Option 1: NetworkManager
If the Linux image uses NetworkManager, scan and connect with:

```bash
nmcli device wifi list
nmcli device wifi connect "YOUR_SSID" password "YOUR_PASSWORD"
```

To confirm the connection:

```bash
nmcli connection show --active
```

### Option 2: wpa_supplicant
If NetworkManager is not available, create a `wpa_supplicant.conf` entry and bring the interface up manually:

```bash
wpa_passphrase "YOUR_SSID" "YOUR_PASSWORD" | sudo tee /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
sudo wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
sudo dhclient wlan0
```

On OpenWRT-style systems, adapt the wireless interface name if it differs from `wlan0`.

## Find the board IP address
Use either of these commands after Wi-Fi is up:

```bash
ip addr show
hostname -I
```

Then open `http://BOARD_IP:5000/` from a phone or laptop on the same network.

## Install Python dependencies
From the dashboard directory:

```bash
pip3 install -r requirements.txt
```

## Run manually

```bash
python3 app.py
```

The Flask server listens on `0.0.0.0:5000` and reads MCU events from `/dev/ttyS1` by default.

Optional environment overrides:

```bash
export SERIAL_PORT=/dev/ttyS1
export SERIAL_BAUD=115200
python3 app.py
```

## Auto-start on boot
1. Copy `security_hub.service` to systemd:

   ```bash
   sudo cp security_hub.service /etc/systemd/system/security_hub.service
   ```

2. Adjust `WorkingDirectory` and `ExecStart` in the service file if the dashboard is installed elsewhere.
3. Enable and start the service:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable security_hub.service
   sudo systemctl start security_hub.service
   ```

4. Check service health:

   ```bash
   sudo systemctl status security_hub.service
   journalctl -u security_hub.service -f
   ```

If the target system does not use systemd, use the same `python3 app.py` command in the platform's equivalent init system.
