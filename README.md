# Celiuz/Hermes Real Bootstrap

Script ini untuk VPS baru/mingguan agar tidak install dan restore manual setiap minggu.

File utama:

```bash
/root/celiuz-bootstrap/bootstrap-celiuz-vps.sh
```

## Yang dilakukan script

1. Install dependency Ubuntu/Debian:
   - `curl`, `git`, `gnupg`, `python3`, `python3-venv`, `build-essential`, `jq`, `npm`, `gh`
2. Install Node.js 22 via `n`.
3. Install CLI global:
   - `9router`
   - `@openai/codex`
   - `opencode-ai`
4. Install Visual Studio Code dari repo Microsoft.
5. Buat launcher root:
   - command `code-root`
   - desktop launcher `Visual Studio Code (Root)`
   - profile terisolasi `/root/.vscode-root`
   - otomatis pakai `--no-sandbox`
6. Install Hermes Agent kalau belum ada.
7. Ambil encrypted backup terbaru dari salah satu sumber:
   - `BACKUP_URL`
   - `BACKUP_FILE`
   - `BACKUP_DRIVE_FILE_ID`
   - `BACKUP_DRIVE_FOLDER_URL`
   - `BACKUP_DRIVE_FOLDER_ID`
8. Decrypt backup GPG.
9. Validasi archive tidak berisi path berbahaya.
10. Restore:
   - `/root/.hermes`
   - `/root/.9router`
   - `/etc/systemd/system/9router.service`
   - `/etc/systemd/system/hermes-gateway.service`
11. Perbaiki `9router.service` agar memakai binary npm terbaru (`/usr/local/bin/9router`).
12. Start/enable service:
    - `9router.service`
    - `hermes-gateway.service`
13. Verifikasi versi CLI, VS Code/code-root, 9Router health, status gateway, dan file memory Hermes.

## Cara pakai di VPS baru

Login sebagai root, lalu jalankan salah satu mode berikut.

### Mode A — backup file sudah di-upload/scp ke VPS

```bash
BACKUP_FILE='/root/hermes-backup-20260617_030000.tar.gz.gpg' \
  bash /root/celiuz-bootstrap/bootstrap-celiuz-vps.sh
```

Script akan meminta passphrase backup secara interaktif.

### Mode B — direct URL ke file `.gpg`

```bash
BACKUP_URL='https://example.com/hermes-backup-latest.tar.gz.gpg' \
  bash /root/celiuz-bootstrap/bootstrap-celiuz-vps.sh
```

### Mode C — Google Drive file ID public/shared

```bash
BACKUP_DRIVE_FILE_ID='FILE_ID' \
  bash /root/celiuz-bootstrap/bootstrap-celiuz-vps.sh
```

### Mode D — Google Drive folder public/shared berisi `hermes-backup-*.tar.gz.gpg`

```bash
BACKUP_DRIVE_FOLDER_ID='FOLDER_ID' \
  bash /root/celiuz-bootstrap/bootstrap-celiuz-vps.sh
```

atau:

```bash
BACKUP_DRIVE_FOLDER_URL='https://drive.google.com/drive/folders/FOLDER_ID' \
  bash /root/celiuz-bootstrap/bootstrap-celiuz-vps.sh
```

Script akan download folder tersebut dengan `gdown`, lalu pilih file dengan nama paling akhir secara sort:

```text
hermes-backup-*.tar.gz.gpg
```

## Passphrase

Paling aman: biarkan script prompt passphrase.

Alternatif untuk otomasi penuh:

```bash
printf '%s' 'PASSPHRASE_BACKUP_KAMU' > /root/pass.tmp
chmod 600 /root/pass.tmp
PASSPHRASE_FILE=/root/pass.tmp BACKUP_FILE=/root/hermes-backup.tar.gz.gpg \
  bash /root/celiuz-bootstrap/bootstrap-celiuz-vps.sh
rm -f /root/pass.tmp
```

Hindari menyimpan passphrase permanen di VPS mingguan.

## One-liner jika script sudah di-host di URL

Setelah script ini di-upload ke GitHub/private URL/Drive direct URL, VPS baru bisa pakai pola:

```bash
curl -fsSL 'https://URL/bootstrap-celiuz-vps.sh' -o /root/bootstrap-celiuz-vps.sh
chmod 700 /root/bootstrap-celiuz-vps.sh
BACKUP_DRIVE_FOLDER_ID='FOLDER_ID' bash /root/bootstrap-celiuz-vps.sh
```

## Output penting

Di akhir, pastikan terlihat:

```text
9router.service active
{"ok":true}
hermes-gateway.service active
Bootstrap complete
```

## VS Code root

Bootstrap Hermes sekarang juga menginstall Visual Studio Code dan membuat launcher:

```bash
code-root
```

Gunakan dari terminal root atau menu desktop **Visual Studio Code (Root)**. Launcher ini otomatis menambahkan:

```text
--no-sandbox --user-data-dir=/root/.vscode-root
```

Jadi VS Code bisa langsung jalan sebagai root tanpa perlu mengetik flag panjang.

## Rollback dan keamanan

Default `WORKDIR`:

```text
/root/hermes-bootstrap-work
```

Script menyimpan rollback archive dan staging di sana. Setelah berhasil dan sudah yakin, hapus folder ini karena bisa berisi decrypted backup:

```bash
rm -rf /root/hermes-bootstrap-work
```

## Bootstrap tambahan: XFCE + XRDP

Kalau VPS baru juga perlu desktop remote via RDP, jalankan script ini:

```bash
curl -fsSL https://raw.githubusercontent.com/BangDills/celiuz-bootstrap/main/xrdp-xfce-bootstrap.sh \
  -o /root/xrdp-xfce-bootstrap.sh && \
chmod 700 /root/xrdp-xfce-bootstrap.sh && \
bash /root/xrdp-xfce-bootstrap.sh
```

Script ini melakukan versi aman dari command manual:

```bash
apt update
apt install xfce4 xfce4-goodies dbus-x11 xrdp ufw -y
systemctl enable xrdp
echo "xfce4-session" > ~/.xsession
systemctl restart xrdp
ufw allow OpenSSH
ufw allow 3389/tcp
ufw --force enable
```

Catatan: script sengaja menjalankan `ufw allow OpenSSH` sebelum `ufw enable`, supaya koneksi SSH tidak terkunci.

Optional:

```bash
# Batasi RDP hanya dari IP tertentu
ALLOW_RDP_FROM=203.0.113.10 bash /root/xrdp-xfce-bootstrap.sh

# Jangan ubah firewall
ENABLE_UFW=false bash /root/xrdp-xfce-bootstrap.sh
```

## Catatan penting

- Agar auto-pick backup terbaru dari Google Drive mudah, sebaiknya folder Drive khusus backup hanya berisi file `hermes-backup-*.tar.gz.gpg`.
- Kalau folder Drive private, `gdown` di VPS baru tidak bisa list/download tanpa auth. Solusi paling praktis: share folder/file sebagai “Anyone with the link”. Karena backup sudah terenkripsi GPG, yang penting passphrase tetap rahasia.
- Kalau ingin private 100%, perlu mekanisme download lain seperti rclone/service account/sealed token, tapi itu menambah kompleksitas.
