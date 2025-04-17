variable "aws_access_key_id" {
  description = "AWS Access Key"
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS Secret Key"
  type        = string
  sensitive   = true
}

variable "api_key" {
  description = "API key for Generative Engine"
  type        = string
  sensitive   = true
}

variable "ui_password" {
  description = "Password for UI login"
  type        = string
  sensitive   = true
}

