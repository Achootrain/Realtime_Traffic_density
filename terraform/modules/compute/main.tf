# ===========================================
# Compute Module — EC2 + K3s
# ===========================================

# Find latest Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# SSH Key Pair
data "local_file" "ssh_public_key" {
  filename = pathexpand(var.ssh_public_key_path)
}

resource "aws_key_pair" "k3s" {
  key_name   = "${var.project_name}-k3s-key"
  public_key = trimspace(data.local_file.ssh_public_key.content)

  tags = {
    Name = "${var.project_name}-k3s-key"
  }
}

# EC2 Instance
resource "aws_instance" "k3s" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.k3s.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]

  user_data = file("${path.module}/userdata.sh")

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${var.project_name}-k3s-root"
    }
  }

  tags = {
    Name = "${var.project_name}-k3s"
  }

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

# Wait for K3s to be fully ready
resource "null_resource" "wait_for_k3s" {
  depends_on = [aws_instance.k3s]

  triggers = {
    instance_id = aws_instance.k3s.id
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(var.ssh_private_key_path)
    host        = aws_instance.k3s.public_ip
    timeout     = "10m"
  }

  # Wait for cloud-init to finish (K3s install via user-data)
  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait || true",
      "echo 'Waiting for K3s API server...'",
      "timeout 300 bash -c 'until kubectl get nodes 2>/dev/null | grep -q \" Ready\"; do sleep 10; echo \"Still waiting...\"; done'",
      "echo 'K3s is ready!'",
      "kubectl get nodes",
    ]
  }
}
