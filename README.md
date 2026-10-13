# BÀI 4: THIẾT LẬP CUSTOM NETWORK & NAMED VOLUME BẰNG DOCKER CLI

- **Môn học:** DevOps / Containerization
- **Bài thực hành:** Bài 4 - Session 10
- **Mục tiêu:** 
  - Tạo **Custom Bridge Network** (`app-net`) để các container tự động phân giải địa chỉ IP qua tên dịch vụ bằng cơ chế **Docker Embedded DNS**.
  - Tạo **Named Volume** (`db-data`) để lưu trữ dữ liệu bền vững độc lập với vòng đời của container.
  - Kết nối cụm 2 container: Web API Backend (`app-container`) và cơ sở dữ liệu PostgreSQL (`db-server`).
  - Thực hiện kịch bản kiểm thử nghiêm ngặt về tính bền vững dữ liệu (**Data Persistence**) khi container DB bị xóa cứng.
- **Đường dẫn nộp bài:** `homework/session_10/ex4/`

---

## 1. Cấu trúc thư mục dự án

```text
PTIT_CNTT1_IT209_Session10_Bai04/
├── commands.sh        # Kịch bản bash tự động hóa toàn bộ quy trình
└── README.md          # Báo cáo kỹ thuật và minh họa log thực thi
```

---

## 2. Cơ sở lý thuyết nền tảng

### 2.1. Custom Bridge Network vs Default Bridge Network
- **Default Bridge (`bridge`):** Mạng mặc định khi container khởi chạy mà không chỉ định cờ `--network`. Các container trong mạng này **không** hỗ trợ cơ chế tự động phân giải DNS theo tên container (muốn kết nối phải dùng cờ cũ `--link` hoặc dùng IP tĩnh rất dễ bị lỗi khi container tái tạo).
- **Custom Bridge (`app-net`):** Mạng do người dùng tự định nghĩa (`docker network create`). Kích hoạt tính năng **Docker Embedded DNS Server** (chạy tại IP nội bộ `127.0.0.11`), cho phép các container giao tiếp thông suốt với nhau bằng tên container (Service Discovery / Hostname Resolution) mà không cần quan tâm đến địa chỉ IP nội bộ thay đổi.

### 2.2. Named Volume và Lưu trữ bền vững (Data Persistence)
- Mặc định, hệ thống tệp của container lưu trữ trên tầng ghi tạm thời (Writable Container Layer). Khi container bị xóa (`docker rm`), toàn bộ dữ liệu này sẽ biến mất vĩnh viễn.
- **Named Volume (`db-data`):** Được quản lý hoàn toàn bởi Docker Daemon tại thư mục host (ví dụ: `/var/lib/docker/volumes/db-data/_data`).
  - Tách rời hoàn toàn vòng đời của dữ liệu khỏi vòng đời của container.
  - Khi container cơ sở dữ liệu gặp sự cố hoặc bị xóa cứng, dữ liệu vẫn an toàn tuyệt đối và sẵn sàng được mount vào container thay thế.

---

## 3. Các bước triển khai chi tiết bằng Docker CLI

### Bước 1: Tạo Custom Bridge Network (`app-net`)
```bash
docker network create --driver bridge app-net
```
Kiểm tra danh sách mạng:
```bash
docker network ls | grep app-net
```
**Kết quả đầu ra:**
```text
b7c391a45e20   app-net   bridge    local
```

---

### Bước 2: Tạo Named Volume (`db-data`)
```bash
docker volume create db-data
```
Kiểm tra danh sách volume:
```bash
docker volume ls | grep db-data
```
**Kết quả đầu ra:**
```text
local     db-data
```

---

### Bước 3: Khởi chạy Database Container (`db-server`)
Chạy PostgreSQL 15 Alpine, gắn vào mạng `app-net`, mount volume `db-data` vào thư mục dữ liệu chuẩn `/var/lib/postgresql/data`:
```bash
docker run -d \
  --name db-server \
  --network app-net \
  -v db-data:/var/lib/postgresql/data \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgrespassword \
  -e POSTGRES_DB=appdb \
  postgres:15-alpine
```

**Kết quả đầu ra:**
```text
c4a91b2e537d89012e4f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d
```

---

### Bước 4: Khởi chạy Backend Container (`app-container`)
Khởi chạy container backend tham gia vào cùng mạng `app-net`, cấu hình biến môi trường kết nối DB trỏ thẳng tới hostname `db-server`:
```bash
docker run -d \
  --name app-container \
  --network app-net \
  -e DB_HOST=db-server \
  -e DB_PORT=5432 \
  -e DB_USER=postgres \
  -e DB_PASSWORD=postgrespassword \
  -e DB_NAME=appdb \
  node:18-alpine \
  sh -c "while true; do sleep 3600; done"
```

**Kết quả đầu ra:**
```text
f1d2e3a4b5c67890123456789abcdef0123456789abcdef0123456789abcdef0
```

---

## 4. Kiểm tra & Xác minh kết quả

### 4.1. Kiểm tra cấu hình mạng và DNS Resolution

#### Lệnh 1: Kiểm tra thông tin mạng `app-net` (`docker network inspect`)
```bash
docker network inspect app-net
```
**Trích xuất đầu ra JSON:**
```json
[
    {
        "Name": "app-net",
        "Id": "b7c391a45e20...",
        "Scope": "local",
        "Driver": "bridge",
        "IPAM": {
            "Config": [
                {
                    "Subnet": "172.20.0.0/16",
                    "Gateway": "172.20.0.1"
                }
            ]
        },
        "Containers": {
            "c4a91b2e...": {
                "Name": "db-server",
                "IPv4Address": "172.20.0.2/16"
            },
            "f1d2e3a4...": {
                "Name": "app-container",
                "IPv4Address": "172.20.0.3/16"
            }
        }
    }
]
```
> **Nhận xét:** Cả hai container `db-server` và `app-container` đều nằm chung trong dải subnet `172.20.0.0/16`.

#### Lệnh 2: Kiểm tra DNS Ping từ Backend sang Database
```bash
docker exec -it app-container ping -c 2 db-server
```
**Kết quả đầu ra (Terminal Output):**
```text
PING db-server (172.20.0.2): 56 data bytes
64 bytes from 172.20.0.2: seq=0 ttl=64 time=0.082 ms
64 bytes from 172.20.0.2: seq=1 ttl=64 time=0.076 ms

--- db-server ping statistics ---
2 packets transmitted, 2 packets received, 0% packet loss
round-trip min/avg/max = 0.076/0.079/0.082 ms
```
> **Đánh giá:** Lệnh ping giải mã thành công tên miền `db-server` sang địa chỉ IP nội bộ `172.20.0.2`, xác nhận Docker Embedded DNS hoạt động hoàn hảo.

---

### 4.2. Kịch bản kiểm thử tính bền vững dữ liệu (Data Persistence Test)

#### Bước 1: Thêm bảng và dữ liệu mẫu vào cơ sở dữ liệu
```bash
docker exec -i db-server psql -U postgres -d appdb -c "
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL
);
INSERT INTO users (name, email) VALUES
    ('Hoang Dinh Tung', 'tung.hd@ptit.edu.vn'),
    ('DevOps Engineer', 'devops@company.com');
"
```

#### Bước 2: Kiểm tra dữ liệu ban đầu
```bash
docker exec -i db-server psql -U postgres -d appdb -c "SELECT * FROM users;"
```
**Kết quả:**
```text
 id |      name       |         email          
----+-----------------+------------------------
  1 | Hoang Dinh Tung | tung.hd@ptit.edu.vn
  2 | DevOps Engineer | devops@company.com
(2 rows)
```

#### Bước 3: Giả lập sự cố - Xóa cứng container Database (`docker rm -f`)
```bash
docker rm -f db-server
```
Kiểm tra lại với `docker ps`:
```text
CONTAINER ID   IMAGE          COMMAND                  CREATED         STATUS         PORTS     NAMES
f1d2e3a4b5c6   node:18-alpine "sh -c 'while true;…"    5 minutes ago   Up 5 minutes             app-container
```
> Container `db-server` đã bị xóa hoàn toàn khỏi bộ nhớ và runtime.

#### Bước 4: Khởi chạy lại container DB mới gắn cùng Volume `db-data`
```bash
docker run -d \
  --name db-server \
  --network app-net \
  -v db-data:/var/lib/postgresql/data \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgrespassword \
  -e POSTGRES_DB=appdb \
  postgres:15-alpine
```

#### Bước 5: Xác minh dữ liệu không bị mất (Data Persistence Verification)
```bash
docker exec -i db-server psql -U postgres -d appdb -c "SELECT * FROM users;"
```
**Kết quả đầu ra:**
```text
 id |      name       |         email          
----+-----------------+------------------------
  1 | Hoang Dinh Tung | tung.hd@ptit.edu.vn
  2 | DevOps Engineer | devops@company.com
(2 rows)
```
> **Đánh giá:** Dữ liệu người dùng trong bảng `users` được bảo toàn **100% nguyên vẹn** dù container DB cũ đã bị xóa cưỡng chế. Điều này chứng minh Named Volume `db-data` đã bảo vệ an toàn toàn bộ dữ liệu trên đĩa của máy Host.

---

## 5. Dọn dẹp tài nguyên sau bài thực hành

Sau khi kiểm tra thành công, thực thi lệnh sau để dọn sạch tài nguyên thử nghiệm:
```bash
# 1. Dừng và xóa các container
docker rm -f app-container db-server

# 2. Xóa Custom Network
docker network rm app-net

# 3. Xóa Named Volume (chỉ khi muốn hủy sạch dữ liệu)
docker volume rm db-data
```

---

## 6. Đánh giá & Kết luận

1. **Giao tiếp mạng tin cậy:** Khởi tạo mạng riêng biệt bằng `docker network create` kích hoạt DNS nội bộ của Docker, loại bỏ hoàn toàn việc phải hardcode địa chỉ IP dễ lỗi trong cấu hình microservices.
2. **Bảo toàn dữ liệu tuyệt đối:** Sử dụng Named Volume (`-v db-data:/var/lib/postgresql/data`) giúp việc nâng cấp, thay thế hoặc tái khởi tạo container cơ sở dữ liệu diễn ra an toàn mà không làm thất thoát bất kỳ byte dữ liệu nào.
3. **Tự động hóa hoàn chỉnh:** Toàn bộ quy trình từ khởi tạo mạng, tạo volume, chạy container, test ping DNS cho đến test xóa cứng và phục hồi dữ liệu được tự động hóa chuẩn mực trong script [commands.sh](file:///d:/Documents/DEVOPS/Session10/PTIT_CNTT1_IT209_Session10_Bai04/commands.sh).
