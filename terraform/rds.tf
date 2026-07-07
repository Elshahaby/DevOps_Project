resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-rds-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-rds-subnet-group"
  }
}

resource "aws_db_instance" "sql_server" {
  identifier = "${var.project_name}-sqlserver"
  
  # 20 GB space for DataBase
  allocated_storage = 20   

  engine         = "sqlserver-ex"
  engine_version = "15.00"
  instance_class = "db.t3.micro"

  username = var.rds_master_username
  password = var.rds_master_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false
  skip_final_snapshot = true

  # SQL Server Express licensing
  license_model = "license-included"

  tags = {
    Name = "${var.project_name}-sqlserver"
  }
}
