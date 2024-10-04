/* EC2 user data */

resource "aws_s3_bucket" "user_data" {
  force_destroy = true
}

resource "aws_s3_object" "user_data" {
  bucket = aws_s3_bucket.user_data.bucket
  for_each = fileset("${path.module}/user_data/", "*")
  key = each.value
  source = "${path.module}/user_data/${each.value}"
  etag = filemd5("${path.module}/user_data/${each.value}")
}

/* EC2 launch template */

data "aws_ami" "this" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-arm64-gp2"]
  }
}

locals {
  user_data_hash = sha1(join("", [for f in fileset(path.module, "user_data/**") : filesha1("${path.module}/${f}")]))
}

resource "aws_launch_template" "experiments_k8s_control_plane_template" {
  image_id      = data.aws_ami.this.id
  instance_type = "t4g.medium"
  depends_on = [aws_s3_object.user_data]

  user_data = base64encode(<<EOF
#!/bin/bash
export HOME=/root
mkdir /root/init
cd /root/init
# trigger: ${local.user_data_hash}
aws s3 cp --recursive s3://${aws_s3_bucket.user_data.bucket}/ ./
chmod +x init.sh
./init.sh && rm -rf /root/init # keep init files around for debugging
EOF
  )

  key_name = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.this.id]
  block_device_mappings {
    # swap
    device_name = "/dev/sdf"
    ebs {
      volume_size = 8
      volume_type = "gp3"
      delete_on_termination = "true"
    }
  }

  iam_instance_profile {
    arn = aws_iam_instance_profile.this.arn
  }
}