provider "aws" {
  region  = "${var.aws_region}"
}

#-------------VPC-----------

resource "aws_vpc" "fss_vpc" {
  cidr_block           = "${var.vpc_cidr}"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags {
    Name = "fss_vpc"
  }
}

#internet gateway

resource "aws_internet_gateway" "fss_internet_gateway" {
  vpc_id = "${aws_vpc.fss_vpc.id}"
  tags {
    Name = "fss_igw"
  }
}

# Route tables

resource "aws_route_table" "fss_public_rt" {
  vpc_id = "${aws_vpc.fss_vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.fss_internet_gateway.id}"
  }

  tags {
    Name = "fss_public"
  }
}

resource "aws_default_route_table" "fss_private_rt" {
  default_route_table_id = "${aws_vpc.fss_vpc.default_route_table_id}"

  tags {
    Name = "fss_private"
  }
}

resource "aws_subnet" "fss_public_subnet" {
  vpc_id                  = "${aws_vpc.fss_vpc.id}"
  cidr_block              = "${var.cidrs["public"]}"
  map_public_ip_on_launch = true
  availability_zone       = "${data.aws_availability_zones.available.names[0]}"

  tags {
    Name = "fss_public"
  }
}

resource "aws_subnet" "fss_private_subnet" {
  vpc_id                  = "${aws_vpc.fss_vpc.id}"
  cidr_block              = "${var.cidrs["private"]}"
  map_public_ip_on_launch = false
  availability_zone       = "${data.aws_availability_zones.available.names[0]}"

  tags {
    Name = "fss_private"
  }
}


# Subnet Associations

resource "aws_route_table_association" "fss_public_assoc" {
  subnet_id      = "${aws_subnet.fss_public_subnet.id}"
  route_table_id = "${aws_route_table.fss_public_rt.id}"
}

resource "aws_route_table_association" "fss_private_assoc" {
  subnet_id      = "${aws_subnet.fss_private_subnet.id}"
  route_table_id = "${aws_default_route_table.fss_private_rt.id}"
}

#Security groups

resource "aws_security_group" "fss_dev_sg" {
  name        = "fss_dev_sg"
  description = "Used for access to the dev instance"
  vpc_id      = "${aws_vpc.fss_vpc.id}"

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

resource "aws_security_group" "fss_public_sg" {
  name        = "fss_public_sg"
  description = "Used for public and private instances for load balancer access"
  vpc_id      = "${aws_vpc.fss_vpc.id}"

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

resource "aws_security_group" "fss_private_sg" {
  name        = "fss_private_sg"
  description = "Used for private instances"
  vpc_id      = "${aws_vpc.fss_vpc.id}"

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
resource "aws_security_group" "fss_rdbms_sg" {
  name        = "fss_rdbms_sg"
  description = "Used for DB instances"
  vpc_id      = "${aws_vpc.fss_vpc.id}"

  # sql access from public/private security group
  ingress {
    from_port = 1521
    to_port   = 1521
    protocol  = "tcp"

    security_groups = ["${aws_security_group.fss_dev_sg.id}",
      "${aws_security_group.fss_public_sg.id}",
      "${aws_security_group.fss_private_sg.id}",
    ]
  }
}

#---------compute-----------
#key pair

resource "aws_key_pair" "fss_auth" {
  key_name   = "${var.key_name}"
  public_key = "${file(var.public_key_path)}"
}

#rdbms server
resource "aws_instance" "fss_rdbms_dev" {
  instance_type = "${var.dev_instance_type}"
  ami           = "${var.dev_ami}"

  tags {
    Name = "fss_rdbms_dev"
  }

  key_name               = "${aws_key_pair.fss_auth.id}"
  vpc_security_group_ids = ["${aws_security_group.fss_dev_sg.id}"]
  iam_instance_profile   = "${var.s3_access_profile}"
  subnet_id              = "${aws_subnet.fss_public_subnet.id}"

}

#------------outputs----------------
output "rdbms public ip" {
   value = "${aws_instance.fss_rdbms_dev.public_ip}"
}
