# 💡 すでにAWSに存在するパブリックEC2を特定します
data "aws_instance" "existing_web" {
  filter {
    name   = "tag:Name"
    values = ["git-actions-public-ec2"]
  }
}

# 🚀 そのEC2に対して、PHPのバグを直したスクリプト（<?php）を送り込んで、アパッチを再起動します
resource "null_resource" "update_php" {
  # コードが変更されたら毎回実行するためのトリガー
  triggers = {
    script_hash = md5(local.php_script)
  }

  # 遠隔でEC2の中身（index.php）を正しいコードで上書きする命令
  provisioner "remote-exec" {
    inline = [
      "echo '${local.php_script}' > /tmp/index.php",
      "sudo mv /tmp/index.php /var/www/html/index.php",
      "sudo chown root:root /var/www/html/index.php",
      "sudo systemctl restart httpd"
    ]
  }
}

# 🛠️ 修正版の正しいPHPプログラム（中身を完全に <?php に修正したもの）
locals {
  php_script = <<-EOF
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
              EOF
}

# 🌐 確認用URLをもう一度出力します
output "web_public_url" {
  value       = "http://${data.aws_instance.existing_web.public_ip}"
}
