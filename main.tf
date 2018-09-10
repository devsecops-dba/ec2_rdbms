provider "aws" {
  region  = "${var.aws_region}"
}

#-------------VPC-----------

resource "aws_vpc" "sanjeevk_vpc" {
  cidr_block           = "${var.vpc_cidr}"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags {
    Name = "sanjeevk_vpc"
  }
}

#internet gateway

resource "aws_internet_gateway" "sanjeevk_internet_gateway" {
  vpc_id = "${aws_vpc.sanjeevk_vpc.id}"
  tags {
    Name = "sanjeevk_igw"
  }
}

# Route tables

resource "aws_route_table" "sanjeevk_public_rt" {
  vpc_id = "${aws_vpc.sanjeevk_vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.sanjeevk_internet_gateway.id}"
  }

  tags {
    Name = "sanjeevk_public_rt"
  }
}

resource "aws_default_route_table" "sanjeevk_private_rt" {
  default_route_table_id = "${aws_vpc.sanjeevk_vpc.default_route_table_id}"

  tags {
    Name = "sanjeevk_private_rt"
  }
}

resource "aws_subnet" "sanjeevk_public_subnet" {
  vpc_id                  = "${aws_vpc.sanjeevk_vpc.id}"
  cidr_block              = "${var.cidrs["public"]}"
  map_public_ip_on_launch = true
  availability_zone       = "${data.aws_availability_zones.available.names[0]}"

  tags {
    Name = "sanjeevk_public_sn"
  }
}

resource "aws_subnet" "sanjeevk_private_subnet" {
  vpc_id                  = "${aws_vpc.sanjeevk_vpc.id}"
  cidr_block              = "${var.cidrs["private"]}"
  map_public_ip_on_launch = false
  availability_zone       = "${data.aws_availability_zones.available.names[0]}"

  tags {
    Name = "sanjeevk_private_sn"
  }
}


# Subnet Associations

resource "aws_route_table_association" "sanjeevk_public_assoc" {
  subnet_id      = "${aws_subnet.sanjeevk_public_subnet.id}"
  route_table_id = "${aws_route_table.sanjeevk_public_rt.id}"
}

resource "aws_route_table_association" "sanjeevk_private_assoc" {
  subnet_id      = "${aws_subnet.sanjeevk_private_subnet.id}"
  route_table_id = "${aws_default_route_table.sanjeevk_private_rt.id}"
}

#Security groups

resource "aws_security_group" "sanjeevk_dev_sg" {
  name        = "sanjeevk_dev_sg"
  description = "Used for access to the dev instance"
  vpc_id      = "${aws_vpc.sanjeevk_vpc.id}"

  #SSH

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.localip}"]
  }

  #HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["${var.localip}"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#Public Security group

resource "aws_security_group" "sanjeevk_public_sg" {
  name        = "sanjeevk_public_sg"
  description = "Used for public and private instances for load balancer access"
  vpc_id      = "${aws_vpc.sanjeevk_vpc.id}"

  #HTTP 

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  #Outbound internet access

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#Private Security Group

resource "aws_security_group" "sanjeevk_private_sg" {
  name        = "sanjeevk_private_sg"
  description = "Used for private instances"
  vpc_id      = "${aws_vpc.sanjeevk_vpc.id}"

  # Access from other security groups
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${var.vpc_cidr}"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#rdbms security group
resource "aws_security_group" "sanjeevk_rdbms_sg" {
  name        = "sanjeevk_rdbms_sg"
  description = "Used for DB instances"
  vpc_id      = "${aws_vpc.sanjeevk_vpc.id}"

  # sql access from public/private security group
  ingress {
    from_port = 1521
    to_port   = 1521
    protocol  = "tcp"

    security_groups = ["${aws_security_group.sanjeevk_dev_sg.id}",
      "${aws_security_group.sanjeevk_public_sg.id}",
      "${aws_security_group.sanjeevk_private_sg.id}",
    ]
  }
}

#---------compute-----------
#key pair

resource "aws_key_pair" "sanjeevk_auth" {
  key_name   = "${var.key_name}"
  public_key = "${file(var.public_key_path)}"
}

#user_data
data "template_file" "user-init" {
   template = "${file("bootstrap.sh")}"

  vars {
    region = "${var.aws_region}"
    avail_zone = "${aws_subnet.sanjeevk_public_subnet.availability_zone.id}"
    rdbms_bucket = "${var.rdbms_bucket}"
    shmall = "${var.shmall}"
    shmmax = "${var.shmmax}"
    asmpass = "${var.asmpass}"
    dbport = "${var.dbport}"
  }
}

# ec2 instance
resource "aws_instance" "sanjeevk_rdbms_dev" {
  instance_type = "${var.dev_instance_type}"
  ami           = "${var.dev_ami}"

  tags {
    Name = "sanjeevk_rdbms_dev"
  }

  key_name               = "${aws_key_pair.sanjeevk_auth.id}"
  vpc_security_group_ids = ["${aws_security_group.sanjeevk_dev_sg.id}"]
  iam_instance_profile   = "${var.profile}"
  subnet_id              = "${aws_subnet.sanjeevk_public_subnet.id}"
  user_data              = "${data.template_file.user-init.rendered}"
}


#------------outputs----------------
output "rdbms public ip" {
   value = "${aws_instance.sanjeevk_rdbms_dev.public_ip}"
}
