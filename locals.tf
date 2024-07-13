locals {
  region = "ap-southeast-1"

  bucket_name = "tsanghan-ce6-${local.random.Name}-cloudfront"

  name = "tsanghan-ce6"

  common_tags = {
    Name = "${local.name}"
  }

  random = {
    Name = "${random_id.server.hex}"
  }

  s3_origin_id = "myS3Origin"

}

resource "random_id" "server" {
  byte_length = 4
}
