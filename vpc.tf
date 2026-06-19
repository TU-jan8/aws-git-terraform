# ========================================================
# 1. VPC & サブネット
# ========================================================
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "git-actions-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = true
  tags                 = { Name = "git-actions-public-subnet" }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-northeast-1a"
  tags              = { Name = "git-actions-private-subnet" }
}

# ========================================================
# 2. インターネットゲートウェイ (IGW) & NATゲートウェイ (NAT-GW)
# ========================================================
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "git-actions-igw" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "git-actions-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags          = { Name = "git-actions-nat-gw" }
  depends_on    = [aws_internet_gateway.igw]
}

# ========================================================
# 3. ルートテーブル (道案内)
# ========================================================
# 【パブリック】IGWへ流す
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "git-actions-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# 【プライベート】NAT-GWへ流す
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "git-actions-private-rt" }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ========================================================
# 4. セキュリティグループ (SG)
# ========================================================
# Webサーバー用：外の世界からHTTP/HTTPS/SSHを許可
resource "aws_security_group" "web_sg" {
  name        = "git-actions-web-sg"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "git-actions-web-sg" }
}

# DBサーバー用：Webサーバーからの通信（マリアDBの3306番ポート）のみを許可
resource "aws_security_group" "db_sg" {
  name        = "git-actions-db-sg"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "git-actions-db-sg" }
}

# ========================================================
# 5. EC2 サーバー & サーバー内セットアップ（User Data）
# ========================================================
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}

# プライベートEC2 (先にDBがないとWebが繋げないので上に配置)
resource "aws_instance" "private_db" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  private_ip             = "10.0.2.10"

  # 🚀 サーバー起動時に自動でMariaDBを入れ、テスト用テーブルを作るスクリプト
  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y mariadb105-server
              systemctl start mariadb
              systemctl enable mariadb
              
              # テスト用データベースとテーブル作成、Webサーバー用ユーザーの許可
              mysql -e "CREATE DATABASE IF NOT EXISTS testdb;"
              mysql -e "CREATE TABLE IF NOT EXISTS testdb.messages (id INT AUTO_INCREMENT PRIMARY KEY, content TEXT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);"
              mysql -e "CREATE USER 'webuser'@'%' IDENTIFIED BY 'Password123!';"
              mysql -e "GRANT ALL PRIVILEGES ON testdb.* TO 'webuser'@'%';"
              mysql -e "FLUSH PRIVILEGES;"
              EOF

  tags = { Name = "git-actions-private-ec2" }
}

# パブリックEC2
resource "aws_instance" "public_web" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  depends_on             = [aws_instance.private_db]

  # 🚀 ⚙️ サーバー起動時の自動設定スクリプト（PHPの開始タグを <?php に完全修正）
  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y httpd php php-mysqlnd
              systemctl start httpd
              systemctl enable httpd
              
              # 簡単なデータ入力フォーム兼表示用のPHPプログラムを配置
              cat << 'PHP' > /var/www/html/index.php
              <?php
              \$conn = new mysqli('10.0.2.10', 'webuser', 'Password123!', 'testdb');
              if (\$conn->connect_error) { die("接続失敗: " . \$conn->connect_error); }

              if (\$_SERVER['REQUEST_METHOD'] === 'POST' && !empty(\$_POST['content'])) {
                  \$stmt = \$conn->prepare("INSERT INTO messages (content) VALUES (?)");
                  \$stmt->bind_param("s", \$_POST['content']);
                  \$stmt->execute();
              }
              ?>
              <!DOCTYPE html>
              <html>
              <head><meta charset="utf-8"><title>AWS Test</title></head>
              <body>
                <h2>DB格納テストフォーム</h2>
                <form method="POST">
                  <input type="text" name="content" placeholder="ここに文字を入力" required>
                  <button type="submit">DBに保存</button>
                </form>
                <h3>保存されたデータ一覧:</h3>
                <ul>
                <?php
                \$result = \$conn->query("SELECT content, created_at FROM messages ORDER BY id DESC");
                while (\$row = \$result->fetch_assoc()) {
                    echo "<li>" . htmlspecialchars(\$row['content']) . " (" . \$row['created_at'] . ")</li>";
                }
                ?>
                </ul>
              </body>
              </html>
              PHP
              EOF

  tags = { Name = "git-actions-public-ec2" }
}

# ========================================================
# 6. アウトプット（確認用URLの出力）
# ========================================================
output "web_public_url" {
  value       = "http://${aws_instance.public_web.public_ip}"
  description = "WebサーバーのURLです。ブラウザで開いてみてください！"
}
