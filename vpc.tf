# 1. VPCの定義（前回作ったものと同じ）
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "git-actions-vpc"
  }
}

# 2. パブリックサブネット（インターネットと通信できる部屋）
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id # 👈 上で作ったVPCと紐付けるマジックコード
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-1a" # 東京リージョンの「A区域」
  map_public_ip_on_launch = true              # この部屋に入ったサーバーには自動で外向けのIPを配る設定

  tags = {
    Name = "git-actions-public-subnet"
  }
}

# 3. プライベートサブネット（インターネットから隔離された秘密の部屋）
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id # 👈 これも同じVPCに紐付け
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-northeast-1a"

  tags = {
    Name = "git-actions-private-subnet"
  }
}
