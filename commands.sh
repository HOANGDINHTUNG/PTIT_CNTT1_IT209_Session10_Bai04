#!/bin/bash
# ==============================================================================
# Script: commands.sh
# Bài tập: Bài 4 - Session 10 - Thiết lập Custom Network & Named Volume
# Đường dẫn nộp bài: homework/session_10/ex4/commands.sh
# Mô tả: Tự động hóa tạo Custom Bridge Network, Named Volume, triển khai cụm
#        Container (Postgres DB + Backend), kiểm tra DNS resolution và Data Persistence.
# ==============================================================================

set -e

echo "=== BƯỚC 1: TẠO CUSTOM BRIDGE NETWORK (app-net) ==="
# Kiểm tra nếu network đã tồn tại thì xóa trước để đảm bảo môi trường sạch
if docker network inspect app-net >/dev/null 2>&1; then
    echo "Network 'app-net' đã tồn tại, đang dọn dẹp..."
    docker network rm app-net
fi
docker network create --driver bridge app-net
echo "-> Tạo thành công Custom Network: app-net"
docker network ls | grep app-net

echo ""
echo "=== BƯỚC 2: TẠO NAMED VOLUME (db-data) ==="
# Kiểm tra nếu volume chưa tồn tại thì tạo mới
if ! docker volume inspect db-data >/dev/null 2>&1; then
    docker volume create db-data
    echo "-> Tạo thành công Named Volume: db-data"
else
    echo "-> Named Volume 'db-data' đã có sẵn."
fi
docker volume ls | grep db-data

echo ""
echo "=== BƯỚC 3: KHỞI CHẠY DATABASE CONTAINER (db-server) ==="
# Dọn dẹp container cũ nếu đang tồn tại
docker rm -f db-server 2>/dev/null || true

docker run -d \
  --name db-server \
  --network app-net \
  -v db-data:/var/lib/postgresql/data \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgrespassword \
  -e POSTGRES_DB=appdb \
  postgres:15-alpine

echo "-> Khởi chạy thành công container 'db-server' (postgres:15-alpine)"
echo "Đang chờ PostgreSQL khởi động hoàn toàn (10 giây)..."
sleep 10

echo ""
echo "=== BƯỚC 4: KHỞI CHẠY BACKEND CONTAINER (app-container) ==="
# Dọn dẹp container cũ nếu đang tồn tại
docker rm -f app-container 2>/dev/null || true

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

echo "-> Khởi chạy thành công container 'app-container' tham gia vào 'app-net'"

echo ""
echo "=== BƯỚC 5: KIỂM TRA DOCKER EMBEDDED DNS RESOLUTION ==="
echo "Kiểm tra ping từ app-container sang db-server thông qua tên service:"
docker exec -it app-container ping -c 2 db-server

echo ""
echo "Kiểm tra thông tin chi tiết mạng app-net:"
docker network inspect app-net

echo ""
echo "=== BƯỚC 6: KIỂM TRA TÍNH BỀN VỮNG DỮ LIỆU (DATA PERSISTENCE) ==="
echo "6.1. Tạo bảng và chèn dữ liệu mẫu vào cơ sở dữ liệu 'appdb':"
docker exec -i db-server psql -U postgres -d appdb << 'EOF'
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO users (name, email) VALUES
    ('Hoang Dinh Tung', 'tung.hd@ptit.edu.vn'),
    ('DevOps Engineer', 'devops@company.com');
EOF

echo "6.2. Truy vấn kiểm tra dữ liệu ban đầu trong db-server:"
docker exec -i db-server psql -U postgres -d appdb -c "SELECT * FROM users;"

echo ""
echo "6.3. Giả lập sự cố: XÓA CỨNG CONTAINER DB (docker rm -f db-server)..."
docker rm -f db-server
echo "-> Container 'db-server' đã bị xóa hoàn toàn khỏi hệ thống!"

echo ""
echo "6.4. Khởi chạy lại container DB mới gắn cùng Named Volume 'db-data'..."
docker run -d \
  --name db-server \
  --network app-net \
  -v db-data:/var/lib/postgresql/data \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgrespassword \
  -e POSTGRES_DB=appdb \
  postgres:15-alpine

echo "Đang chờ PostgreSQL container mới khởi động (10 giây)..."
sleep 10

echo ""
echo "6.5. XÁC MINH DỮ LIỆU BỀN VỮNG (DATA PERSISTENCE VERIFICATION):"
docker exec -i db-server psql -U postgres -d appdb -c "SELECT * FROM users;"

echo ""
echo "=== KẾT QUẢ: TẤT CẢ CÁC BƯỚC ĐÃ THỰC THI THÀNH CÔNG RỰC RỠ! ==="
