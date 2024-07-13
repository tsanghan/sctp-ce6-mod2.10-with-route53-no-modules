resource "aws_s3_bucket" "mybucket" {
  bucket        = local.bucket_name
  force_destroy = true

  tags = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "enable_public_access" {
  bucket = aws_s3_bucket.mybucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false

}

resource "aws_s3_bucket_policy" "allow_access_from_cloudfront" {
  bucket = aws_s3_bucket.mybucket.id
  policy = data.aws_iam_policy_document.bucket_policy.json
}

resource "aws_cloudfront_origin_access_control" "example" {
  name                              = "example"
  description                       = "Example Policy"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "s3_distribution" {

  origin {
    domain_name              = aws_s3_bucket.mybucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.example.id
    origin_id                = local.s3_origin_id
  }

  enabled             = true
  comment             = "Tsang Han's awesome CloudFront with Route 53 & TLS Certificcate - No Modules - ${local.random.Name}"
  default_root_object = "index.html"

  aliases = ["${local.name}-cloudfront.${data.aws_route53_zone.selected.name}"]

  default_cache_behavior {
    cache_policy_id        = data.aws_cloudfront_cache_policy.example.id
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "allow-all"

    function_association {
      event_type   = "viewer-response"
      function_arn = aws_cloudfront_function.security_headers.arn
    }

  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cert.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }

}

resource "aws_cloudfront_function" "security_headers" {
  name    = "security_headers"
  runtime = "cloudfront-js-2.0"
  comment = "add security headers"
  publish = true
  code    = file("function/function.js")
}

resource "aws_route53_record" "tsanghan-ce6" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "${local.name}-cloudfront.${data.aws_route53_zone.selected.name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }

}

resource "aws_route53_record" "tsanghan-ce6-caa" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = data.aws_route53_zone.selected.name
  type    = "CAA"
  ttl     = 60
  records = ["0 issue \"amazon.com\""]
}

resource "aws_acm_certificate" "cert" {
  provider = aws.ue1

  domain_name       = "${local.name}-cloudfront.${data.aws_route53_zone.selected.name}"
  validation_method = "DNS"

  tags = local.common_tags

}

resource "aws_route53_record" "validation" {
  # provider = aws.ue1
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.selected.zone_id
}

resource "aws_acm_certificate_validation" "cert" {
  provider                = aws.ue1
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}

module "template_files" {
  source   = "hashicorp/dir/template"
  base_dir = "static-website"
  template_vars = {
    # Pass in any values that you wish to use in your templates.
    vpc_id = "vpc-abc123"
  }
}

module "s3-bucket_object" {
  source  = "terraform-aws-modules/s3-bucket/aws//modules/object"
  version = "4.1.2"

  for_each     = module.template_files.files
  bucket       = aws_s3_bucket.mybucket.id
  key          = each.key
  file_source  = each.value.source_path
  content_type = each.value.content_type
  etag         = each.value.digests.md5
}
