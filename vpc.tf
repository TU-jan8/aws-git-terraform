# 💡 1. 今動いているパブリックEC2を特定して情報を取ってくる
data "aws_instance" "existing_web" {
  filter {
    name   = "tag:Name"
    values = ["git-actions-public-ec2"]
  }
}

# 🚀 2. AWSのSSM機能を使って、正しい文法でEC2のPHPを上書きする
resource "aws_ssm_association" "update_php" {
  name = "AWS-RunShellScript"

  # 正しいターゲットの指定方法
  targets {
    key    = "InstanceIds"
    values = [data.aws_instance.existing_web.id]
  }

  # 正しいパラメータの指定方法（値を文字列として渡す）
  parameters = {
    commands = "cat << 'PHP' > /var/www/html/index.php\n${local.php_script}\nPHP\nchown root:root /var/www/html/index.php\nsystemctl restart httpd"
  }
}

# 🛠️ 3. 修正版の正しいPHPプログラム
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

# 🌐 4. 確認用URLを出力
output "web_public_url" {
  value       = "http://${data.aws_instance.existing_web.public_ip}"
}
