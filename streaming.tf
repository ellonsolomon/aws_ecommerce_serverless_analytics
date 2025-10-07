resource "aws_kinesis_stream" "data_stream" {
  name             = "${local.name_prefix}-stream"
  shard_count      = local.kinesis_shards
  retention_period = 24

  shard_level_metrics = [
    "IncomingBytes",
    "OutgoingBytes",
  ]

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = local.common_tags
}
