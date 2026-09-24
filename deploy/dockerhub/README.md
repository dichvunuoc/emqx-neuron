# Neuron Remote trên Docker Desktop (Windows)

Sau khi phát hành, image public `dannvhy/neuron-remote` sẽ chứa Neuron,
remote backend và Nginx proxy trong một container. Image hỗ trợ `linux/amd64`
và `linux/arm64`; Docker tự chọn đúng kiến trúc của máy. Tag trong tài liệu này
chỉ dùng được sau khi đã xuất hiện công khai trên Docker Hub.

> Đây là bản pilot. Remote API chưa có auth/RBAC độc lập, mTLS/HMAC/replay
> protection chưa hoàn chỉnh, control server trung tâm không nằm trong image,
> JWT Neuron hiện hết hạn sau một giờ mà chưa tự refresh, và source hiện dùng
> chung khóa ký JWT thay vì sinh khóa riêng cho từng bản cài. Chỉ bind localhost.

## Windows prerequisites

1. Cài [Docker Desktop cho Windows](https://docs.docker.com/desktop/setup/install/windows-install/)
   và bật WSL 2 / Linux containers. Máy cần Windows còn được Microsoft hỗ trợ,
   CPU 64-bit có SLAT, bật virtualization trong BIOS/UEFI, WSL `2.1.5` trở lên
   và tối thiểu 8 GB RAM. Kiểm tra điều khoản sử dụng Docker Desktop nếu đây là
   doanh nghiệp lớn hoặc cơ quan nhà nước.
2. Chờ Docker Desktop báo Engine đang chạy và bật tùy chọn khởi động Docker
   Desktop khi đăng nhập Windows nếu máy dùng như gateway không người trực.
3. Mở PowerShell và kiểm tra:

```powershell
wsl --version
wsl --status
docker version
docker info --format "{{.OSType}}/{{.Architecture}}"
```

Kết quả dòng cuối phải bắt đầu bằng `linux/`. Docker Desktop không hỗ trợ
Windows Server; máy Windows Server cần phương án Linux VM riêng.

Không cài thêm Docker Engine bên trong distro WSL đang tích hợp Docker Desktop;
hai engine riêng có thể xung đột và dùng hai kho image/volume khác nhau. Sau lần
khởi động lại Windows đầu tiên, kiểm tra lại container tự chạy và có trạng thái
`healthy`.

Docker Desktop cần chạy Linux containers. Nếu Neuron phải truy cập USB/serial,
Windows/WSL cần thêm bước ánh xạ thiết bị và quyền group; trường hợp đó không
còn là luồng cài đặt một lệnh này. Kết nối công nghiệp qua TCP không cần bước đó.
Modbus simulator tích hợp dùng cổng `1502` vì tiến trình Neuron chạy bằng tài
khoản không đặc quyền trong container.

## Cài bằng một lệnh

```powershell
docker run -d --name neuron-remote --restart unless-stopped --pull=always -p 127.0.0.1:7000:8080 -v neuron-remote-data:/data dannvhy/neuron-remote:2.14.0-alpha-remote.1
```

Không cần chạy `docker pull` trước; `docker run` tự tải image nếu máy chưa có.
Mở <http://localhost:7000> sau khi container chuyển sang trạng thái `healthy`.
Đăng nhập lần đầu bằng `admin` / `0000`, rồi đổi mật khẩu ngay.

Kiểm tra:

```powershell
docker ps --filter name=neuron-remote
docker logs --tail 100 neuron-remote
docker inspect --format "{{.State.Health.Status}}" neuron-remote
```

Named volume `neuron-remote-data` giữ cấu hình, SQLite, log và cấu hình remote
khi container được thay thế hoặc nâng cấp. Volume nằm trong vùng dữ liệu Linux
của Docker Desktop/WSL; không sửa trực tiếp bằng File Explorer mà hãy dùng quy
trình backup/restore bên dưới.

## Cho phép máy khác trong LAN truy cập

Lệnh mặc định chỉ mở giao diện trên chính máy Windows. Nếu thực sự cần truy
cập từ LAN, bind đúng IP LAN của máy Windows, ví dụ
`-p 192.168.1.20:7000:8080`; không dùng `-p 7000:8080` vì nó mở trên mọi giao
diện mạng. Chỉ cho phép Windows Firewall profile `Private` và subnet/VPN cần
thiết. Không port-forward cổng này trên router và không mở trực tiếp ra Internet
khi remote API chưa có lớp xác thực riêng.

## Token cho lệnh điều khiển Neuron

Các lệnh remote gọi Neuron API cần JWT hợp lệ; nếu không có token thì giao diện
và cấu hình kết nối vẫn chạy nhưng lệnh điều khiển Neuron sẽ thất bại. Với pilot,
tạo file cấu hình cạnh nơi bạn quản trị container:

```powershell
"REMOTE_NEURON_TOKEN=THAY_BANG_TOKEN_THU_NGHIEM" | Set-Content -Encoding ascii .\neuron-remote.env
```

Sau đó thêm `--env-file .\neuron-remote.env` vào **mọi** lệnh `docker run`, kể
cả khi cài lại, update hoặc rollback. Biến môi trường vẫn có thể xem qua
`docker inspect`; token hiện hết hạn sau một giờ và chưa tự refresh. Không dùng
cách này cho vận hành unattended/production cho đến khi có secret + refresh
token đúng chuẩn. Không dán token trực tiếp vào lịch sử lệnh PowerShell.

## Backup

Sao lưu volume trước khi cập nhật vì dữ liệu có SQLite:

```powershell
docker stop neuron-remote
$Backup = "neuron-remote-data-$(Get-Date -Format yyyyMMdd-HHmmss).tgz"
docker run --rm --mount "type=volume,source=neuron-remote-data,target=/data,readonly" --mount "type=bind,source=$((Get-Location).Path),target=/backup" alpine:3.20 tar -czf "/backup/$Backup" -C /data .
docker start neuron-remote
```

Giữ file `.tgz` ở nơi an toàn và kiểm tra nó có dung lượng lớn hơn 0 byte.

## Cập nhật

Không di chuyển/ghi đè một tag release cũ. Thay `<NEW_TAG>` bằng tag mới đã
được công bố, đồng thời ghi lại tag đang chạy để có thể rollback:

```powershell
$OldTag = "2.14.0-alpha-remote.1"
$NewTag = "<NEW_TAG>"
docker pull "dannvhy/neuron-remote:$NewTag"
docker stop neuron-remote
docker rm neuron-remote
docker run -d --name neuron-remote --restart unless-stopped -p 127.0.0.1:7000:8080 -v neuron-remote-data:/data "dannvhy/neuron-remote:$NewTag"
docker inspect --format "{{.State.Health.Status}}" neuron-remote
docker logs --tail 100 neuron-remote
```

Backup trước khi chạy các lệnh trên. Không xóa volume trong quá trình cập nhật.
Chỉ hoàn tất update sau khi trạng thái là `healthy`, đăng nhập được giao diện và
kiểm tra chức năng chính. Nếu đã tạo `neuron-remote.env`, thêm
`--env-file .\neuron-remote.env` vào lệnh `docker run` ở trên.

Rollback nhanh bằng cách dừng/xóa container mới rồi chạy `$OldTag` với cùng
volume. Nếu bản mới đã migrate schema không tương thích ngược, không ghi đè
volume hiện tại: tạo volume mới từ backup rồi chạy tag cũ với volume đó:

```powershell
docker stop neuron-remote
docker rm neuron-remote
docker volume create neuron-remote-data-restore
docker run --rm --mount "type=volume,source=neuron-remote-data-restore,target=/data" --mount "type=bind,source=$((Get-Location).Path),target=/backup,readonly" alpine:3.20 tar -xzf "/backup/$Backup" -C /data
docker run -d --name neuron-remote --restart unless-stopped -p 127.0.0.1:7000:8080 -v neuron-remote-data-restore:/data "dannvhy/neuron-remote:$OldTag"
```

## Gỡ cài đặt

Xóa container nhưng giữ dữ liệu:

```powershell
docker stop neuron-remote
docker rm neuron-remote
```

Chỉ khi đã backup và muốn xóa vĩnh viễn toàn bộ dữ liệu (không thể hoàn tác):

```powershell
docker volume rm neuron-remote-data
```

## Build và phát hành (người duy trì)

Các lệnh sau là cú pháp Bash; chạy trong WSL hoặc Git Bash, không chạy trực tiếp
như cú pháp PowerShell.

Smoke build một kiến trúc:

```bash
PLATFORM=linux/arm64 ./scripts/dockerhub-release-build.sh
```

Push manifest `linux/amd64` + `linux/arm64` cùng tag `latest`:

```bash
PUSH=1 ./scripts/dockerhub-release-build.sh
```

Script từ chối phát hành khi worktree chưa commit, khi full commit SHA chưa có
trên public source remote, hoặc khi URL source không trỏ tới chính SHA đó. Image
cũng chứa source snapshot, GPL/LGPL text và notice của dashboard; không có tùy
chọn bỏ qua kiểm tra này khi push public.
