data "aws_availability_zones" "available" {}
variable "aws_region" {}
variable "vpc_cidr" {}
variable "cidrs" {
   type = "map"
}
variable "localip" {}
variable "key_name" {}
variable "public_key_path" {}
variable "dev_instance_type" {}
variable "dev_ami" {}
variable "profile" {}
variable "myfile" {}
variable "rdbms_bucket" {}
