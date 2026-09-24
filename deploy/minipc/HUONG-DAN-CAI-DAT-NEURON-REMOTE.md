# Hướng dẫn cài Neuron Remote Edge trên mini PC/CM4

Tài liệu này dùng cho bộ cài Docker `neuron-minipc-bundle-<phiên-bản>.tar.gz`. Bộ cài chạy ba dịch vụ:

- **Neuron + Dashboard**: thu thập dữ liệu công nghiệp và giao diện web.
- **Remote backend/GatewayAgent**: tạo kết nối WebSocket đi ra ngoài tới máy chủ điều khiển.
- **Edge proxy**: cung cấp Dashboard và API remote trên cùng một địa chỉ.

> **Phạm vi an toàn:** phần Remote Control trong repo hiện là bản skeleton/pilot. REST API của remote backend và remote server chưa có lớp xác thực độc lập; `mtls`/`mtls_hmac` chưa phải triển khai mTLS hoàn chỉnh end-to-end. Chỉ dùng trong mạng thử nghiệm hoặc sau VPN/firewall. Không công khai trực tiếp lên Internet.

> **Thành phần không nằm trong bundle:** gói cài này chỉ cài phía gateway/mini PC. Bạn phải có sẵn một control server tương thích tại URL `wss://.../reverse-channel`; mã demo tham khảo nằm trong `scripts/neuron-remote-control/remote-server` của repo.

## 1. Yêu cầu

- Mini PC/CM4 chạy Linux 64-bit, đúng kiến trúc ghi trong `BUNDLE-MANIFEST.txt` (thường là `linux/arm64`).
- Khuyến nghị RAM từ 2 GB, dung lượng trống từ 4 GB.
- Docker Engine và Docker Compose v2.
- Cổng vào `80/tcp` từ mạng quản trị; kết nối đi ra tới `wss://<control-server>/reverse-channel`.
- Nếu máy chưa có Docker, installer có thể tải Docker từ `get.docker.com`; vì vậy cài hoàn toàn air-gapped cần cài Docker trước.

## 2. Chép và kiểm tra bộ cài

Từ máy quản trị:

```bash
scp neuron-minipc-bundle-<phiên-bản>.tar.gz user@IP_MINIPC:~/
scp neuron-minipc-bundle-<phiên-bản>.tar.gz.sha256 user@IP_MINIPC:~/
```

Trên mini PC:

```bash
cd ~
sha256sum -c neuron-minipc-bundle-<phiên-bản>.tar.gz.sha256
tar -xzf neuron-minipc-bundle-<phiên-bản>.tar.gz
cd neuron-minipc-bundle-<phiên-bản>
sha256sum -c SHA256SUMS
```

Tất cả dòng kiểm tra phải báo `OK`. Installer cũng tự kiểm tra `SHA256SUMS` trước khi thay đổi hệ thống.

## 3. Cài đặt một lệnh

Trong thư mục vừa giải nén:

```bash
sudo ./install.sh
```

Hoặc kích hoạt lệnh cài từ máy quản trị sau khi đã chép và giải nén bundle:

```bash
ssh -t user@IP_MINIPC 'cd ~/neuron-minipc-bundle-<phiên-bản> && sudo ./install.sh'
```

Installer sẽ tự động:

1. nhận diện file `neuron-stack-*.tar` và ba image đi kèm;
2. kiểm tra checksum và kiến trúc CPU;
3. nạp image mà không cần registry;
4. seed đầy đủ `neuron.json`, `zlog.conf`, migration và danh sách plugin;
5. lưu dữ liệu dưới `/opt/neuron-minipc/data`;
6. khởi động và chờ cả ba dịch vụ ở trạng thái `healthy`.

Sau khi thành công, mở:

```text
http://IP_MINIPC/
```

Tài khoản mặc định của Neuron là `admin` / `0000`. Hãy đổi mật khẩu ngay sau lần đăng nhập đầu tiên.

## 4. Cấu hình kết nối từ xa

### 4.1 Chuẩn bị token gọi Neuron cục bộ

GatewayAgent cần một JWT hợp lệ của Neuron để gọi API local. JWT do bản Neuron hiện tại phát hành hết hạn sau 1 giờ và stub pilot chưa tự refresh; vì vậy đây là giới hạn vận hành bắt buộc phải xử lý trước production. Đặt token vào file cấu hình:

```bash
sudo nano /opt/neuron-minipc/.env
```

Sửa dòng:

```dotenv
REMOTE_NEURON_TOKEN=<JWT_CUA_NEURON>
```

Sau đó áp dụng:

```bash
cd /opt/neuron-minipc
sudo docker compose up -d --force-recreate remote-stub
sudo docker compose up -d
```

Không gửi token qua chat/email và không lưu token vào Git. Khi JWT hết hạn, đăng nhập Neuron để lấy token mới, cập nhật dòng trên rồi recreate `remote-stub` bằng hai lệnh ở trên.

### 4.2 Khai báo Remote Control trên Dashboard

Vào **Cấu hình → Điều khiển từ xa** và nhập:

- `Gateway ID`: mã duy nhất, ví dụ `gw_nhamay_001`.
- `Control Server URL`: `wss://<ten-mien-control-server>/reverse-channel`.
- `Auth mode`: dùng đúng chế độ do control server cấp.
- `Heartbeat`: khuyến nghị `20` giây.
- `Reconnect`: khuyến nghị `3` giây.
- `Dry-run default`: nên bật trong giai đoạn chạy thử.

Thực hiện lần lượt **Lưu → Kiểm tra kết nối → Kết nối**. Sau khi kết nối thành công, trạng thái `enabled` được lưu và agent tự khởi động lại cùng container/host. Chứng chỉ TLS của control server phải hợp lệ và khớp hostname. Không đặt `REMOTE_TLS_INSECURE=1` ngoài môi trường lab.

## 5. Kiểm tra sau cài

```bash
cd /opt/neuron-minipc
sudo docker compose ps
HTTP_PORT=$(awk -F= '$1 == "NEURON_HTTP_PORT" { print $2 }' .env)
curl -fsS "http://127.0.0.1:${HTTP_PORT:-80}/" >/dev/null && echo "Dashboard/Proxy: OK"
curl -fsS "http://127.0.0.1:${HTTP_PORT:-80}/api/v2/remote/connection/status"
```

Ba container sau phải là `healthy`:

- `neuron-minipc`
- `neuron-remote-stub`
- `neuron-edge-proxy`

Xem log khi cần:

```bash
cd /opt/neuron-minipc
sudo docker compose logs --tail=200 neuron remote-stub edge-proxy
```

## 6. Dữ liệu và cập nhật

Dữ liệu cần sao lưu nằm tại:

```text
/opt/neuron-minipc/data/config
/opt/neuron-minipc/data/persistence
/opt/neuron-minipc/data/remote-stub
/opt/neuron-minipc/.env
```

Trước khi sao lưu, dừng stack để SQLite và các file cấu hình ở trạng thái nhất quán:

```bash
cd /opt/neuron-minipc
sudo docker compose down
```

Sau đó sao lưu toàn bộ thư mục `/opt/neuron-minipc`. Để dùng bundle mới, giải nén bundle mới rồi chạy lại `sudo ./install.sh`. Installer giữ token/cổng/dữ liệu hiện có và tự cập nhật ba image tag theo bundle mới. Chỉ đặt `KEEP_EXISTING_IMAGE_TAGS=1` khi bạn chủ động muốn giữ image cũ để xử lý sự cố hoặc rollback.

## 7. Dừng hoặc gỡ stack

Dừng nhưng giữ dữ liệu:

```bash
cd /opt/neuron-minipc
sudo docker compose down
```

Khởi động lại:

```bash
cd /opt/neuron-minipc
sudo docker compose up -d
```

Không xóa `/opt/neuron-minipc/data` nếu còn cần cấu hình và lịch sử vận hành.

## 8. Xử lý lỗi nhanh

| Hiện tượng | Kiểm tra | Cách xử lý |
|---|---|---|
| Báo sai kiến trúc image | `uname -m`, xem `BUNDLE-MANIFEST.txt` | Dùng bundle `arm64` cho CM4 hoặc bundle `amd64` cho PC Intel/AMD |
| Cổng 80 đã được dùng | `sudo ss -ltnp | grep ':80 '` | Đổi `NEURON_HTTP_PORT` trong `/opt/neuron-minipc/.env`, rồi `docker compose up -d` |
| Neuron `unhealthy` | `docker compose logs neuron` | Kiểm tra quyền và file trong `data/config`; chạy lại installer để seed file còn thiếu |
| `TLS_FAILED` | hostname/cert/CA của control server | Cấp chứng chỉ hợp lệ; không tắt verify ở production |
| `AUTH_FAILED` hoặc API Neuron trả 401 | JWT trong `.env` | Tạo JWT mới, cập nhật `REMOTE_NEURON_TOKEN`, recreate `remote-stub` |
| `EDGE_OFFLINE` | trạng thái Remote Control và outbound firewall | Kiểm tra DNS, cổng WSS, proxy/firewall và heartbeat |
| Cài offline vẫn cần mạng | Docker chưa có trên máy | Cài sẵn Docker Engine + Compose v2 bằng bộ cài nội bộ |

## 9. Giới hạn trước khi đưa vào production

Trước khi vận hành thật, cần bổ sung tối thiểu: cơ chế refresh/service credential thay cho JWT 1 giờ, xác thực/RBAC cho API remote, mTLS hai chiều thật, ký lệnh HMAC end-to-end, chống replay/idempotency, lưu gateway/command vào cơ sở dữ liệu, audit log, rotate secret/certificate, TLS cho Dashboard, giám sát và quy trình rollback đã kiểm thử.
